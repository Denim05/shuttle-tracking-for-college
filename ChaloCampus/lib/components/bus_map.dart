import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../utils/map_math.dart';

class BusMap extends StatefulWidget {
  final List<Bus> buses;
  final RouteModel? selectedRoute;
  /// When set, the map will animate to this bus and open its detail card.
  final String? centerOnBusId;

  const BusMap({
    super.key,
    required this.buses,
    this.selectedRoute,
    this.centerOnBusId,
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
  bool _isDriveMode = false; // Google Maps Drive Mode
  MapType _currentMapType = MapType.normal;
  bool _showLayerSelector = false;
  
  final Map<String, Marker> _markers = {};
  final Map<String, Polyline> _polylines = {};
  final Map<String, List<LatLng>> _busTrails = {};
  final Map<String, AnimationController> _markerAnimations = {};
  final Map<String, LatLng> _animatedPositions = {};
  final Map<String, double> _animatedHeadings = {};
  
  final Map<String, BitmapDescriptor> _busIcons = {};
  final Map<String, BitmapDescriptor> _focusedBusIcons = {};
  
  static const int _maxTrailPoints = 20;
  static const LatLng _bhopal = LatLng(23.2599, 77.4126);

  String? _darkMapStyle;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _precacheAllBusIcons();
  }

  Future<void> _precacheAllBusIcons() async {
    for (final bus in widget.buses) {
      final label = bus.id.substring(bus.id.length.clamp(4, bus.id.length) - 4).toUpperCase();
      await _ensureBusIcon(bus.id, label, isFocused: false);
      await _ensureBusIcon(bus.id, label, isFocused: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureBusIcon(String busId, String label, {required bool isFocused}) async {
    final key = isFocused ? 'focused_$busId' : busId;
    if (_busIcons.containsKey(key)) return;
    final icon = await _drawBusMarker(label, isFocused: isFocused);
    if (mounted) setState(() => (isFocused ? _focusedBusIcons : _busIcons)[busId] = icon);
  }

  /// Draws a compact Google Maps Drive Mode navigation chevron:
  /// - A small sharp arrow/chevron pointing up (direction of travel)
  /// - Clean neon fill with white border
  /// - Subtle drop shadow below
  Future<BitmapDescriptor> _drawBusMarker(String label, {bool isFocused = false}) async {
    const double w   = 80.0;
    const double h   = 96.0;
    final Color fill   = isFocused ? Colors.white         : const Color(0xFF1A6BFF);
    final Color border = isFocused ? const Color(0xFF1A6BFF) : Colors.white;
    final Color shadow = isFocused ? Colors.white : const Color(0xFF1A6BFF);

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));

    // ── Drop shadow ────────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(w / 2, w / 2 + 4),
      w / 2 - 4,
      Paint()
        ..color = shadow.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ── Main circle body ──────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(w / 2, w / 2),
      w / 2 - 4,
      Paint()..color = fill,
    );

    // ── White ring border ─────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(w / 2, w / 2),
      w / 2 - 4,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    // ── Navigation chevron arrow (sharp upward arrow inside circle) ───────
    final double cx = w / 2;
    final double cy = w / 2;
    final Paint arrowPaint = Paint()
      ..color = isFocused ? const Color(0xFF1A6BFF) : Colors.white
      ..style = PaintingStyle.fill;

    // Draw chevron: two filled triangles forming a chevron shape
    final Path chevron = Path()
      ..moveTo(cx, cy - 22)              // tip (top)
      ..lineTo(cx - 16, cy + 14)         // bottom-left
      ..lineTo(cx, cy + 6)              // inner bottom-center
      ..lineTo(cx + 16, cy + 14)         // bottom-right
      ..close();
    canvas.drawPath(chevron, arrowPaint);

    // ── Sharp teardrop pin tail ────────────────────────────────────────────
    final Path tail = Path()
      ..moveTo(cx, h - 2)                // tip of pin
      ..lineTo(cx - 9, w - 2)           // left shoulder
      ..lineTo(cx + 9, w - 2)           // right shoulder
      ..close();
    canvas.drawPath(tail, Paint()..color = fill);
    canvas.drawPath(
      tail,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final ui.Image img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bd!.buffer.asUint8List());
  }


  Future<void> _loadMapStyle() async {
    // Custom dark mode style for Google Maps
    _darkMapStyle = '''
    [
      {
        "elementType": "geometry",
        "stylers": [{"color": "#212121"}]
      },
      {
        "elementType": "labels.icon",
        "stylers": [{"visibility": "off"}]
      },
      {
        "elementType": "labels.text.fill",
        "stylers": [{"color": "#757575"}]
      },
      {
        "elementType": "labels.text.stroke",
        "stylers": [{"color": "#212121"}]
      },
      {
        "featureType": "administrative",
        "elementType": "geometry",
        "stylers": [{"color": "#757575"}]
      },
      {
        "featureType": "poi",
        "elementType": "geometry",
        "stylers": [{"color": "#181818"}]
      },
      {
        "featureType": "road",
        "elementType": "geometry.fill",
        "stylers": [{"color": "#2c2c2c"}]
      },
      {
        "featureType": "water",
        "elementType": "geometry",
        "stylers": [{"color": "#000000"}]
      }
    ]
    ''';
  }

  @override
  void dispose() {
    _mapController?.dispose();
    for (var controller in _markerAnimations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BusMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handleBusUpdates(oldWidget.buses);
  }

  void _handleBusUpdates(List<Bus> oldBuses) {
    for (var bus in widget.buses) {
      final oldPos = _animatedPositions[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
      final oldHeading = _animatedHeadings[bus.id] ?? bus.heading;
      final newPos = LatLng(bus.currentLat, bus.currentLng);
      
      // If the bus moved or rotated, start/update its animation
      if (oldPos.latitude != newPos.latitude || oldPos.longitude != newPos.longitude || oldHeading != bus.heading) {
        _animateBusMarker(bus.id, oldPos, newPos, oldHeading, bus.heading);
      }
      
      // Initial state for new buses
      if (!_animatedPositions.containsKey(bus.id)) {
        _animatedPositions[bus.id] = newPos;
        _animatedHeadings[bus.id] = bus.heading;
      }
    }
  }

  void _animateBusMarker(String busId, LatLng start, LatLng end, double startRotation, double endRotation) {
    // Cancel previous animation if it exists
    _markerAnimations[busId]?.stop();
    _markerAnimations[busId]?.dispose();

    final controller = AnimationController(
      duration: const Duration(milliseconds: 1000), // Glide over 1 second
      vsync: this,
    );

    final animation = CurvedAnimation(parent: controller, curve: Curves.linear);

    controller.addListener(() {
      if (mounted) {
        setState(() {
          final t = animation.value;
          final lat = start.latitude + (end.latitude - start.latitude) * t;
          final lng = start.longitude + (end.longitude - start.longitude) * t;
          _animatedPositions[busId] = LatLng(lat, lng);
          
          // Simple rotation interpolation
          double rotationDiff = endRotation - startRotation;
          if (rotationDiff > 180) rotationDiff -= 360;
          if (rotationDiff < -180) rotationDiff += 360;
          _animatedHeadings[busId] = startRotation + (rotationDiff * t);
        });

        // Drive Mode: smoothly rotate & follow the bus with camera
        if (_isFollowing) {
          final bus = widget.buses.firstWhere((b) => b.id == busId, orElse: () => widget.buses.first);
          final pos = _animatedPositions[busId]!;
          _moveCameraToBus(bus, pos);
        }
      }
    });

    _markerAnimations[busId] = controller;
    controller.forward();
  }

  void _updateMarkers() {
    final Map<String, Marker> newMarkers = {};
    
    for (var bus in widget.buses) {
      final isFocused = _focusedBus?.id == bus.id;
      final pos = _animatedPositions[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
      final heading = _animatedHeadings[bus.id] ?? bus.heading;
      final label = bus.id.substring(bus.id.length.clamp(4, bus.id.length) - 4).toUpperCase();

      // Trigger async icon creation if not yet cached
      _ensureBusIcon(bus.id, label, isFocused: false);
      _ensureBusIcon(bus.id, label, isFocused: true);

      final icon = isFocused
          ? (_focusedBusIcons[bus.id] ?? _busIcons[bus.id] ?? BitmapDescriptor.defaultMarker)
          : (_busIcons[bus.id] ?? BitmapDescriptor.defaultMarker);

      newMarkers[bus.id] = Marker(
        markerId: MarkerId(bus.id),
        position: pos,
        rotation: 0, // rotation is handled by camera bearing in drive mode
        anchor: const Offset(0.5, 0.75), // pin tail anchor point
        flat: true,
        consumeTapEvents: false,
        infoWindow: InfoWindow(
          title: 'Shuttle $label',
          snippet: '${bus.speed.toInt()} km/h  •  ${bus.occupancy}',
        ),
        onTap: () => setState(() {
          _focusedBus = bus;
          _isDriveMode = true;
          _isFollowing = true;
        }),
        icon: icon,
        zIndex: isFocused ? 2.0 : 1.0,
      );

      // Stop markers (only when bus is focused)
      if (isFocused && widget.selectedRoute != null) {
        for (var stop in widget.selectedRoute!.stops) {
          final stopId = 'stop_${stop['name']}';
          newMarkers[stopId] = Marker(
            markerId: MarkerId(stopId),
            position: LatLng(stop['lat'], stop['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            alpha: 0.85,
            infoWindow: InfoWindow(title: stop['name']),
          );
        }
      }

      // Update trail
      final trail = _busTrails[bus.id] ?? [];
      if (trail.isEmpty || Geolocator.distanceBetween(
        trail.first.latitude, trail.first.longitude, pos.latitude, pos.longitude) > 8.0) {
        trail.insert(0, pos);
        if (trail.length > _maxTrailPoints) trail.removeLast();
        _busTrails[bus.id] = trail;
      }
    }

    if (mounted) setState(() { _markers
      ..clear()
      ..addAll(newMarkers); });
  }

  void _updatePolylines() {
    final Map<String, Polyline> newPolylines = {};

    // Selected Route
    if (widget.selectedRoute != null) {
      final routePoints = widget.selectedRoute!.coordinates
          .map((c) => LatLng(c['latitude']!, c['longitude']!))
          .toList();

      newPolylines['selected_route_glow'] = Polyline(
        polylineId: const PolylineId('selected_route_glow'),
        points: routePoints,
        width: 10,
        color: Color(int.parse(widget.selectedRoute!.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.15),
      );

      newPolylines['selected_route'] = Polyline(
        polylineId: const PolylineId('selected_route'),
        points: routePoints,
        width: 5,
        color: Color(int.parse(widget.selectedRoute!.color.replaceAll('#', '0xFF'))),
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      );
    }

    // Bus Trails
    for (var entry in _busTrails.entries) {
      if (entry.value.length >= 2) {
        newPolylines['trail_${entry.key}'] = Polyline(
          polylineId: PolylineId('trail_${entry.key}'),
          points: entry.value,
          width: 4,
          color: Colors.blueAccent.withValues(alpha: 0.3),
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        );
      }
    }

    if (mounted) {
      setState(() {
        _polylines.clear();
        _polylines.addAll(newPolylines);
      });
    }
  }

  Future<void> _requestPermissions() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        _showPermissionDialog(true);
      }
    } else {
      if (mounted) {
        _showPermissionDialog(false);
      }
    }
  }

  void _toggleFollow() {
    setState(() {
      _isFollowing = !_isFollowing;
      if (!_isFollowing) _isDriveMode = false;
      if (_isFollowing && widget.buses.isNotEmpty) {
        final bus = widget.buses.first;
        final pos = _animatedPositions[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
        _moveCameraToBus(bus, pos);
      }
    });
  }

  void _toggleDriveMode() {
    setState(() {
      _isDriveMode = !_isDriveMode;
      if (_isDriveMode) {
        _isFollowing = true;
        // Focus the first bus when entering drive mode
        if (_focusedBus == null && widget.buses.isNotEmpty) {
          _focusedBus = widget.buses.first;
        }
      } else {
        // Exit drive mode — reset camera to top-down view
        final bus = _focusedBus ?? (widget.buses.isNotEmpty ? widget.buses.first : null);
        if (bus != null) {
          final pos = _animatedPositions[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
          _mapController?.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: pos, zoom: 16, tilt: 0, bearing: 0),
          ));
        }
      }
    });
  }

  void _moveCameraToBus(Bus bus, LatLng pos) {
    if (_isDriveMode) {
      // Drive Mode: tilt 45°, rotate map to match bus heading
      final heading = _animatedHeadings[bus.id] ?? bus.heading;
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos,
          zoom: 17.5,
          tilt: 50,              // 3D perspective tilt
          bearing: heading,      // Map rotates with bus
        ),
      ));
    } else {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: 16, tilt: 0, bearing: 0),
      ));
    }
  }

  void _showPermissionDialog(bool isPermanent) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F1528),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
        title: const Text('Location Consent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          isPermanent 
            ? 'Location tracking is disabled in your settings. Please enable it to see your position on the map.'
            : 'We need your location to show where you are relative to the bus. Please grant permission to continue.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A4CFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Future<void> _getCurrentLocation() async {
    try {
      if (!await Permission.location.isGranted) return;
      Position position = await Geolocator.getCurrentPosition();
      final pos = LatLng(position.latitude, position.longitude);
      setState(() => _center = pos);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _updateMarkers();
    _updatePolylines();

    if (_isFollowing && widget.buses.isNotEmpty) {
      final activeBus = widget.buses.firstWhere(
        (b) => widget.selectedRoute != null ? b.routeId == widget.selectedRoute!.id : true,
        orElse: () => widget.buses.first,
      );
      final pos = _animatedPositions[activeBus.id] ?? LatLng(activeBus.currentLat, activeBus.currentLng);
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(pos)
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: widget.buses.isNotEmpty 
              ? LatLng(widget.buses.first.currentLat, widget.buses.first.currentLng) 
              : _bhopal,
            zoom: 15,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            if (_currentMapType == MapType.none) {
               _mapController?.setMapStyle(_darkMapStyle);
            }
            // Move camera to the first bus once map is ready
            if (widget.buses.isNotEmpty) {
              final b = widget.buses.first;
              _mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                LatLng(b.currentLat, b.currentLng), 15,
              ));
            }
          },
          mapType: _currentMapType == MapType.none ? MapType.normal : _currentMapType,
          markers: Set<Marker>.of(_markers.values),
          polylines: Set<Polyline>.of(_polylines.values),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
          tiltGesturesEnabled: true,
          onTap: (_) => setState(() => _focusedBus = null),
        ),
        Positioned(
          right: 20,
          top: 100,
          child: Column(
            children: [
              _buildMapControl(
                icon: Icons.layers_rounded,
                onTap: () => setState(() => _showLayerSelector = !_showLayerSelector),
                isActive: _showLayerSelector,
              ),
              if (_showLayerSelector) ...[
                const SizedBox(height: 8),
                _buildLayerItem(MapType.normal, Icons.map_rounded),
                const SizedBox(height: 8),
                _buildLayerItem(MapType.satellite, Icons.satellite_alt_rounded),
                const SizedBox(height: 8),
                _buildLayerItem(MapType.hybrid, Icons.layers_outlined),
                const SizedBox(height: 8),
                _buildLayerItem(MapType.terrain, Icons.terrain_rounded),
                const SizedBox(height: 8),
                _buildLayerItem(MapType.none, Icons.nightlight_round), // 'none' represents Dark
              ],
              const SizedBox(height: 12),
              _buildMapControl(
                icon: Icons.gps_fixed_rounded,
                onTap: _toggleFollow,
                isActive: _isFollowing,
              ),
              const SizedBox(height: 12),
              // Drive Mode toggle button
              _buildMapControl(
                icon: Icons.navigation_rounded,
                onTap: _toggleDriveMode,
                isActive: _isDriveMode,
                activeColor: const Color(0xFF00C853),
              ),
              const SizedBox(height: 12),
              _buildMapControl(
                icon: Icons.my_location_rounded,
                onTap: _getCurrentLocation,
              ),
            ],
          ),
        ),

        // Drive Mode top HUD
        if (_isDriveMode && _focusedBus != null)
          Positioned(
            top: 16,
            left: 16,
            right: 80,
            child: GestureDetector(
              onTap: _toggleDriveMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFF00C853).withValues(alpha: 0.4), blurRadius: 16)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'DRIVE MODE  •  ${(_animatedHeadings[_focusedBus!.id] ?? 0).toInt()}°  •  Tap to exit',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Bus Detail Card
        if (_focusedBus != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0B14).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      )
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
                                colors: [const Color(0xFF1A4CFF), const Color(0xFF1A4CFF).withValues(alpha: 0.6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF1A4CFF).withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 2)
                              ],
                            ),
                            child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SHUTTLE ${_focusedBus!.id.substring(_focusedBus!.id.length - 4).toUpperCase()}',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ACTIVE ON ${_focusedBus!.routeId.toUpperCase()}',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white60,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _focusedBus = null),
                            icon: const Icon(Icons.close_rounded, color: Colors.white38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildPremiumStat(Icons.speed_rounded, '${_focusedBus!.speed.toInt()}', 'KM/H'),
                          _buildPremiumStat(Icons.people_alt_rounded, _focusedBus!.occupancy, 'LOAD'),
                          _buildPremiumStat(Icons.timer_outlined, _focusedBus!.etas.isNotEmpty ? '${_focusedBus!.etas.first.minutes}' : '--', 'NEXT ETA'),
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
                            separatorBuilder: (_, __) => const SizedBox(width: 20),
                            itemBuilder: (context, index) {
                              final eta = _focusedBus!.etas[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    eta.stopName.toUpperCase(),
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${eta.minutes} MIN',
                                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A4CFF), fontSize: 14, fontWeight: FontWeight.w800),
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
          ).animate().slideY(begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutQuart).fadeIn(),
      ],
    );
  }

  Widget _buildLayerItem(MapType type, IconData icon) {
    bool isSelected = _currentMapType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _currentMapType = type;
        if (type == MapType.none) {
          _mapController?.setMapStyle(_darkMapStyle);
        } else {
          _mapController?.setMapStyle(null);
        }
        _showLayerSelector = false;
      }),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A4CFF) : Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ).animate().slideX(begin: 0.5, end: 0);
  }

  Widget _buildMapControl({required IconData icon, required VoidCallback onTap, bool isActive = false, Color? activeColor}) {
    final Color activeBg = (activeColor ?? const Color(0xFF1A4CFF)).withValues(alpha: 0.85);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isActive ? activeBg : Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: isActive ? (activeColor ?? const Color(0xFF1A4CFF)).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
              boxShadow: isActive ? [BoxShadow(color: (activeColor ?? const Color(0xFF1A4CFF)).withValues(alpha: 0.4), blurRadius: 12)] : [],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackerTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: const Color(0xFF1A4CFF)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildPremiumStat(IconData icon, String value, String unit) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1A4CFF), size: 20),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            Text(unit, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
      ],
    );
  }
}
