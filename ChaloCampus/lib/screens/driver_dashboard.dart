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
  Position? _prevPosition; // for distance tracking
  DateTime? _prevPositionTime; // for computed speed fallback
  StreamSubscription<Position>? _positionStream;
  double _speedKmH = 0.0;
  double _sessionDistanceKm = 0.0;
  int _sessionStops = 0;
  final List<double> _recentSpeeds = List.filled(15, 0.0);
  final ApiService _apiService = ApiService();
  List<dynamic> _buses = [];
  String? _selectedBusId;
  RouteModel? _selectedRoute;
  bool _isSosActive = false;
  Timer? _heartbeatTimer;
  final ValueNotifier<DateTime?> _lastEmitTime = ValueNotifier<DateTime?>(null);

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

    setState(() => _isOnline = true);
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        // distanceFilter: 5m for stable GPS speed — no timeLimit (it kills the stream!)
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        if (!mounted) return;
        setState(() {
          // ── Accumulate session distance ─────────────────────────────
          double distMeters = 0;
          if (_prevPosition != null) {
            distMeters = Geolocator.distanceBetween(
              _prevPosition!.latitude, _prevPosition!.longitude,
              position.latitude, position.longitude,
            );
            _sessionDistanceKm += distMeters / 1000.0;
          }

          // ── Speed: prefer GPS chip value; fall back to computed ─────
          double gpsSpeed = position.speed * 3.6; // m/s → km/h
          if (gpsSpeed <= 0 && _prevPosition != null && _prevPositionTime != null) {
            final elapsedSec = DateTime.now()
                .difference(_prevPositionTime!)
                .inMilliseconds / 1000.0;
            if (elapsedSec > 0) {
              gpsSpeed = (distMeters / elapsedSec) * 3.6;
            }
          }
          _speedKmH = gpsSpeed.clamp(0.0, 200.0);

          _prevPosition     = position;
          _prevPositionTime = DateTime.now();
          _currentPosition  = position;

          _recentSpeeds.removeAt(0);
          _recentSpeeds.add(_speedKmH);
        });
        _emitLocation();
      },
      onError: (dynamic err) {
        // Stream error (e.g. GPS unavailable) — log and keep running
        debugPrint('⚠️ GPS stream error: $err');
      },
    );

    // Heartbeat: keeps listeners alive even when stationary
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isOnline) _emitLocation();
    });
  }

  void _stopTracking() {
    _positionStream?.cancel();
    _heartbeatTimer?.cancel();
    setState(() {
      _isOnline         = false;
      _speedKmH         = 0;
      _sessionDistanceKm = 0;
      _sessionStops     = 0;
      _prevPosition     = null;
      _prevPositionTime = null; // reset computed-speed timestamp
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
      'heading': _currentPosition!.heading,
      'speed': _speedKmH,
      'status': 'On-time',
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    debugPrint('📡 Emitted Location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
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

  Widget _buildTrackerCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161421),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Speedometer', style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_speedKmH.toStringAsFixed(1), style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: -2)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, left: 8),
                        child: Text('KM/H', style: TextStyle(color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ],
              ),
              _buildLiveIndicator(),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _recentSpeeds.asMap().entries.map((e) {
                final double h = (e.value * 1.5).clamp(4.0, 60.0);
                final bool isHighest = e.value == _recentSpeeds.reduce((a, b) => a > b ? a : b) && e.value > 0;
                return Container(
                  width: 14,
                  height: h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: _isOnline 
                        ? [Colors.deepPurpleAccent, isHighest ? Colors.redAccent : Colors.blueAccent]
                        : [Colors.white10, Colors.white10],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                );
              }).toList(),
            ),
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
