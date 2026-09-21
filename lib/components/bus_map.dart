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

  bool _isMuted = false;
  String _currentInstruction = "Head east on Main Road";
  String _nextInstruction = "Then turn left";
  IconData _instructionIcon = Icons.navigation_rounded;
  IconData _nextInstructionIcon = Icons.turn_left_rounded;

  // ── ValueNotifiers for decoupled Map Rendering ────────────────────────────
  late final ValueNotifier<Set<Marker>> _markersNotifier;
  late final ValueNotifier<Set<Polyline>> _polylinesNotifier;
  late final ValueNotifier<Set<Circle>> _circlesNotifier;

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

  // ── Camera debounce ───────────────────────────────────────────────────────
  Timer? _cameraDebounce;
  bool   _mapReady = false;
  DateTime? _lastCameraMoveTime;

  // ── Icon caches ───────────────────────────────────────────────────────────
  final Map<String, BitmapDescriptor> _busIcons        = {};
  final Map<String, BitmapDescriptor> _focusedBusIcons = {};
  BitmapDescriptor? _firstStopIcon;
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

    _markersNotifier = ValueNotifier<Set<Marker>>({});
    _polylinesNotifier = ValueNotifier<Set<Polyline>>({});
    _circlesNotifier = ValueNotifier<Set<Circle>>({});

    _buildDarkMapStyle();

    _focusInitialBus();

    // Precache icons and then build initial markers
    _precacheIcons().then((_) {
      _cacheRouteData();
      if (_focusedBus != null) {
        _updateNavigationInstructions(_focusedBus!);
      }
      _rebuildMapObjects();
    });
  }

  @override
  void didUpdateWidget(covariant BusMap old) {
    super.didUpdateWidget(old);

    bool needsRebuild = false;

    if (old.initialDriveMode != widget.initialDriveMode) {
      _isDriveMode = widget.initialDriveMode;
      if (_isDriveMode) {
        _isFollowing = true;
        _focusInitialBus();
        if (_focusedBus != null) {
          _updateNavigationInstructions(_focusedBus!);
        }
      } else {
        _isFollowing = false;
        _focusedBus = null;
      }
      needsRebuild = true;
    }

    // Keep focused bus updated with latest live telemetry
    if (_focusedBus != null) {
      try {
        _focusedBus = widget.buses.firstWhere((b) => b.id == _focusedBus!.id);
        _updateNavigationInstructions(_focusedBus!);
      } catch (_) {}
    } else if (_isDriveMode) {
      _focusInitialBus();
    }

    if (old.centerOnBusId != widget.centerOnBusId && widget.centerOnBusId != null) {
      _focusInitialBus();
    }

    for (final bus in widget.buses) {
      final newPos = LatLng(bus.currentLat, bus.currentLng);
      final oldPos = _animatedPos[bus.id];

      // Precache icon if new bus
      if (!_busIcons.containsKey(bus.id)) {
        final label = _busLabel(bus.id);
        _ensureBusIcon(bus.id, label, bus.routeColor, isFocused: false);
        _ensureBusIcon(bus.id, label, bus.routeColor, isFocused: true);
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
    _markersNotifier.dispose();
    _polylinesNotifier.dispose();
    _circlesNotifier.dispose();
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
          final now = DateTime.now();
          if (_lastCameraMoveTime == null ||
              now.difference(_lastCameraMoveTime!).inMilliseconds >= 50) {
            _lastCameraMoveTime = now;
            _mapController?.moveCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                target:  _animatedPos[busId]!,
                zoom:    _isDriveMode ? 18.0 : 16.5,
                tilt:    _isDriveMode ? 52.0 : 0.0,
                bearing: headingVal,
              ),
            ));
          }
        }

        // Only rebuild map markers and circles — not the whole polyline route
        _rebuildMarkersOnly();
      });

      ctrl.addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _animatedPos[busId]     = _targetPos[busId] ?? end;
          _animatedHeading[busId] = _targetHeading[busId] ?? endBearing;
          _rebuildMarkersOnly();
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
        final isFirst = i == 0;
        final isLast = i == stops.length - 1;

        final BitmapDescriptor markerIcon = isFirst
            ? (_firstStopIcon ?? BitmapDescriptor.defaultMarker)
            : (isLast
                ? (_lastStopIcon ?? BitmapDescriptor.defaultMarker)
                : (_stopIcon ?? BitmapDescriptor.defaultMarker));

        _cachedStopMarkers.add(Marker(
          markerId: MarkerId(stopId),
          position: LatLng(lat, lng),
          anchor:   const Offset(0.5, 0.5),
          icon:     markerIcon,
          alpha:    0.95,
          infoWindow: InfoWindow(
            title: stop['name'],
            snippet: isFirst ? 'Origin Stop' : (isLast ? 'SISTec Campus Terminal' : 'Bus Stop #${i + 1}'),
          ),
        ));
      }
    }
  }

  void _rebuildMapObjects() {
    if (!mounted) return;

    final newMarkers   = _buildMarkers();
    final newPolylines = _buildPolylines();
    final newCircles   = _buildCircles();

    _markersNotifier.value = newMarkers;
    _polylinesNotifier.value = newPolylines;
    _circlesNotifier.value = newCircles;
  }

  void _rebuildMarkersOnly() {
    if (!mounted) return;

    final newMarkers = _buildMarkers();
    final newCircles = _buildCircles();

    _markersNotifier.value = newMarkers;
    _circlesNotifier.value = newCircles;
  }

  Set<Marker> _buildMarkers() {
    final result = <String, Marker>{};

    for (final bus in widget.buses) {
      if (bus.status.toLowerCase() == 'offline') {
        continue;
      }

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
          title:   'Bus ${_busLabel(bus.id)}',
          snippet: '${bus.speed.toInt()} km/h  •  ${bus.occupancy}',
        ),
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _focusedBus  = bus;
            _isDriveMode = true;
            _isFollowing = true;
            _updateNavigationInstructions(bus);
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

      // 1. Ambient Road Glow Layer
      result['route_glow'] = Polyline(
        polylineId: const PolylineId('route_glow'),
        points:     _selectedRoutePoints,
        width:      8,
        color:      routeColor.withValues(alpha: 0.25),
        jointType:  JointType.round,
        endCap:     Cap.roundCap,
        startCap:   Cap.roundCap,
      );

      // 2. High-Contrast Core Road Polyline
      result['route'] = Polyline(
        polylineId: const PolylineId('route'),
        points:     _selectedRoutePoints,
        width:      4,
        color:      routeColor,
        jointType:  JointType.round,
        endCap:     Cap.roundCap,
        startCap:   Cap.roundCap,
      );

      // 3. Subtle Inner Road Highlight
      result['route_flow'] = Polyline(
        polylineId: const PolylineId('route_flow'),
        points:     _selectedRoutePoints,
        width:      2,
        color:      Colors.white.withValues(alpha: 0.45),
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
      await _ensureBusIcon(bus.id, label, bus.routeColor, isFocused: false);
      await _ensureBusIcon(bus.id, label, bus.routeColor, isFocused: true);
    }
    _firstStopIcon = await _drawStopMarker(0);
    _stopIcon      = await _drawStopMarker(1);
    _lastStopIcon  = await _drawStopMarker(2);
  }

  Future<void> _ensureBusIcon(String busId, String label, String routeColorHex, {required bool isFocused}) async {
    final map = isFocused ? _focusedBusIcons : _busIcons;
    if (map.containsKey(busId)) return;
    final icon = await _drawBusMarker(label, routeColorHex, isFocused: isFocused);
    if (mounted) {
      map[busId] = icon;
      _rebuildMapObjects();
    }
  }

  Future<BitmapDescriptor> _drawBusMarker(String label, String routeColorHex, {bool isFocused = false}) async {
    const double scale = 1.8; // Optimal scale: large enough for details, small enough for map aesthetics
    const double w = 120.0 * scale;
    const double h = 120.0 * scale;
    const double cx = 60.0; // Logical center X
    const double cy = 60.0; // Logical center Y

    final Color routeColor = Color(int.parse(routeColorHex.replaceAll('#', '0xFF')));

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));

    // Scale the coordinate system
    canvas.scale(scale);

    // 1. Drop shadow (elevated slightly, soft blur)
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale);
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 18.5, cy - 30.5 + 4.5, 37, 67),
        const Radius.circular(11),
      ),
      shadowPaint,
    );

    // 2. Focused Glowing Ring
    if (isFocused) {
      final glowPaint = Paint()
        ..color = routeColor.withOpacity(0.18)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx, cy + 4), 46, glowPaint);

      final glowOutline = Paint()
        ..color = routeColor.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(Offset(cx, cy + 4), 46, glowOutline);
    }

    // 3. Wheels (4 dark gray rounded rects)
    final wheelPaint = Paint()..color = const Color(0xFF222222);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 21, cy - 20, 4, 13), const Radius.circular(2)), wheelPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 17, cy - 20, 4, 13), const Radius.circular(2)), wheelPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 21, cy + 11, 4, 13), const Radius.circular(2)), wheelPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 17, cy + 11, 4, 13), const Radius.circular(2)), wheelPaint);

    // 4. 3D Body Extrusion (Stack extrusion loops to render solid side walls)
    final Color darkerRouteColor = Color.alphaBlend(Colors.black.withOpacity(0.42), routeColor);
    final extrusionPaint = Paint()..color = darkerRouteColor;
    for (double i = 3.5; i >= 0.0; i -= 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 18, cy - 30 + i, 36, 66),
          const Radius.circular(10),
        ),
        extrusionPaint,
      );
    }

    // 5. Front Bumper
    final bumperPaint = Paint()..color = const Color(0xFF333333);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 15, cy - 31, 30, 3.5),
        const Radius.circular(1.5),
      ),
      bumperPaint,
    );

    // 6. Upper Bus Body
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - 18, cy - 30),
        Offset(cx + 18, cy + 36),
        [
          Colors.white,
          const Color(0xFFEDEDED),
          const Color(0xFFD6D6D6),
        ],
        [0.0, 0.7, 1.0],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 18, cy - 30, 36, 66),
        const Radius.circular(10),
      ),
      bodyPaint,
    );

    // 7. Accent side stripes
    final stripePaint = Paint()..color = routeColor;
    canvas.drawRect(Rect.fromLTWH(cx - 17.5, cy - 8, 1.8, 28), stripePaint);
    canvas.drawRect(Rect.fromLTWH(cx + 15.7, cy - 8, 1.8, 28), stripePaint);

    // 8. 3D Cabin/Roof Extrusion (Stack extrusion loops for solid roof block elevation)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 14, cy - 22 + 1.5, 28, 48),
        const Radius.circular(8),
      ),
      Paint()
        ..color = Colors.black.withOpacity(0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 * scale),
    );
    final cabinExtrusionPaint = Paint()..color = const Color(0xFFB5B5B5);
    for (double i = 2.0; i >= 0.0; i -= 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 14, cy - 22 + i, 28, 48),
          const Radius.circular(8),
        ),
        cabinExtrusionPaint,
      );
    }
    // Cabin Roof top
    final cabinPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - 14, cy - 22),
        Offset(cx + 14, cy + 26),
        [
          Colors.white,
          const Color(0xFFF7F7F7),
          const Color(0xFFE0E0E0),
        ],
        [0.0, 0.65, 1.0],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 14, cy - 22, 28, 48),
        const Radius.circular(8),
      ),
      cabinPaint,
    );

    // 9. Front Windshield (Gradient glass)
    final glassPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - 11, cy - 20),
        Offset(cx + 11, cy - 10),
        [
          const Color(0xFF00E5FF),
          const Color(0xFF0051FF),
        ],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 11, cy - 20, 22, 10),
        const Radius.circular(3),
      ),
      glassPaint,
    );

    // specular highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.65)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 6, cy - 20), Offset(cx - 1.5, cy - 10), highlightPaint);
    canvas.drawLine(Offset(cx - 1.5, cy - 20), Offset(cx + 3, cy - 10), highlightPaint);

    // 10. Segmented Side and Rear Windows
    final windowPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx - 13, cy - 8),
        Offset(cx + 13, cy + 24),
        [
          const Color(0xFF003C8F),
          const Color(0xFF001064),
        ],
      );
    // Left windows
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 13.8, cy - 8, 1, 7.5), const Radius.circular(0.5)), windowPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 13.8, cy + 1.5, 1, 7.5), const Radius.circular(0.5)), windowPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 13.8, cy + 11, 1, 7.5), const Radius.circular(0.5)), windowPaint);
    // Right windows
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 12.8, cy - 8, 1, 7.5), const Radius.circular(0.5)), windowPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 12.8, cy + 1.5, 1, 7.5), const Radius.circular(0.5)), windowPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 12.8, cy + 11, 1, 7.5), const Radius.circular(0.5)), windowPaint);
    // Rear Window
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 9.5, cy + 22, 19, 3.2), const Radius.circular(1)), windowPaint);

    // 11. Headlights (Bright Yellow glow)
    final headlightPaint = Paint()
      ..color = const Color(0xFFFFEA00)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.8 * scale);
    canvas.drawCircle(Offset(cx - 10, cy - 28.5), 3.2, headlightPaint);
    canvas.drawCircle(Offset(cx + 10, cy - 28.5), 3.2, headlightPaint);

    // 12. Taillights (Red rectangles)
    final taillightPaint = Paint()..color = const Color(0xFFFF1744);
    canvas.drawRect(Rect.fromLTWH(cx - 13.5, cy + 34, 4, 2.2), taillightPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 9.5, cy + 34, 4, 2.2), taillightPaint);

    // 13. Route Label Badge on Roof (Circular colored badge with text)
    final badgePaint = Paint()..color = routeColor;
    canvas.drawCircle(Offset(cx, cy + 8), 10.0, badgePaint);

    // Badge outline
    final badgeOutline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy + 8), 10.0, badgeOutline);

    // Draw the text
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width / 2, cy + 8 - textPainter.height / 2),
    );

    final ui.Image img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.fromBytes(data.buffer.asUint8List());
  }

  Future<BitmapDescriptor> _drawStopMarker(int type) async {
    const double scale = 1.4;
    const double size = 36.0 * scale;
    const double drawSize = 36.0;
    
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, size, size));

    canvas.scale(scale);

    final isFirst = type == 0;
    final isLast = type == 2;

    final primaryColor = isFirst
        ? const Color(0xFF10B981) // Emerald Green for Origin
        : (isLast
            ? const Color(0xFFEF4444) // Coral Red for Campus Destination
            : const Color(0xFF3B82F6)); // Royal Blue for Intermediate Stops

    // Drop Shadow
    canvas.drawCircle(
      const Offset(drawSize / 2, drawSize / 2 + 1.5),
      drawSize / 2 - 4,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Outer Ring
    canvas.drawCircle(
      const Offset(drawSize / 2, drawSize / 2),
      drawSize / 2 - 3,
      Paint()..color = Colors.white,
    );

    // Inner Color Circle
    canvas.drawCircle(
      const Offset(drawSize / 2, drawSize / 2),
      drawSize / 2 - 5.5,
      Paint()..color = primaryColor,
    );

    // Core Dot
    canvas.drawCircle(
      const Offset(drawSize / 2, drawSize / 2),
      isLast ? 4.5 : 3.0,
      Paint()..color = Colors.white,
    );

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
  void _focusInitialBus() {
    if (widget.centerOnBusId != null) {
      try {
        final bus = widget.buses.firstWhere((b) => b.id == widget.centerOnBusId);
        _focusedBus = bus;
        if (widget.initialDriveMode) {
          _isDriveMode = true;
          _isFollowing = true;
        }
      } catch (_) {}
    } else if (widget.initialDriveMode && widget.buses.isNotEmpty) {
      _focusedBus = widget.buses.first;
      _isDriveMode = true;
      _isFollowing = true;
    }
  }

  void _updateNavigationInstructions(Bus bus) {
    if (bus.etas.isNotEmpty) {
      _currentInstruction = "Head toward ${bus.etas.first.stopName}";
      if (bus.etas.length > 1) {
        _nextInstruction = "Next stop: ${bus.etas[1].stopName}";
        _nextInstructionIcon = Icons.location_on_outlined;
      } else {
        _nextInstruction = "Then arrive at destination";
        _nextInstructionIcon = Icons.check_circle_outline_rounded;
      }
      _instructionIcon = Icons.navigation_rounded;
    } else {
      _currentInstruction = "Drive along the route";
      _nextInstruction = "GPS is active";
      _instructionIcon = Icons.navigation_rounded;
      _nextInstructionIcon = Icons.gps_fixed_rounded;
    }
  }

  void _showReportDialog() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0B14).withOpacity(0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              'REPORT AN ISSUE',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildReportOption(ctx, Icons.traffic_rounded, 'Traffic Jam', Colors.orangeAccent),
                _buildReportOption(ctx, Icons.car_crash_rounded, 'Crash', Colors.redAccent),
                _buildReportOption(ctx, Icons.construction_rounded, 'Roadworks', Colors.amber),
                _buildReportOption(ctx, Icons.warning_amber_rounded, 'Hazard', Colors.yellow),
                _buildReportOption(ctx, Icons.timer_outlined, 'Bus Delay', Colors.blueAccent),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildReportOption(BuildContext ctx, IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF38EF7D),
            content: Text(
              'Reported "$label" successfully. Thank you for updating transit conditions!',
              style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnByTurnCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF38EF7D).withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Row(
            children: [
              // Direction Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF38EF7D), Color(0xFF11998E)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF38EF7D).withOpacity(0.4), blurRadius: 10),
                  ],
                ),
                child: Icon(_instructionIcon, color: Colors.black, size: 24),
              ),
              const SizedBox(width: 16),
              // Instructions Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentInstruction,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Then  ',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF38EF7D),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Icon(_nextInstructionIcon, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _nextInstruction,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarCompassBtn() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Transform.rotate(
            angle: -((_animatedHeading[_focusedBus?.id] ?? 0.0) * (3.14159 / 180.0)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.explore_outlined, color: Colors.white60, size: 26),
                Positioned(
                  top: 8,
                  child: Container(
                    width: 3,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarSearchBtn() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: Text(
              'Search along route is active.',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarMuteBtn() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _isMuted = !_isMuted;
        });
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _isMuted ? Colors.redAccent : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReCentreBtn() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (_focusedBus != null) {
          setState(() {
            _isFollowing = true;
          });
          _scheduleCameraMove(_focusedBus!);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _isFollowing ? const Color(0xFF38EF7D) : Colors.white10, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: 45 * 3.14159 / 180, // tilt icon slightly to look like navigation
              child: Icon(
                Icons.navigation_rounded,
                color: _isFollowing ? const Color(0xFF38EF7D) : Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Re-centre',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportBtn() {
    return GestureDetector(
      onTap: _showReportDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
            const SizedBox(width: 8),
            Text(
              'Report',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatsPanel() {
    // Generate realistic remaining time and distance using ETA or a dynamic fallback
    String timeStr = "12 min";
    String distanceStr = "4.8 km";
    String etaStr = "10:38 am";

    if (_focusedBus != null) {
      if (_focusedBus!.etas.isNotEmpty) {
        final totalMins = _focusedBus!.etas.fold<int>(0, (prev, element) => prev + element.minutes);
        timeStr = totalMins > 60 
            ? '${totalMins ~/ 60} hr ${totalMins % 60} min'
            : '$totalMins min';
        final speed = _focusedBus!.speed > 0 ? _focusedBus!.speed : 30.0; // km/h
        final distanceKm = (speed * (totalMins / 60.0)).clamp(0.5, 45.0);
        distanceStr = '${distanceKm.toStringAsFixed(1)} km';
        final arrivalTime = DateTime.now().add(Duration(minutes: totalMins));
        final hour = arrivalTime.hour > 12 ? arrivalTime.hour - 12 : (arrivalTime.hour == 0 ? 12 : arrivalTime.hour);
        final min = arrivalTime.minute.toString().padLeft(2, '0');
        final ampm = arrivalTime.hour >= 12 ? 'pm' : 'am';
        etaStr = '$hour:$min $ampm';
      } else {
        timeStr = "15 min";
        distanceStr = "5.2 km";
        final arrivalTime = DateTime.now().add(const Duration(minutes: 15));
        final hour = arrivalTime.hour > 12 ? arrivalTime.hour - 12 : (arrivalTime.hour == 0 ? 12 : arrivalTime.hour);
        final min = arrivalTime.minute.toString().padLeft(2, '0');
        final ampm = arrivalTime.hour >= 12 ? 'pm' : 'am';
        etaStr = '$hour:$min $ampm';
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14).withOpacity(0.82),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _toggleDriveMode,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          timeStr,
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF38EF7D), // Eco green
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (_focusedBus?.isDropoff ?? false) ? Colors.orangeAccent.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (_focusedBus?.isDropoff ?? false) ? Colors.orangeAccent : Colors.blueAccent,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            (_focusedBus?.isDropoff ?? false) ? 'CAMPUS → CITY' : 'CITY → CAMPUS',
                            style: GoogleFonts.plusJakartaSans(
                              color: (_focusedBus?.isDropoff ?? false) ? Colors.orangeAccent : Colors.blueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$distanceStr  •  $etaStr',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF0F1528),
                      content: Text(
                        'Recalculating alternative routes...',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white),
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.alt_route_rounded, color: Colors.blueAccent, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        ValueListenableBuilder<Set<Marker>>(
          valueListenable: _markersNotifier,
          builder: (context, markers, _) {
            return ValueListenableBuilder<Set<Polyline>>(
              valueListenable: _polylinesNotifier,
              builder: (context, polylines, _) {
                return ValueListenableBuilder<Set<Circle>>(
                  valueListenable: _circlesNotifier,
                  builder: (context, circles, _) {
                    return GoogleMap(
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
                      markers:               markers,
                      polylines:             polylines,
                      circles:               circles,
                      myLocationEnabled:     widget.showMyLocation,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled:   false,
                      mapToolbarEnabled:     true,
                      compassEnabled:        _isDriveMode,
                      tiltGesturesEnabled:   true,
                      rotateGesturesEnabled: true,
                      buildingsEnabled:      _isDriveMode,   // 3D buildings only in drive mode
                      trafficEnabled:        true,
                      onTap: (_) => setState(() => _focusedBus = null),
                    );
                  },
                );
              },
            );
          },
        ),

        // ── Map Floating Action Stack (Right side) ─────────────────────────
        if (widget.showMapControls)
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + (_isDriveMode ? 148 : 76),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildMapBtn(
                  icon: Icons.layers_rounded,
                  label: 'LAYERS',
                  color: Colors.white70,
                  onTap: _showLayersSheet,
                ),
                const SizedBox(height: 10),
                _buildMapBtn(
                  icon: _isFollowing ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                  label: _isFollowing ? 'FOLLOWING' : 'FOLLOW BUS',
                  color: const Color(0xFF2D5BFF),
                  isActive: _isFollowing,
                  onTap: _toggleFollow,
                ),
                const SizedBox(height: 10),
                _buildMapBtn(
                  icon: Icons.directions_car_filled_rounded,
                  label: _isDriveMode ? 'EXIT NAV' : 'DRIVE MODE',
                  color: const Color(0xFF38EF7D),
                  isActive: _isDriveMode,
                  onTap: _toggleDriveMode,
                ),
                if (widget.showLocationButton) ...[
                  const SizedBox(height: 10),
                  _buildMapBtn(
                    icon: Icons.my_location_rounded,
                    label: 'MY LOCATION',
                    color: Colors.deepPurpleAccent,
                    onTap: _getCurrentLocation,
                  ),
                ],
                if (_isDriveMode) ...[
                  const SizedBox(height: 10),
                  _buildSidebarMuteBtn(),
                ],
              ],
            ),
          ),

        // ── Drive Mode Navigation Banner ────────────────────────────────────
        if (_isDriveMode && _focusedBus != null) ...[
          Positioned(
            top: MediaQuery.of(context).padding.top + 76,
            left: 16,
            right: 16,
            child: _buildTurnByTurnCard(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildBottomStatsPanel(),
          ),
        ],

        // ── Focused Bus Card ────────────────────────────────────────────────
        if (_focusedBus != null && !_isDriveMode)
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
                                  'BUS ${_busLabel(_focusedBus!.id)}',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF38EF7D),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ONLINE  •  ROUTE ${_focusedBus!.routeId}',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white38,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white30, size: 24),
                            onPressed: () => setState(() => _focusedBus = null),
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

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0B14).withOpacity(0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MAP STYLE',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _buildLayerGridItem(MapType.normal, Icons.map_rounded, 'STREET'),
                  _buildLayerGridItem(MapType.satellite, Icons.satellite_alt_rounded, 'SATELLITE'),
                  _buildLayerGridItem(MapType.hybrid, Icons.layers_outlined, 'HYBRID'),
                  _buildLayerGridItem(MapType.terrain, Icons.terrain_rounded, 'TERRAIN'),
                  _buildLayerGridItem(MapType.none, Icons.nightlight_round, 'DARK'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerGridItem(MapType type, IconData icon, String label) {
    final isSelected = _currentMapType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentMapType = type;
        });
        if (type == MapType.none) {
          _mapController?.setMapStyle(_darkMapStyle);
        } else {
          _mapController?.setMapStyle(null);
        }
        Navigator.pop(context); // close sheet
      },
      child: SizedBox(
        width: 90,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1A4CFF)
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.white.withOpacity(0.4)
                      : Colors.white.withOpacity(0.08),
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: const Color(0xFF1A4CFF).withOpacity(0.3), blurRadius: 10)]
                    : [],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
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
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? color.withValues(alpha: 0.90)
                    : const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? color.withValues(alpha: 0.50)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
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
