import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';

class BusMap extends StatefulWidget {
  final List<Bus> buses;
  final RouteModel? selectedRoute;
  final String? centerOnBusId;
  final bool initialDriveMode;
  final bool showMyLocation;
  final bool showMapControls;
  final bool showLocationButton;
  final MapType initialMapType;
  final Function(bool)? onDriveModeChanged;

  const BusMap({
    super.key,
    required this.buses,
    this.selectedRoute,
    this.centerOnBusId,
    this.initialDriveMode = false,
    this.showMyLocation = true,
    this.showMapControls = true,
    this.showLocationButton = true,
    this.initialMapType = MapType.normal,
    this.onDriveModeChanged,
  });

  @override
  State<BusMap> createState() => _BusMapState();
}

enum MapStyle { street, satellite, hybrid, terrain, dark }

class _BusMapState extends State<BusMap> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng _center = const LatLng(23.2599, 77.4126);
  Bus? _focusedBus;
  bool _isFollowing = false;
  bool _isDriveMode = false;
  MapType _currentMapType = MapType.normal;
  bool _showLayerSelector = false;

  // ── Map object sets — only rebuilt when GPS data changes ──────────────────
  Set<Marker>   _markers   = {};
  Set<Polyline> _polylines = {};
  Set<Circle>   _circles   = {};

  // ── Animation state ────────────────────────────────────────────────────────
  final Map<String, AnimationController> _markerAnims    = {};
  final Map<String, LatLng>              _animatedPos     = {};
  final Map<String, double>              _animatedHeading = {};
  final Map<String, List<LatLng>>       _busTrails       = {};

  // ── Polyline flow — 8fps timer, only touches route_flow polyline ───────────
  Timer? _flowTimer;
  double _flowOffset = 0.0;

  // ── Camera debounce ───────────────────────────────────────────────────────
  Timer? _cameraDebounce;
  bool   _mapReady = false;

  // ── Icon caches ───────────────────────────────────────────────────────────
  final Map<String, BitmapDescriptor> _busIcons        = {};
  final Map<String, BitmapDescriptor> _focusedBusIcons = {};
  BitmapDescriptor? _stopIcon;
  BitmapDescriptor? _lastStopIcon;

  static const int    _maxTrail         = 20;
  static const LatLng _bhopal           = LatLng(23.2599, 77.4126);
  static const double _trailMinDistM    = 8.0;

  String? _darkMapStyle;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _isDriveMode   = widget.initialDriveMode;
    _isFollowing   = widget.initialDriveMode;
    _currentMapType = widget.initialMapType;

    _buildDarkMapStyle();

    // Flow: update at ~8fps (every 125ms) — only changes the dashed overlay
    _flowTimer = Timer.periodic(const Duration(milliseconds: 125), (_) {
      if (!mounted) return;
      _flowOffset = (_flowOffset + 2.5) % 20.0;
      _updateFlowPolyline();
    });

    // Precache icons and then build initial markers
    _precacheIcons().then((_) => _rebuildMapObjects());
  }

  @override
  void didUpdateWidget(covariant BusMap old) {
    super.didUpdateWidget(old);

    bool needsRebuild = false;

    for (final bus in widget.buses) {
      final newPos = LatLng(bus.currentLat, bus.currentLng);
      final oldPos = _animatedPos[bus.id];

      // Precache icon if new bus
      if (!_busIcons.containsKey(bus.id)) {
        final label = _busLabel(bus.id);
        _ensureBusIcon(bus.id, label, isFocused: false);
        _ensureBusIcon(bus.id, label, isFocused: true);
      }

      if (oldPos == null) {
        // Brand-new bus: set initial position immediately
        _animatedPos[bus.id]     = newPos;
        _animatedHeading[bus.id] = bus.heading;
        _updateTrail(bus.id, newPos);
        needsRebuild = true;
      } else {
        final moved = (oldPos.latitude  - newPos.latitude).abs()  > 1e-7 ||
                      (oldPos.longitude - newPos.longitude).abs() > 1e-7;
        final turned = (_animatedHeading[bus.id] ?? 0.0) != bus.heading;

        if (moved || turned) {
          _startMarkerAnimation(bus.id, oldPos, newPos,
              _animatedHeading[bus.id] ?? bus.heading, bus.heading);
          _updateTrail(bus.id, newPos);
          needsRebuild = true;

          // Debounced camera follow (once per GPS update, not every anim frame)
          if (_isFollowing) _scheduleCameraMove(bus);
        }
      }
    }

    if (needsRebuild) _rebuildMapObjects();

    // Route changed
    if (old.selectedRoute?.id != widget.selectedRoute?.id) _rebuildMapObjects();
  }

  @override
  void dispose() {
    for (final c in _markerAnims.values) c.dispose();
    _flowTimer?.cancel();
    _cameraDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION
  // ═══════════════════════════════════════════════════════════════════════════

  void _startMarkerAnimation(
      String busId, LatLng start, LatLng end,
      double startBearing, double endBearing) {
    _markerAnims[busId]?.stop();
    _markerAnims[busId]?.dispose();

    final ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeInOut);

    ctrl.addListener(() {
      if (!mounted) return;
      final t = anim.value;

      // Interpolate position
      final lat = start.latitude  + (end.latitude  - start.latitude)  * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      _animatedPos[busId] = LatLng(lat, lng);

      // Interpolate heading (handles 0/360 wrap)
      double diff = endBearing - startBearing;
      if (diff >  180) diff -= 360;
      if (diff < -180) diff += 360;
      _animatedHeading[busId] = startBearing + diff * t;

      // Only rebuild map objects — not the whole widget tree
      _rebuildMapObjects();
    });

    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _animatedPos[busId]     = end;
        _animatedHeading[busId] = endBearing;
        _rebuildMapObjects();
      }
    });

    _markerAnims[busId] = ctrl;
    ctrl.forward();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP OBJECT BUILDERS — called only when data actually changes
  // ═══════════════════════════════════════════════════════════════════════════

  void _rebuildMapObjects() {
    if (!mounted) return;

    final newMarkers   = _buildMarkers();
    final newPolylines = _buildPolylines();
    final newCircles   = _buildCircles();

    // Single setState for all three sets together
    setState(() {
      _markers   = newMarkers;
      _polylines = newPolylines;
      _circles   = newCircles;
    });
  }

  // Update only the animated dashed flow polyline — called at 8fps
  void _updateFlowPolyline() {
    if (!mounted || widget.selectedRoute == null) return;
    if (widget.selectedRoute!.coordinates.isEmpty) return;

    final pts = widget.selectedRoute!.coordinates
        .map((c) => LatLng(c['latitude']!, c['longitude']!))
        .toList();

    final flow = Polyline(
      polylineId: const PolylineId('route_flow'),
      points:     pts,
      width:      5,
      color:      Colors.white.withOpacity(0.35),
      patterns:   [PatternItem.dash(10), PatternItem.gap(10 + _flowOffset)],
    );

    setState(() {
      _polylines = {
        ..._polylines.where((p) => p.polylineId.value != 'route_flow'),
        flow,
      };
    });
  }

  Set<Marker> _buildMarkers() {
    final result = <String, Marker>{};

    for (final bus in widget.buses) {
      final isFocused = _focusedBus?.id == bus.id;
      final pos       = _animatedPos[bus.id]     ?? LatLng(bus.currentLat, bus.currentLng);
      final heading   = _animatedHeading[bus.id] ?? bus.heading;

      final icon = isFocused
          ? (_focusedBusIcons[bus.id] ?? _busIcons[bus.id] ?? BitmapDescriptor.defaultMarker)
          : (_busIcons[bus.id]         ?? BitmapDescriptor.defaultMarker);

      result[bus.id] = Marker(
        markerId: MarkerId(bus.id),
        position: pos,
        rotation: _isDriveMode ? 0 : heading,
        anchor:   const Offset(0.5, 0.5),
        flat:     true,
        consumeTapEvents: false,
        infoWindow: InfoWindow(
          title:   'Shuttle ${_busLabel(bus.id)}',
          snippet: '${bus.speed.toInt()} km/h  •  ${bus.occupancy}',
        ),
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _focusedBus  = bus;
            _isDriveMode = true;
            _isFollowing = true;
          });
          _scheduleCameraMove(bus);
          _rebuildMapObjects();
        },
        icon:   icon,
        zIndex: isFocused ? 2.0 : 1.0,
      );
    }

    // Stop markers
    if (widget.selectedRoute != null) {
      final stops    = widget.selectedRoute!.stops;
      final hasCoords = stops.any((s) =>
          s['lat'] != null && s['lng'] != null &&
          (s['lat'] as num) != 0 && (s['lng'] as num) != 0);

      if (hasCoords) {
        for (var i = 0; i < stops.length; i++) {
          final stop = stops[i];
          if (stop['lat'] == null || stop['lng'] == null) continue;
          final lat = (stop['lat'] as num).toDouble();
          final lng = (stop['lng'] as num).toDouble();
          if (lat == 0 && lng == 0) continue;

          final stopId = 'stop_${stop['name']}';
          final isLast = i == stops.length - 1;

          result[stopId] = Marker(
            markerId: MarkerId(stopId),
            position: LatLng(lat, lng),
            anchor:   const Offset(0.5, 0.5),
            icon: isLast
                ? (_lastStopIcon ?? BitmapDescriptor.defaultMarker)
                : (_stopIcon     ?? BitmapDescriptor.defaultMarker),
            alpha: 0.9,
            infoWindow: InfoWindow(title: stop['name'], snippet: 'Bus Stop'),
          );
        }
      }
    }

    return Set<Marker>.of(result.values);
  }

  Set<Polyline> _buildPolylines() {
    final result = <String, Polyline>{};

    if (widget.selectedRoute != null) {
      final pts = widget.selectedRoute!.coordinates
          .map((c) => LatLng(c['latitude']!, c['longitude']!))
          .toList();

      final routeColor = Color(
          int.parse(widget.selectedRoute!.color.replaceAll('#', '0xFF')));

      // Glow
      result['route_glow'] = Polyline(
        polylineId: const PolylineId('route_glow'),
        points:     pts,
        width:      10,
        color:      routeColor.withOpacity(0.15),
      );

      // Solid line
      result['route'] = Polyline(
        polylineId: const PolylineId('route'),
        points:     pts,
        width:      5,
        color:      routeColor,
        jointType:  JointType.round,
        endCap:     Cap.roundCap,
        startCap:   Cap.roundCap,
      );
    }

    // Trails
    for (final entry in _busTrails.entries) {
      if (entry.value.length >= 2) {
        result['trail_${entry.key}'] = Polyline(
          polylineId: PolylineId('trail_${entry.key}'),
          points:     entry.value,
          width:      4,
          color:      Colors.blueAccent.withOpacity(0.35),
          patterns:   [PatternItem.dash(20), PatternItem.gap(10)],
          endCap:     Cap.roundCap,
          startCap:   Cap.roundCap,
        );
      }
    }

    return Set<Polyline>.of(result.values);
  }

  Set<Circle> _buildCircles() {
    final result = <Circle>{};
    if (_focusedBus != null) {
      final pos = _animatedPos[_focusedBus!.id]
          ?? LatLng(_focusedBus!.currentLat, _focusedBus!.currentLng);
      result.add(Circle(
        circleId:    CircleId('pulse_${_focusedBus!.id}'),
        center:      pos,
        radius:      20,
        fillColor:   const Color(0xFF1A4CFF).withOpacity(0.08),
        strokeColor: const Color(0xFF1A4CFF).withOpacity(0.25),
        strokeWidth: 2,
      ));
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CAMERA — debounced to avoid firing on every animation frame
  // ═══════════════════════════════════════════════════════════════════════════

  void _scheduleCameraMove(Bus bus) {
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || !_mapReady) return;
      final pos     = _animatedPos[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
      final heading = _animatedHeading[bus.id] ?? bus.heading;
      _moveCameraTo(pos, heading);
    });
  }

  void _moveCameraTo(LatLng pos, double heading) {
    if (_isDriveMode) {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  pos,
          zoom:    18.0,
          tilt:    52.0,
          bearing: heading,
        ),
      ));
    } else {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: 16.5, tilt: 0, bearing: 0),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRAIL
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateTrail(String busId, LatLng pos) {
    final trail = _busTrails[busId] ?? [];
    if (trail.isEmpty ||
        Geolocator.distanceBetween(
            trail.first.latitude, trail.first.longitude,
            pos.latitude, pos.longitude) > _trailMinDistM) {
      trail.insert(0, pos);
      if (trail.length > _maxTrail) trail.removeLast();
      _busTrails[busId] = trail;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ICONS
  // ═══════════════════════════════════════════════════════════════════════════

  String _busLabel(String busId) =>
      busId.substring(busId.length.clamp(4, busId.length) - 4).toUpperCase();

  Future<void> _precacheIcons() async {
    for (final bus in widget.buses) {
      final label = _busLabel(bus.id);
      await _ensureBusIcon(bus.id, label, isFocused: false);
      await _ensureBusIcon(bus.id, label, isFocused: true);
    }
    _stopIcon     = await _drawStopMarker(false);
    _lastStopIcon = await _drawStopMarker(true);
  }

  Future<void> _ensureBusIcon(String busId, String label, {required bool isFocused}) async {
    final map = isFocused ? _focusedBusIcons : _busIcons;
    if (map.containsKey(busId)) return;
    final icon = await _drawBusMarker(label, isFocused: isFocused);
    if (mounted) map[busId] = icon;
  }

  Future<BitmapDescriptor> _drawBusMarker(String label, {bool isFocused = false}) async {
    const double w = 60.0;
    const double h = 60.0;
    final Color fill   = isFocused ? Colors.white : const Color(0xFF1A6BFF);
    final Color border = isFocused ? const Color(0xFF1A6BFF) : Colors.white;
    final Color shadow = isFocused ? Colors.white : const Color(0xFF1A6BFF);

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));

    // Drop shadow
    canvas.drawCircle(
      const Offset(w / 2, w / 2 + 4), w / 2 - 4,
      Paint()
        ..color = shadow.withOpacity(0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Main body
    canvas.drawCircle(const Offset(w / 2, w / 2), w / 2 - 4, Paint()..color = fill);

    // Border ring
    canvas.drawCircle(
      const Offset(w / 2, w / 2), w / 2 - 4,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // Navigation chevron
    final double cx = w / 2, cy = w / 2;
    final Paint arrowPaint = Paint()
      ..color = isFocused ? const Color(0xFF1A6BFF) : Colors.white
      ..style = PaintingStyle.fill;

    final Path chevron = Path()
      ..moveTo(cx, cy - 14)
      ..lineTo(cx - 10, cy + 10)
      ..lineTo(cx, cy + 4)
      ..lineTo(cx + 10, cy + 10)
      ..close();
    canvas.drawPath(chevron, arrowPaint);

    final ui.Image img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bd!.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _drawStopMarker(bool isLast) async {
    const double size = 40.0;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec, const Rect.fromLTWH(0, 0, size, size));

    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 4,
        Paint()..color = isLast ? Colors.redAccent : Colors.white);
    canvas.drawCircle(
      const Offset(size / 2, size / 2), size / 2 - 4,
      Paint()
        ..color = isLast ? Colors.white : const Color(0xFF1A4CFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (isLast) {
      canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 12,
          Paint()..color = Colors.white);
    }

    final ui.Image img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bd!.buffer.asUint8List());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP STYLE
  // ═══════════════════════════════════════════════════════════════════════════

  void _buildDarkMapStyle() {
    _darkMapStyle = '''
    [
      {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
      {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"elementType":"labels.text.fill","stylers":[{"color":"#8b8b9e"}]},
      {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1a2e"}]},
      {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#3d3d5c"}]},
      {"featureType":"poi","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2a2a4a"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1a1a2e"}]},
      {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3a3a6a"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1a1a2e"}]},
      {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8b8b9e"}]},
      {"featureType":"transit","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d0d1a"}]},
      {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d5c"}]}
    ]
    ''';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleFollow() {
    setState(() {
      _isFollowing = !_isFollowing;
      if (!_isFollowing) _isDriveMode = false;
    });
    if (_isFollowing && widget.buses.isNotEmpty) {
      final bus = _focusedBus ?? widget.buses.first;
      _scheduleCameraMove(bus);
    }
  }

  void _toggleDriveMode() {
    setState(() => _isDriveMode = !_isDriveMode);

    if (_isDriveMode) {
      _isFollowing = true;
      _focusedBus ??= widget.buses.isNotEmpty ? widget.buses.first : null;
      if (_focusedBus != null) _scheduleCameraMove(_focusedBus!);
    } else {
      final bus = _focusedBus ?? (widget.buses.isNotEmpty ? widget.buses.first : null);
      if (bus != null) {
        final pos = _animatedPos[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
        _mapController?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: pos, zoom: 16, tilt: 0, bearing: 0),
        ));
      }
    }
    widget.onDriveModeChanged?.call(_isDriveMode);
    _rebuildMapObjects();
  }

  Future<void> _getCurrentLocation() async {
    try {
      if (!await Permission.location.isGranted) {
        await _requestPermissions();
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition();
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _center = latlng);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latlng, 15));
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else if (status.isPermanentlyDenied && mounted) {
      _showPermissionDialog(true);
    } else if (mounted) {
      _showPermissionDialog(false);
    }
  }

  void _showPermissionDialog(bool isPermanent) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F1528),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white10)),
        title: Text('Location Consent',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          isPermanent
              ? 'Location tracking is disabled. Please enable it in Settings.'
              : 'We need your location to show your position on the map.',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Maybe Later',
                style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A4CFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              if (isPermanent) {
                await openAppSettings();
              } else {
                await _requestPermissions();
              }
            },
            child: Text(isPermanent ? 'Open Settings' : 'Allow Access'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // NOTE: NO calls to _updateMarkers / _updatePolylines / _updateCircles here.
    // Map objects are rebuilt only when data actually changes (in didUpdateWidget
    // or when the user taps a marker). This prevents the infinite rebuild loop.

    return Stack(
      children: [
        // ── Google Map ──────────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: widget.buses.isNotEmpty
                ? LatLng(widget.buses.first.currentLat,
                         widget.buses.first.currentLng)
                : _bhopal,
            zoom: _isDriveMode ? 18 : 15,
            tilt:    _isDriveMode ? 52 : 0,
            bearing: _isDriveMode
                ? (_animatedHeading[widget.buses.isNotEmpty ? widget.buses.first.id : ''] ?? 0)
                : 0,
          ),
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            _mapReady = true;
            if (_currentMapType == MapType.none) {
              ctrl.setMapStyle(_darkMapStyle);
            }
            if (widget.buses.isNotEmpty) {
              final b = widget.buses.first;
              ctrl.animateCamera(CameraUpdate.newLatLngZoom(
                  LatLng(b.currentLat, b.currentLng),
                  _isDriveMode ? 18 : 15));
            }
          },
          mapType:               _currentMapType == MapType.none ? MapType.normal : _currentMapType,
          markers:               _markers,
          polylines:             _polylines,
          circles:               _circles,
          myLocationEnabled:     widget.showMyLocation,
          myLocationButtonEnabled: false,
          zoomControlsEnabled:   false,
          mapToolbarEnabled:     false,
          compassEnabled:        _isDriveMode,
          tiltGesturesEnabled:   true,
          rotateGesturesEnabled: true,
          buildingsEnabled:      _isDriveMode,   // 3D buildings only in drive mode
          trafficEnabled:        true,
          onTap: (_) => setState(() => _focusedBus = null),
        ),

        // ── Map Controls ────────────────────────────────────────────────────
        if (widget.showMapControls)
          Positioned(
            right: 12,
            top:   MediaQuery.of(context).padding.top + 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // —— Layers picker ———————————————————
                _buildMapBtn(
                  icon:  Icons.layers_rounded,
                  label: 'LAYERS',
                  color: Colors.white70,
                  isActive: _showLayerSelector,
                  onTap: () => setState(() => _showLayerSelector = !_showLayerSelector),
                ),
                if (_showLayerSelector) ...[
                  const SizedBox(height: 8),
                  _buildLayerItem(MapType.normal,    Icons.map_rounded,          'STREET'),
                  const SizedBox(height: 6),
                  _buildLayerItem(MapType.satellite, Icons.satellite_alt_rounded, 'SATELLITE'),
                  const SizedBox(height: 6),
                  _buildLayerItem(MapType.hybrid,    Icons.layers_outlined,       'HYBRID'),
                  const SizedBox(height: 6),
                  _buildLayerItem(MapType.terrain,   Icons.terrain_rounded,       'TERRAIN'),
                  const SizedBox(height: 6),
                  _buildLayerItem(MapType.none,      Icons.nightlight_round,      'DARK'),
                ],
                const SizedBox(height: 10),

                // —— Follow bus ————————————————————
                _buildMapBtn(
                  icon:    _isFollowing ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                  label:   _isFollowing ? 'FOLLOWING' : 'FOLLOW BUS',
                  color:   Colors.blueAccent,
                  isActive: _isFollowing,
                  onTap:   _toggleFollow,
                ),
                const SizedBox(height: 10),

                // —— Drive / Navigation mode ————————————
                _buildMapBtn(
                  icon:    Icons.directions_car_filled_rounded,
                  label:   _isDriveMode ? 'EXIT NAV' : 'DRIVE MODE',
                  color:   const Color(0xFF00C853),
                  isActive: _isDriveMode,
                  onTap:   _toggleDriveMode,
                ),

                // —— My location ———————————————————
                if (widget.showLocationButton) ...[
                  const SizedBox(height: 10),
                  _buildMapBtn(
                    icon:  Icons.person_pin_circle_rounded,
                    label: 'MY LOCATION',
                    color: Colors.deepPurpleAccent,
                    onTap: _getCurrentLocation,
                  ),
                ],
              ],
            ),
          ),

        // ── Drive Mode HUD ──────────────────────────────────────────────────
        if (_isDriveMode && _focusedBus != null)
          Positioned(
            top:   MediaQuery.of(context).padding.top + 10,
            left:  16,
            right: 80,
            child: GestureDetector(
              onTap: _toggleDriveMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF00C853).withOpacity(0.4),
                        blurRadius: 16)
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'DRIVE MODE  •  ${(_animatedHeading[_focusedBus!.id] ?? 0).toInt()}°  •  Tap to exit',
                      style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Focused Bus Card ────────────────────────────────────────────────
        if (_focusedBus != null)
          Positioned(
            left:   16,
            right:  16,
            bottom: 32,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0B14).withOpacity(0.82),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF1A4CFF),
                                  const Color(0xFF1A4CFF).withOpacity(0.6)
                                ],
                                begin: Alignment.topLeft,
                                end:   Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF1A4CFF).withOpacity(0.3),
                                    blurRadius: 12,
                                    spreadRadius: 2)
                              ],
                            ),
                            child: const Icon(Icons.directions_bus_filled_rounded,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SHUTTLE ${_busLabel(_focusedBus!.id)}',
                                  style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5),
                                ),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Container(
                                    width: 8, height: 8,
                                    decoration: const BoxDecoration(
                                        color: Colors.greenAccent,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _focusedBus!.routeName.toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white60,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.0),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() => _focusedBus = null);
                              _rebuildMapObjects();
                            },
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildPremiumStat(Icons.speed_rounded,
                              '${_focusedBus!.speed.toInt()}', 'KM/H'),
                          _buildPremiumStat(Icons.people_alt_rounded,
                              _focusedBus!.occupancy, 'LOAD'),
                          _buildPremiumStat(
                              Icons.timer_outlined,
                              _focusedBus!.etas.isNotEmpty
                                  ? '${_focusedBus!.etas.first.minutes}'
                                  : '--',
                              'MIN ETA'),
                          _buildPremiumStat(
                              Icons.social_distance_rounded,
                              _calculateDistance(
                                  LatLng(_focusedBus!.currentLat,
                                         _focusedBus!.currentLng),
                                  _center),
                              'DIST'),
                        ],
                      ),
                      if (_focusedBus!.etas.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _focusedBus!.etas.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 20),
                            itemBuilder: (context, index) {
                              final eta = _focusedBus!.etas[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    eta.stopName.toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white30,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${eta.minutes} MIN',
                                    style: GoogleFonts.plusJakartaSans(
                                        color: const Color(0xFF1A4CFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ).animate().slideY(begin: 1, end: 0, duration: 500.ms, curve: Curves.easeOutQuart).fadeIn(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  String _calculateDistance(LatLng p1, LatLng p2) {
    final d = Geolocator.distanceBetween(
        p1.latitude, p1.longitude, p2.latitude, p2.longitude);
    return d < 1000 ? '${d.toInt()}M' : '${(d / 1000).toStringAsFixed(1)}KM';
  }

  Widget _buildLayerItem(MapType type, IconData icon, String label) {
    final isSelected = _currentMapType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMapType = type;
          _showLayerSelector = false;
        });
        if (type == MapType.none) {
          _mapController?.setMapStyle(_darkMapStyle);
        } else {
          _mapController?.setMapStyle(null);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1A4CFF)
              : Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.3)
                : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    ).animate().slideX(begin: 0.4, end: 0, duration: 180.ms);
  }

  // Icon-only map button — distinct icon + color per action
  Widget _buildMapBtn({
    required IconData     icon,
    required String       label,   // used as tooltip only
    required Color        color,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: isActive
                    ? color.withOpacity(0.90)
                    : Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? color.withOpacity(0.55)
                      : Colors.white.withOpacity(0.10),
                  width: 1.2,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: color.withOpacity(0.45), blurRadius: 16, spreadRadius: 1)]
                    : [],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapControl({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    final Color activeBg = (activeColor ?? const Color(0xFF1A4CFF)).withOpacity(0.85);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isActive ? activeBg : Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isActive
                    ? (activeColor ?? const Color(0xFF1A4CFF)).withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
              boxShadow: isActive
                  ? [BoxShadow(
                      color: (activeColor ?? const Color(0xFF1A4CFF)).withOpacity(0.4),
                      blurRadius: 12)]
                  : [],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumStat(IconData icon, String value, String unit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A4CFF).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF1A4CFF), size: 18),
        ),
        const SizedBox(height: 8),
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
        Text(unit,
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white38,
                fontSize: 7,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      ],
    );
  }
}
