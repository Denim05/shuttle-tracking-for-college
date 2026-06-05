import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  final Map<String, DateTime>            _lastUpdateTimes = {};
  final Map<String, LatLng>              _startPos        = {};
  final Map<String, LatLng>              _targetPos       = {};
  final Map<String, double>              _startHeading    = {};
  final Map<String, double>              _targetHeading   = {};

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

  final List<LatLng> _selectedRoutePoints = [];
  final List<Marker> _cachedStopMarkers = [];

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
    _precacheIcons().then((_) {
      _cacheRouteData();
      _rebuildMapObjects();
    });
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
        _lastUpdateTimes[bus.id] = DateTime.now();
        needsRebuild = true;
      } else {
        final moved = (oldPos.latitude  - newPos.latitude).abs()  > 1e-7 ||
                      (oldPos.longitude - newPos.longitude).abs() > 1e-7;
        final turned = (_animatedHeading[bus.id] ?? 0.0) != bus.heading;

        if (moved || turned) {
          // Calculate time since last update to dynamically adapt animation duration
          final now = DateTime.now();
          final lastUpdate = _lastUpdateTimes[bus.id];
          _lastUpdateTimes[bus.id] = now;

          Duration animDuration = const Duration(milliseconds: 900);
          if (lastUpdate != null) {
            final diff = now.difference(lastUpdate);
            // Cap duration between 400ms and 4000ms to handle anomalous delay packets
            if (diff.inMilliseconds > 400 && diff.inMilliseconds < 4000) {
              // Target 92% of packet frequency to ensure completion before next update
              animDuration = Duration(milliseconds: (diff.inMilliseconds * 0.92).round());
            }
          }

          // Suppress heading adjustments when the bus is stationary to avoid oscillation/jitter
          double targetBearing = bus.heading;
          if (bus.speed <= 2.0 && _animatedHeading[bus.id] != null) {
            targetBearing = _animatedHeading[bus.id]!;
          }

          _startMarkerAnimation(
            bus.id,
            oldPos,
            newPos,
            _animatedHeading[bus.id] ?? bus.heading,
            targetBearing,
            animDuration,
          );
          _updateTrail(bus.id, newPos);
          needsRebuild = true;
        }
      }
    }

    if (needsRebuild) _rebuildMapObjects();

    // Route changed
    if (old.selectedRoute?.id != widget.selectedRoute?.id) {
      _cacheRouteData();
      _rebuildMapObjects();
    }
  }

  @override
  void dispose() {
    for (final c in _markerAnims.values) {
      c.dispose();
    }
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
      double startBearing, double endBearing, Duration duration) {
    var ctrl = _markerAnims[busId];
    if (ctrl == null) {
      // Reuse the AnimationController instance per bus to optimize CPU and GC performance
      ctrl = AnimationController(vsync: this);
      _markerAnims[busId] = ctrl;

      ctrl.addListener(() {
        if (!mounted) return;
        final t = ctrl!.value;

        final sPos = _startPos[busId] ?? start;
        final tPos = _targetPos[busId] ?? end;
        final sHead = _startHeading[busId] ?? startBearing;
        final tHead = _targetHeading[busId] ?? endBearing;

        // Interpolate position linearly to preserve constant velocity in continuous streams
        final lat = sPos.latitude  + (tPos.latitude  - sPos.latitude)  * t;
        final lng = sPos.longitude + (tPos.longitude - sPos.longitude) * t;
        _animatedPos[busId] = LatLng(lat, lng);

        // Interpolate heading smoothly with shortest-path wrap correction
        double diff = tHead - sHead;
        if (diff >  180) diff -= 360;
        if (diff < -180) diff += 360;
        _animatedHeading[busId] = sHead + diff * t;

        // If we are following this bus, update the camera position in real-time
        if (_isFollowing && _focusedBus?.id == busId) {
          final headingVal = _isDriveMode ? _animatedHeading[busId]! : 0.0;
          _mapController?.moveCamera(CameraUpdate.newCameraPosition(
            CameraPosition(
              target:  _animatedPos[busId]!,
              zoom:    _isDriveMode ? 18.0 : 16.5,
              tilt:    _isDriveMode ? 52.0 : 0.0,
              bearing: headingVal,
            ),
          ));
        }

        // Only rebuild map objects — not the whole widget tree
        _rebuildMapObjects();
      });

      ctrl.addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _animatedPos[busId]     = _targetPos[busId] ?? end;
          _animatedHeading[busId] = _targetHeading[busId] ?? endBearing;
          _rebuildMapObjects();
        }
      });
    } else {
      ctrl.stop();
    }

    // Set new segment bounds
    _startPos[busId] = _animatedPos[busId] ?? start;
    _targetPos[busId] = end;
    _startHeading[busId] = _animatedHeading[busId] ?? startBearing;
    _targetHeading[busId] = endBearing;

    // Reset and trigger play with the adapted duration
    ctrl.duration = duration;
    ctrl.forward(from: 0.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP OBJECT BUILDERS — called only when data actually changes
  // ═══════════════════════════════════════════════════════════════════════════

  void _cacheRouteData() {
    _selectedRoutePoints.clear();
    if (widget.selectedRoute != null) {
      _selectedRoutePoints.addAll(widget.selectedRoute!.coordinates
          .map((c) => LatLng(c['latitude']!, c['longitude']!)));
    }
    _rebuildStopMarkers();
  }

  void _rebuildStopMarkers() {
    _cachedStopMarkers.clear();
    if (widget.selectedRoute == null) return;

    final stops = widget.selectedRoute!.stops;
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

        _cachedStopMarkers.add(Marker(
          markerId: MarkerId(stopId),
          position: LatLng(lat, lng),
          anchor:   const Offset(0.5, 0.5),
          icon: isLast
              ? (_lastStopIcon ?? BitmapDescriptor.defaultMarker)
              : (_stopIcon     ?? BitmapDescriptor.defaultMarker),
          alpha: 0.9,
          infoWindow: InfoWindow(title: stop['name'], snippet: 'Bus Stop'),
        ));
      }
    }
  }

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
    if (!mounted || widget.selectedRoute == null || _selectedRoutePoints.isEmpty) return;

    final flow = Polyline(
      polylineId: const PolylineId('route_flow'),
      points:     _selectedRoutePoints,
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

    final allMarkers = Set<Marker>.of(result.values);
    allMarkers.addAll(_cachedStopMarkers);
    return allMarkers;
  }

  Set<Polyline> _buildPolylines() {
    final result = <String, Polyline>{};

    if (widget.selectedRoute != null && _selectedRoutePoints.isNotEmpty) {
      final routeColor = Color(
          int.parse(widget.selectedRoute!.color.replaceAll('#', '0xFF')));

      // Glow
      result['route_glow'] = Polyline(
        polylineId: const PolylineId('route_glow'),
        points:     _selectedRoutePoints,
        width:      10,
        color:      routeColor.withOpacity(0.15),
      );

      // Solid line
      result['route'] = Polyline(
        polylineId: const PolylineId('route'),
        points:     _selectedRoutePoints,
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
    if (mounted) {
      map[busId] = icon;
      _rebuildMapObjects();
    }
  }

  Future<BitmapDescriptor> _drawBusMarker(String label, {bool isFocused = false}) async {
    const double w = 80.0;
    const double h = 80.0;
    final double cx = w / 2;
    final double cy = h / 2;

    final Color primaryColor = isFocused ? const Color(0xFF1A4CFF) : const Color(0xFF0D0B14);
    final Color accentColor  = isFocused ? Colors.white : const Color(0xFF38EF7D);
    final Color textColor    = Colors.white;

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));

    // 1. Soft Ambient glow shadow
    canvas.drawCircle(
      Offset(cx, cy), 22,
      Paint()
        ..color = primaryColor.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 2. Outer border ring (glowing ring)
    canvas.drawCircle(
      Offset(cx, cy), 20,
      Paint()
        ..color = accentColor.withOpacity(0.3)
        ..style = PaintingStyle.fill,
    );

    // 3. Inner circle (body)
    canvas.drawCircle(
      Offset(cx, cy), 17,
      Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill,
    );

    // 4. Solid border outline
    canvas.drawCircle(
      Offset(cx, cy), 17.5,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 5. Heading indicator chevron pointing UP (since the marker rotates)
    final Paint chevronPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    
    final Path chevron = Path()
      ..moveTo(cx, cy - 28)
      ..lineTo(cx - 7, cy - 19)
      ..lineTo(cx, cy - 22)
      ..lineTo(cx + 7, cy - 19)
      ..close();
    canvas.drawPath(chevron, chevronPaint);

    // 6. Bus Label text inside the circle
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: GoogleFonts.plusJakartaSans(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width / 2, cy - textPainter.height / 2),
    );

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
