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
  LatLng _center = const LatLng(23.2599, 77.4126); // Default Center
  Bus? _focusedBus;
  bool _isFollowing = false;
  MapType _currentMapType = MapType.normal;
  bool _showLayerSelector = false;
  
  final Map<String, Marker> _markers = {};
  final Map<String, Polyline> _polylines = {};
  final Map<String, List<LatLng>> _busTrails = {};
  final Map<String, AnimationController> _markerAnimations = {};
  final Map<String, LatLng> _animatedPositions = {};
  final Map<String, double> _animatedHeadings = {};
  
  BitmapDescriptor? _busIcon;
  BitmapDescriptor? _focusedBusIcon;
  
  static const int _maxTrailPoints = 15;

  String? _darkMapStyle;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _createMarkerIcons();
  }

  Future<void> _createMarkerIcons() async {
    _busIcon = await _getAssetIcon(Colors.blueAccent);
    _focusedBusIcon = await _getAssetIcon(Colors.white);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _getAssetIcon(Color color) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 120.0;
    
    // Shadow
    final Paint shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(const Offset(size/2, size/2), size/3, shadowPaint);

    // Background Circle
    final Paint bgPaint = Paint()..color = const Color(0xFF0D0B14);
    canvas.drawCircle(const Offset(size/2, size/2), size/3, bgPaint);
    
    // Border
    final Paint borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(const Offset(size/2, size/2), size/3, borderPaint);

    // Bus Icon (Simplified path or just Text/Icon)
    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.directions_bus_rounded.codePoint),
      style: TextStyle(
        fontSize: 45.0,
        fontFamily: Icons.directions_bus_rounded.fontFamily,
        color: color,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size/2 - textPainter.width/2, size/2 - textPainter.height/2));

    // Direction Pointer (Triangle)
    final Path path = Path();
    path.moveTo(size/2, 10);
    path.lineTo(size/2 - 10, 25);
    path.lineTo(size/2 + 10, 25);
    path.close();
    canvas.drawPath(path, Paint()..color = color);

    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
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
      }
    });

    _markerAnimations[busId] = controller;
    controller.forward();
  }

  void _updateMarkers() {
    final Map<String, Marker> newMarkers = {};
    
    // User Location Marker (Blue Dot)
    newMarkers['user_location'] = Marker(
      markerId: const MarkerId('user_location'),
      position: _center,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );

    for (var bus in widget.buses) {
      final isFocused = _focusedBus?.id == bus.id;
      final pos = _animatedPositions[bus.id] ?? LatLng(bus.currentLat, bus.currentLng);
      final heading = _animatedHeadings[bus.id] ?? bus.heading;
      final busIdLabel = bus.id.substring(bus.id.length - 4).toUpperCase();
      
      // Main Bus Marker
      newMarkers[bus.id] = Marker(
        markerId: MarkerId(bus.id),
        position: pos,
        rotation: heading,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        infoWindow: InfoWindow(
          title: 'Shuttle $busIdLabel',
          snippet: '${bus.speed.toInt()} km/h • ${bus.occupancy} Load',
        ),
        onTap: () => setState(() => _focusedBus = bus),
        icon: isFocused ? (_focusedBusIcon ?? BitmapDescriptor.defaultMarker) : (_busIcon ?? BitmapDescriptor.defaultMarker),
      );

      // Add Stop markers for the focused bus route
      if (isFocused && widget.selectedRoute != null) {
        for (var stop in widget.selectedRoute!.stops) {
          final stopId = 'stop_${stop['name']}';
          newMarkers[stopId] = Marker(
            markerId: MarkerId(stopId),
            position: LatLng(stop['lat'], stop['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            alpha: 0.8,
            infoWindow: InfoWindow(title: stop['name']),
          );
        }
      }

      // Update trail
      final trail = _busTrails[bus.id] ?? [];
      if (trail.isEmpty || Geolocator.distanceBetween(trail.first.latitude, trail.first.longitude, pos.latitude, pos.longitude) > 10.0) {
        trail.insert(0, pos);
        if (trail.length > _maxTrailPoints) trail.removeLast();
        _busTrails[bus.id] = trail;
      }
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(newMarkers);
      });
    }
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
      if (_isFollowing && widget.buses.isNotEmpty) {
        final bus = widget.buses.first;
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(bus.currentLat, bus.currentLng))
        );
      }
    });
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
          initialCameraPosition: CameraPosition(target: _center, zoom: 14),
          onMapCreated: (controller) {
            _mapController = controller;
            if (_currentMapType == MapType.none) { // We'll use 'none' for our custom dark
               _mapController?.setMapStyle(_darkMapStyle);
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
              _buildMapControl(
                icon: Icons.my_location_rounded,
                onTap: _getCurrentLocation,
              ),
            ],
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
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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

  Widget _buildMapControl({required IconData icon, required VoidCallback onTap, bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF1A4CFF).withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
