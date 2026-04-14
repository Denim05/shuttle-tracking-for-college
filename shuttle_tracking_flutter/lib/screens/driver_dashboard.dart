import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isOnline = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  double _speedKmH = 0.0;
  final List<double> _recentSpeeds = List.filled(15, 0.0);
  final ApiService _apiService = ApiService();
  List<dynamic> _buses = [];
  String? _selectedBusId;
  bool _isLoadingBuses = true;
  bool _isSosActive = false;

  @override
  void initState() {
    super.initState();
    _fetchBuses();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _fetchBuses() async {
    try {
      final response = await _apiService.get('buses');
      if (!mounted) return;
      setState(() {
        _buses = response;
        _isLoadingBuses = false;
        if (_buses.isNotEmpty) {
          _selectedBusId = _buses[0]['_id'];
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingBuses = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load buses: $e')));
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _speedKmH = position.speed * 3.6;
        _recentSpeeds.removeAt(0);
        _recentSpeeds.add(_speedKmH);
      });
      _emitLocation();
    });
  }

  void _stopTracking() {
    _positionStream?.cancel();
    setState(() {
      _isOnline = false;
      _speedKmH = 0;
      _recentSpeeds.fillRange(0, 15, 0.0);
    });
  }

  void _emitLocation() {
    if (_currentPosition == null || _selectedBusId == null) return;
    final socketService = Provider.of<SocketService>(context, listen: false);
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    socketService.emitLocationUpdate({
      'driverId': user.id,
      'busId': _selectedBusId,
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'heading': _currentPosition!.heading,
      'speed': _speedKmH,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF02040A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('CAPTAIN TERMINAL', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.white70), onPressed: () => Provider.of<AuthService>(context, listen: false).logout()),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment.topRight, radius: 1.5, colors: [Color(0xFF0F172A), Color(0xFF02040A)]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildDriverHero(user),
                const SizedBox(height: 32),
                _buildTelemetryCard(),
                const SizedBox(height: 32),
                _buildBusSelector(),
                const SizedBox(height: 20),
                _buildStartButton(),
                const SizedBox(height: 24),
                _buildSOSButton(user),
                const SizedBox(height: 32),
                _buildTripStats(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriverHero(User? user) {
    return Row(
      children: [
        Container(
          height: 70, width: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF1A4CFF), Color(0xFF6366F1)]),
            border: Border.all(color: Colors.white12, width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFF1A4CFF).withValues(alpha: 0.3), blurRadius: 20)],
          ),
          child: const Center(child: Text('👨‍✈️', style: TextStyle(fontSize: 32))),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14)),
            Text(user?.username.toUpperCase() ?? 'CAPTAIN', style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ],
        ),
      ],
    ).animate().fadeIn().slideX();
  }

  Widget _buildTelemetryCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CURRENT SPEED', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_speedKmH.toStringAsFixed(1), style: GoogleFonts.outfit(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, left: 4),
                        child: Text('KM/H', style: GoogleFonts.outfit(color: const Color(0xFF1A4CFF), fontSize: 14, fontWeight: FontWeight.bold)),
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
                final double h = (e.value * 1.5).clamp(4.0, 50.0);
                return Container(
                  width: 14,
                  height: h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [_isOnline ? const Color(0xFF1A4CFF) : Colors.white12, _isOnline ? const Color(0xFF6366F1).withValues(alpha: 0.5) : Colors.white10],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ).animate(target: _isOnline ? 1 : 0).shimmer();
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
          icon: const Icon(Icons.refresh_rounded, color: Colors.white24, size: 16),
          onPressed: () => Provider.of<SocketService>(context, listen: false).reconnect(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (_isOnline ? Colors.greenAccent : Colors.white10).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (_isOnline ? Colors.greenAccent : Colors.white24).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              if (_isOnline) Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
              ).animate(onPlay: (c) => c.repeat()).scale(duration: 1.seconds, begin: const Offset(1,1), end: const Offset(1.5,1.5)).fadeOut(),
              const SizedBox(width: 8),
              Text(_isOnline ? 'LIVE' : 'IDLE', style: GoogleFonts.outfit(color: _isOnline ? Colors.greenAccent : Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBusSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: const Color(0xFF0F172A),
          value: _selectedBusId,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38),
          hint: Text('Select Assigned Bus', style: GoogleFonts.outfit(color: Colors.white24)),
          items: _buses.map((bus) => DropdownMenuItem<String>(
            value: bus['_id'],
            child: Text(bus['routeName'] ?? 'Unknown Route', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
          )).toList(),
          onChanged: _isOnline ? null : (v) => setState(() => _selectedBusId = v),
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _toggleOnlineStatus,
      child: AnimatedContainer(
        duration: 400.ms,
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _isOnline ? [Colors.redAccent, const Color(0xFFFF5252)] : [const Color(0xFF1A4CFF), const Color(0xFF6366F1)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: (_isOnline ? Colors.redAccent : const Color(0xFF1A4CFF)).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Center(
          child: Text(
            _isOnline ? 'END CURRENT TRIP' : 'BEGIN TRACKING SESSION',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }

  Future<void> _triggerSOS(User? user) async {
    if (_isSosActive) return;
    setState(() => _isSosActive = true);
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      Position? position;
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      }

      final socketService = Provider.of<SocketService>(context, listen: false);
      
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
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CRITICAL: SOS DISPATCHED TO AUTHORITY!', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 2),
        ),
        child: _isSosActive 
            ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'HOLD TO TRIGGER SOS',
                    style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5),
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
        Text('DAILY OVERVIEW', style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildSmallStat('DISTANCE', '24.8', 'KM'),
            const SizedBox(width: 16),
            _buildSmallStat('STOPS', '12', 'PTS'),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildSmallStat(String label, String value, String unit) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(unit, style: GoogleFonts.outfit(color: const Color(0xFF1A4CFF), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

