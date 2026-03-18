import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';

class BusMap extends StatefulWidget {
  final List<Bus> buses;
  final RouteModel? selectedRoute;

  const BusMap({
    super.key,
    required this.buses,
    this.selectedRoute,
  });

  @override
  State<BusMap> createState() => _BusMapState();
}

enum MapStyle { standard, dark }

class _BusMapState extends State<BusMap> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(23.2599, 77.4126); // Default: Bhopal
  Bus? _focusedBus;
  bool _isFollowing = false;
  MapStyle _currentStyle = MapStyle.dark;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
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

  void _toggleStyle() {
    setState(() {
      _currentStyle = _currentStyle == MapStyle.dark ? MapStyle.standard : MapStyle.dark;
    });
  }

  void _toggleFollow() {
    setState(() {
      _isFollowing = !_isFollowing;
      if (_isFollowing && widget.buses.isNotEmpty) {
        final bus = widget.buses.first;
        _mapController.move(LatLng(bus.currentLat, bus.currentLng), _mapController.camera.zoom);
      }
    });
  }

  void _showPermissionDialog(bool isPermanent) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c1e),
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
              backgroundColor: const Color(0xFF38ef7d),
              foregroundColor: Colors.black,
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
      setState(() {
        _center = LatLng(position.latitude, position.longitude);
        _mapController.move(_center, 15);
      });
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFollowing && widget.buses.isNotEmpty) {
      final activeBus = widget.buses.firstWhere(
        (b) => widget.selectedRoute != null ? b.routeId == widget.selectedRoute!.id : true,
        orElse: () => widget.buses.first,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(LatLng(activeBus.currentLat, activeBus.currentLng), _mapController.camera.zoom);
      });
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 13.0,
            onTap: (_, __) => setState(() => _focusedBus = null),
          ),
          children: [
            if (_currentStyle == MapStyle.dark)
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              )
            else
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
            if (widget.selectedRoute != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.selectedRoute!.coordinates
                        .map((c) => LatLng(c['latitude']!, c['longitude']!))
                        .toList(),
                    strokeWidth: 5,
                    color: Color(int.parse(widget.selectedRoute!.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.6),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _center,
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                      ).animate(onPlay: (controller) => controller.repeat())
                       .scale(begin: const Offset(1, 1), end: const Offset(3, 3), duration: 2000.ms, curve: Curves.easeOut)
                       .fadeOut(),
                      const Icon(Icons.my_location, color: Colors.blue, size: 24),
                    ],
                  ),
                ),
                ...widget.buses.map((bus) => Marker(
                  point: LatLng(bus.currentLat, bus.currentLng),
                  width: 60,
                  height: 60,
                  child: GestureDetector(
                    onTap: () => setState(() => _focusedBus = bus),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                         Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFF38ef7d).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                        ).animate(onPlay: (controller) => controller.repeat())
                         .scale(begin: const Offset(0.8, 0.8), end: const Offset(2, 2))
                         .fadeOut(duration: 1500.ms),
                        Transform.rotate(
                          angle: bus.heading * (3.14159 / 180),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1c1c1e),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _focusedBus?.id == bus.id ? Colors.white : const Color(0xFF38ef7d), 
                                width: 2
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF38ef7d).withValues(alpha: 0.5), 
                                  blurRadius: _focusedBus?.id == bus.id ? 15 : 10
                                )
                              ]
                            ),
                            child: const Icon(Icons.directions_bus, color: Color(0xFF38ef7d), size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
                if (widget.selectedRoute != null)
                  ...widget.selectedRoute!.stops.map((stop) {
                    // Try to find matching ETA for this stop from the focused bus
                    int? etaMinutes;
                    if (_focusedBus != null && _focusedBus!.etas != null) {
                      final etaMatch = _focusedBus!.etas!.firstWhere(
                        (e) => e['stopName'] == stop['name'],
                        orElse: () => null,
                      );
                      if (etaMatch != null) etaMinutes = etaMatch['minutes'];
                    }

                    return Marker(
                      point: LatLng(stop['lat'], stop['lng']),
                      width: 100,
                      height: 65,
                      child: Column(
                        children: [
                          if (etaMinutes != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF38ef7d),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${etaMinutes}m',
                                style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ).animate().fadeIn().scale(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              stop['name'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 8),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 120,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'style',
                backgroundColor: Colors.black87,
                onPressed: _toggleStyle,
                child: Icon(_currentStyle == MapStyle.dark ? Icons.map : Icons.dark_mode, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: 'follow',
                backgroundColor: _isFollowing ? const Color(0xFF38ef7d) : Colors.black87,
                onPressed: _toggleFollow,
                child: Icon(Icons.gps_fixed, color: _isFollowing ? Colors.black : Colors.white70),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.small(
                heroTag: 'location',
                backgroundColor: Colors.black87,
                onPressed: _getCurrentLocation,
                child: const Icon(Icons.my_location, color: Colors.white70),
              ),
            ],
          ),
        ),

        // Bus Detail Card
        if (_focusedBus != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1c1c1e).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF38ef7d).withValues(alpha: 0.3)),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38ef7d).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.speed, color: Color(0xFF38ef7d)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Bus ID: ${_focusedBus!.id.substring(_focusedBus!.id.length - 6).toUpperCase()}', 
                                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            if (_focusedBus!.status != 'Offline')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38ef7d).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('LIVE', style: TextStyle(color: Color(0xFF38ef7d), fontSize: 8, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildTelemetryTag(Icons.navigation, '${_focusedBus!.heading.toInt()}°'),
                            const SizedBox(width: 8),
                            _buildTelemetryTag(Icons.people, _focusedBus!.occupancy),
                            const SizedBox(width: 8),
                            _buildTelemetryTag(Icons.bolt, '${_focusedBus!.speed.toInt()} km/h'),
                          ],
                        ),
                        if (_focusedBus!.etas != null && _focusedBus!.etas!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _focusedBus!.etas!.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final eta = _focusedBus!.etas![index];
                                return Column(
                                  children: [
                                    Text(eta['stopName'], style: const TextStyle(color: Colors.white54, fontSize: 8)),
                                    const SizedBox(height: 2),
                                    Text('${eta['minutes']}m', style: const TextStyle(color: Color(0xFF38ef7d), fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => setState(() => _focusedBus = null),
                  ),
                ],
              ),
            ).animate().slideY(begin: 0.5, end: 0, curve: Curves.easeOutCubic),
          ),
      ],
    );
  }

  Widget _buildTelemetryTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: const Color(0xFF38ef7d)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}
