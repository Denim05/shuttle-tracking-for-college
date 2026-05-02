import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../components/bus_map.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isOnline = false;
  Position? _currentPosition;
  Position? _prevPosition;
  DateTime? _prevPositionTime;
  StreamSubscription<Position>? _positionStream;
  double _speedKmH = 0.0;
  double _smoothedSpeedKmH = 0.0; // EMA-smoothed speed for display
  double _sessionDistanceKm = 0.0;
  int _sessionStops = 0;
  final List<double> _recentSpeeds = List.filled(15, 0.0);
  int _recentSpeedIndex = 0; // circular buffer index
  final ApiService _apiService = ApiService();
  List<dynamic> _buses = [];
  String? _selectedBusId;
  RouteModel? _selectedRoute;
  bool _isSosActive = false;
  Timer? _heartbeatTimer;
  final ValueNotifier<DateTime?> _lastEmitTime = ValueNotifier<DateTime?>(null);

  // ── Speed smoothing constants ──────────────────────────────────────────────
  static const double _emaAlpha = 0.3; // Exponential Moving Average factor
  static const double _speedThresholdMps = 0.5; // min GPS speed to trust (0.5 m/s ≈ 1.8 km/h)

  @override
  void initState() {
    super.initState();
    _fetchMyBus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocketListeners());
  }

  void _initSocketListeners() {
    final socketService = Provider.of<SocketService>(context, listen: false);

    // Listen for manager broadcast alerts
    socketService.listenToSystemAlerts((data) {
      if (mounted && data != null && data['message'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            behavior: SnackBarBehavior.floating,
            content: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF161421),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), blurRadius: 16)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data['message'],
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMyBus() async {
    try {
      final response = await _apiService.get('drivers/my-bus');
      if (!mounted) return;
      setState(() {
        _buses = [response]; // Put in list for compat with existing UI if needed
        _selectedBusId = response['_id'];
        _fetchRouteDetails(response['routeId']);
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error fetching my bus: $e');
      // Fallback to fetch all if assigned not found (optional, but keep it clean)
      _fetchAllBuses();
    }
  }

  Future<void> _fetchAllBuses() async {
    try {
      final response = await _apiService.get('buses');
      if (!mounted) return;
      setState(() {
        _buses = response;
        if (_buses.isNotEmpty && _selectedBusId == null) {
          _selectedBusId = _buses[0]['_id'];
          _fetchRouteDetails(_buses[0]['routeId']);
        }
      });
    } catch (e) {
      debugPrint('Error fetching all buses: $e');
    }
  }

  Future<void> _fetchRouteDetails(String? routeId) async {
    if (routeId == null) return;
    try {
      final response = await _apiService.get('routes/$routeId');
      if (!mounted) return;
      setState(() {
        _selectedRoute = RouteModel.fromJson(response);
      });
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
  }

  Future<void> _toggleOnlineStatus() async {
    if (_selectedBusId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a bus first')));
      return;
    }
    _isOnline ? _stopTracking() : await _startTracking();
  }

  Future<void> _startTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied. Please enable in settings.')),
        );
      }
      return;
    }

    setState(() => _isOnline = true);
    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,          // Get EVERY update — no distance filter for real-time
        intervalDuration: const Duration(seconds: 2), // at least every 2 seconds
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ChaloCampus Tracking',
          notificationText: 'Broadcasting your location to students',
          enableWakeLock: true,
        ),
      ),
    ).listen(
      (Position position) {
        if (!mounted) return;
        setState(() {
          // ── Session distance accumulation ─────────────────────────────────
          double distMeters = 0;
          if (_prevPosition != null) {
            distMeters = Geolocator.distanceBetween(
              _prevPosition!.latitude, _prevPosition!.longitude,
              position.latitude, position.longitude,
            );
            // Only count movement ≥ 2m to avoid GPS drift noise
            if (distMeters >= 2.0) {
              _sessionDistanceKm += distMeters / 1000.0;
            }
          }

          // ── Speed calculation with multi-source fallback ──────────────────
          double rawSpeedKmH = 0.0;

          // Source 1: GPS chip speed (most accurate when moving)
          if (position.speed >= _speedThresholdMps) {
            rawSpeedKmH = position.speed * 3.6; // m/s → km/h
          }
          // Source 2: Computed from distance/time delta (fallback)
          else if (distMeters >= 2.0 && _prevPosition != null && _prevPositionTime != null) {
            final elapsedSec = DateTime.now()
                .difference(_prevPositionTime!)
                .inMilliseconds / 1000.0;
            if (elapsedSec > 0.5) { // Need at least 0.5s gap to be meaningful
              rawSpeedKmH = (distMeters / elapsedSec) * 3.6;
            }
          }

          // Clamp to realistic bus speeds (0 to 120 km/h)
          rawSpeedKmH = rawSpeedKmH.clamp(0.0, 120.0);

          // ── Exponential Moving Average smoothing ──────────────────────────
          // Smooths out GPS jitter while staying responsive to speed changes
          _smoothedSpeedKmH = (_emaAlpha * rawSpeedKmH) + ((1 - _emaAlpha) * _smoothedSpeedKmH);
          _speedKmH = _smoothedSpeedKmH;

          // ── Update circular speed history buffer ──────────────────────────
          _recentSpeeds[_recentSpeedIndex % 15] = _speedKmH;
          _recentSpeedIndex++;

          _prevPosition     = position;
          _prevPositionTime = DateTime.now();
          _currentPosition  = position;
        });

        // Emit every GPS update for smooth real-time tracking
        _emitLocation();
      },
      onError: (dynamic err) {
        debugPrint('⚠️ GPS stream error: $err');
      },
    );

    // Heartbeat: keeps users' maps alive even if GPS doesn't fire
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isOnline && _currentPosition != null) _emitLocation();
    });
  }

  void _stopTracking() {
    _positionStream?.cancel();
    _heartbeatTimer?.cancel();
    setState(() {
      _isOnline         = false;
      _speedKmH            = 0;
      _smoothedSpeedKmH    = 0;
      _sessionDistanceKm   = 0;
      _sessionStops        = 0;
      _prevPosition        = null;
      _prevPositionTime    = null;
      _recentSpeedIndex    = 0;
      _recentSpeeds.fillRange(0, 15, 0.0);
    });
  }

  void _emitLocation() {
    if (_currentPosition == null || _selectedBusId == null) return;
    
    // Trigger visual pulse
    _lastEmitTime.value = DateTime.now();
    
    final socketService = Provider.of<SocketService>(context, listen: false);
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    final selectedBus = _buses.firstWhere((b) => b['_id'] == _selectedBusId, orElse: () => null);
    
    socketService.emitLocationUpdate({
      'driverId': user.id,
      'busId': _selectedBusId,
      'id': _selectedBusId,
      'routeId': selectedBus != null ? selectedBus['routeId'] : null,
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'heading': _currentPosition!.heading >= 0 ? _currentPosition!.heading : 0.0,
      'speed': double.parse(_speedKmH.toStringAsFixed(1)), // Round to 1dp
      'status': 'On-time',
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    debugPrint('📡 Emitted: Lat=${_currentPosition!.latitude.toStringAsFixed(5)}, Lng=${_currentPosition!.longitude.toStringAsFixed(5)}, Speed=${_speedKmH.toStringAsFixed(1)} KM/H');
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    final socketService = Provider.of<SocketService>(context);
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      body: ValueListenableBuilder<bool>(
        valueListenable: socketService.connectionStatus,
        builder: (context, isConnected, child) {
          return Stack(
            children: [
              // Background Map — always visible, centered on driver GPS
              _selectedRoute != null
                  ? BusMap(
                      buses: [
                        Bus(
                          id: _selectedBusId ?? 'driver',
                          routeId: _selectedRoute!.id,
                          routeName: _selectedRoute!.name,
                          routeColor: _selectedRoute!.color,
                          currentLat: _currentPosition?.latitude ?? 23.1270,
                          currentLng: _currentPosition?.longitude ?? 77.3494,
                          heading: _currentPosition?.heading ?? 0.0,
                          speed: _speedKmH,
                          status: _isOnline ? 'On-time' : 'Offline',
                          lastUpdated: DateTime.now(),
                        )
                      ],
                      selectedRoute: _selectedRoute,
                      initialDriveMode: true,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topRight,
                          radius: 1.5,
                          colors: [Color(0xFF161421), Color(0xFF0D0B14)],
                        ),
                      ),
                    ),

              // Reconnecting Guard
              if (!isConnected)
                Positioned(
                  top: MediaQuery.of(context).padding.top,
                  left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.redAccent.withValues(alpha: 0.8),
                    child: Center(
                      child: Text(
                        '📡 SYNCHRONIZING WITH COMMAND...',
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
                ),

              // Header
              Positioned(
                top: isConnected ? 0 : 25,
                left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 30),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Driver Dashboard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildSignalStrength(isConnected),
                              const SizedBox(width: 8),
                              Text(
                                isConnected ? 'Connected' : 'SYNCHRONIZING...',
                                style: TextStyle(
                                  color: isConnected ? Colors.blueAccent : Colors.redAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20),
                        onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Main Content with Draggable Sheet
              DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0B14),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: 10),
                      ],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                        children: [
                          // Handle
                          Center(
                            child: Container(
                              width: 48,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 30, top: 8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Colors.deepPurpleAccent, Colors.blueAccent]),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          
                          _buildDriverHero(user),
                          const SizedBox(height: 32),
                          _buildTrackerCard(),
                          const SizedBox(height: 32),
                          _buildBusSelector(),
                          const SizedBox(height: 20),
                          _buildStartButton(),
                          const SizedBox(height: 24),
                          _buildSOSButton(user),
                          const SizedBox(height: 32),
                          _buildTripStats(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDriverHero(User? user) {
    return Row(
      children: [
        Container(
          height: 64, width: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Colors.deepPurpleAccent, Colors.blueAccent]),
            boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)],
          ),
          child: const Center(child: Icon(Icons.person_rounded, color: Colors.white, size: 32)),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver Status', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text(user?.username.toUpperCase() ?? 'CAPTAIN', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ],
        ),
      ],
    ).animate().fadeIn().slideX();
  }

  // Speed color based on km/h value
  Color _speedColor(double speed) {
    if (speed < 20) return Colors.blueAccent;
    if (speed < 40) return const Color(0xFF00C853); // green
    if (speed < 60) return Colors.orangeAccent;
    if (speed < 80) return Colors.deepOrangeAccent;
    return Colors.redAccent;
  }

  String _speedCategory(double speed) {
    if (!_isOnline) return 'OFFLINE';
    if (speed < 5) return 'STATIONARY';
    if (speed < 25) return 'LOW SPEED';
    if (speed < 50) return 'NORMAL';
    if (speed < 70) return 'FAST';
    return 'HIGH SPEED';
  }

  Widget _buildTrackerCard() {
    final sColor = _speedColor(_speedKmH);
    final sortedSpeeds = List<double>.from(_recentSpeeds)..sort();
    final maxRecentSpeed = sortedSpeeds.isNotEmpty ? sortedSpeeds.last : 1.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161421),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: _isOnline ? sColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
        boxShadow: _isOnline ? [BoxShadow(color: sColor.withValues(alpha: 0.08), blurRadius: 20, spreadRadius: 2)] : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SPEEDOMETER', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(color: _isOnline ? sColor : Colors.white38, fontSize: 64, fontWeight: FontWeight.w900, letterSpacing: -2),
                        child: Text(_speedKmH.toStringAsFixed(1)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, left: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('KM/H', style: TextStyle(color: sColor, fontSize: 13, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: sColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: sColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                _speedCategory(_speedKmH),
                                style: TextStyle(color: sColor, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_currentPosition != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.my_location_rounded, color: Colors.white24, size: 10),
                        const SizedBox(width: 4),
                        Text(
                          '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(color: Colors.white24, fontSize: 9, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    if (_currentPosition!.accuracy > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.gps_fixed_rounded, color: Colors.white24, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            'GPS ±${_currentPosition!.accuracy.toStringAsFixed(0)}m',
                            style: TextStyle(
                              color: _currentPosition!.accuracy < 10 ? const Color(0xFF00C853) : Colors.orangeAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
              _buildLiveIndicator(),
            ],
          ),
          const SizedBox(height: 20),
          // Speed history bars — fixed sorted order, most recent on right
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SPEED HISTORY', style: TextStyle(color: Colors.white12, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              SizedBox(
                height: 55,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _recentSpeeds.map((speed) {
                    final maxRef = maxRecentSpeed > 0 ? maxRecentSpeed : 1.0;
                    final double h = ((speed / maxRef) * 52).clamp(3.0, 52.0);
                    final barColor = _speedColor(speed);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 13,
                      height: h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: _isOnline
                            ? [barColor.withValues(alpha: 0.4), barColor]
                            : [Colors.white10, Colors.white10],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().scale(delay: 200.ms);
  }

  Widget _buildLiveIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white24, size: 20),
          onPressed: () => Provider.of<SocketService>(context, listen: false).reconnect(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: (_isOnline ? Colors.blueAccent : Colors.white10).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (_isOnline ? Colors.blueAccent : Colors.white24).withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isOnline) ...[
                ValueListenableBuilder<DateTime?>(
                  valueListenable: _lastEmitTime,
                  builder: (context, time, _) {
                    return Icon(
                      Icons.sensors_rounded, 
                      color: Colors.blueAccent, 
                      size: 14,
                      key: ValueKey(time?.millisecondsSinceEpoch ?? 0),
                    ).animate(key: ValueKey(time?.millisecondsSinceEpoch ?? 0))
                     .scale(begin: const Offset(1,1), end: const Offset(1.5,1.5))
                     .fadeOut(duration: 400.ms);
                  },
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.blueAccent, blurRadius: 4)]),
                ).animate(onPlay: (c) => c.repeat()).scale(duration: 1.seconds, begin: const Offset(1,1), end: const Offset(1.5,1.5)).fadeOut(),
                const SizedBox(width: 8),
              ],
              Text(_isOnline ? 'ACTIVE' : 'OFFLINE', style: TextStyle(color: _isOnline ? Colors.blueAccent : Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161421),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: const Color(0xFF0D0B14),
          value: _selectedBusId,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.blueAccent),
          hint: Text('SELECT ASSIGNED BUS', style: TextStyle(color: Colors.white24, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
          items: _buses.map((bus) => DropdownMenuItem<String>(
            value: bus['_id'],
            child: Text(bus['routeName'] ?? 'Unknown Route', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          )).toList(),
          onChanged: _isOnline ? null : (v) {
            setState(() => _selectedBusId = v);
            final bus = _buses.firstWhere((b) => b['_id'] == v, orElse: () => null);
            if (bus != null) _fetchRouteDetails(bus['routeId']);
          },
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _toggleOnlineStatus,
      child: AnimatedContainer(
        duration: 400.ms,
        height: 72,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isOnline 
              ? [Colors.redAccent, const Color(0xFFE94560)] 
              : [Colors.deepPurpleAccent, const Color(0xFF3F37C9)]
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (_isOnline ? Colors.redAccent : Colors.deepPurpleAccent).withValues(alpha: 0.4), 
              blurRadius: 25, 
              offset: const Offset(0, 10)
            )
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_isOnline ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Text(
                _isOnline ? 'Go Offline' : 'Go Online',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _triggerSOS(User? user) async {
    if (_isSosActive) return;
    setState(() => _isSosActive = true);

    // Cache context-dependent values BEFORE any awaits
    final socketService = context.read<SocketService>();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      Position? position;
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      }

      if (!mounted) return;
      
      final payload = {
        'userId': user?.id ?? 'driver',
        'name': user?.username ?? 'Driver',
        'role': 'driver',
        'latitude': position?.latitude ?? _currentPosition?.latitude ?? 0.0,
        'longitude': position?.longitude ?? _currentPosition?.longitude ?? 0.0,
        'timestamp': DateTime.now().toIso8601String(),
        'busId': _selectedBusId,
      };

      socketService.emitSOSAlert(payload);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SOS Alert Sent', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        )
      );
    } catch (e) {
      debugPrint('SOS Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSosActive = false);
      }
    }
  }

  Widget _buildSOSButton(User? user) {
    return GestureDetector(
      onLongPress: () => _triggerSOS(user),
      child: Container(
        height: 70,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2), width: 2),
        ),
        child: _isSosActive 
            ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'HOLD 2S FOR SOS',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2),
                  ),
                ],
              ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(color: Colors.redAccent.withValues(alpha: 0.2), duration: 2.seconds);
  }

  Widget _buildTripStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SESSION OVERVIEW', style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildSmallStat('DISTANCE', _sessionDistanceKm.toStringAsFixed(1), 'KM', Colors.deepPurpleAccent),
            const SizedBox(width: 16),
            _buildSmallStat('STOPS', _sessionStops.toString(), 'PTS', Colors.blueAccent),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildSmallStat(String label, String value, String unit, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161421),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Text(unit, style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalStrength(bool isConnected) {
    return Row(
      children: List.generate(4, (index) {
        final active = isConnected && index < 3; // Mocking strength
        return Container(
          width: 3,
          height: 4.0 + (index * 3),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active ? Colors.blueAccent : Colors.white12,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
