import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../components/bus_map.dart';
import 'profile_settings_screen.dart';
import '../theme/app_theme.dart';
import '../utils/timetable_resolver.dart';
import '../components/stop_feedback_sheet.dart';
import '../components/update_dialog.dart';

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
  String _selectedTripType = (DateTime.now().hour < 12) ? 'pickup' : 'dropoff'; // 'pickup' (Stops -> Campus) or 'dropoff' (Campus -> Stops)
  String _currentOccupancy = 'Low'; // 'Low', 'Medium', 'Full'
  bool _isSosActive = false;
  Timer? _heartbeatTimer;
  Timer? _tripDurationTimer;
  int _tripDurationSeconds = 0;
  final Set<String> _reachedStopNames = <String>{};
  final ValueNotifier<DateTime?> _lastEmitTime = ValueNotifier<DateTime?>(null);

  // Speed smoothing constants
  static const double _emaAlpha = 0.3; // Exponential Moving Average factor
  static const double _speedThresholdMps = 0.5; // min GPS speed to trust (0.5 m/s ≈ 1.8 km/h)

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchMyBus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSocketListeners();
      checkForAppUpdate(context);
    });
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
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data['message'],
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
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
    _tripDurationTimer?.cancel();
    _lastEmitTime.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _showServiceDisabledAlert();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) _showPermissionAlert();
    }
  }

  void _showServiceDisabledAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('GPS DISABLED', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(
          'Location services are disabled on your device. Please turn on GPS to start tracking.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
              _checkPermissions(); // Re-check after returning
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('ENABLE GPS', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPermissionAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('GPS REQUIRED', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(
          'This app requires GPS to track the bus location in real-time. Please enable location permissions in settings.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.plusJakartaSans(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Geolocator.openAppSettings(),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('SETTINGS', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchMyBus() async {
    try {
      final response = await _apiService.get('drivers/my-bus');
      if (!mounted) return;
      setState(() {
        _selectedBusId = response['_id'];
        _fetchRouteDetails(response['routeId']);
      });
      _fetchAllBuses();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error fetching my bus: $e');
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
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _showServiceDisabledAlert();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showPermissionAlert();
      }
      return;
    }

    HapticFeedback.heavyImpact();

    setState(() {
      _isOnline = true;
      _tripDurationSeconds = 0;
      _sessionDistanceKm = 0.0;
      _sessionStops = 0;
      _reachedStopNames.clear();
    });

    _tripDurationTimer?.cancel();
    _tripDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isOnline) {
        setState(() => _tripDurationSeconds++);
      }
    });

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 800),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'SISTecChalo Live GPS',
          notificationText: 'Broadcasting live campus shuttle location',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        if (!mounted) return;
        setState(() {
          // Session distance accumulation
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

          // Speed calculation with multi-source fallback
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
            if (elapsedSec > 0.5) {
              rawSpeedKmH = (distMeters / elapsedSec) * 3.6;
            }
          }

          // Clamp to realistic bus speeds (0 to 120 km/h)
          rawSpeedKmH = rawSpeedKmH.clamp(0.0, 120.0);

          // Exponential Moving Average smoothing
          _smoothedSpeedKmH = (_emaAlpha * rawSpeedKmH) + ((1 - _emaAlpha) * _smoothedSpeedKmH);
          _speedKmH = _smoothedSpeedKmH;

          // Update circular speed history buffer
          _recentSpeeds[_recentSpeedIndex % 15] = _speedKmH;
          _recentSpeedIndex++;

          _prevPosition     = position;
          _prevPositionTime = DateTime.now();
          _currentPosition  = position;

          // Automatic Stop Geofence Arrival Check (Adaptive speed-aware radius)
          _checkAutomaticStopArrival(position);
        });

        // Emit every GPS update for smooth real-time tracking
        _emitLocation();
      },
      onError: (dynamic err) {
        debugPrint('⚠️ GPS stream error: $err');
      },
    );

    // Immediate initial GPS lock on trip start
    Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    ).then((pos) {
      if (mounted && _isOnline && _currentPosition == null) {
        setState(() {
          _currentPosition = pos;
          _prevPosition = pos;
          _prevPositionTime = DateTime.now();
          _checkAutomaticStopArrival(pos);
        });
        _emitLocation();
      }
    }).catchError((e) {
      debugPrint('Initial GPS fetch note: $e');
    });

    // Heartbeat: keeps users' maps alive even if GPS doesn't fire
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isOnline && _currentPosition != null) _emitLocation();
    });
  }

  void _checkAutomaticStopArrival(Position pos) {
    if (_selectedRoute == null || _selectedRoute!.stops.isEmpty) return;

    final isDropoff = _selectedTripType == 'dropoff';
    final List<Map<String, dynamic>> displayedStops = isDropoff 
        ? _selectedRoute!.stops.reversed.toList() 
        : _selectedRoute!.stops;

    // Dynamic arrival geofence radius based on live speed
    // Higher speed on highways has larger lookahead; city crawl has tighter precision
    final double arrivalRadius = _speedKmH > 35.0 ? 220.0 : (_speedKmH > 15.0 ? 160.0 : 130.0);

    for (int i = 0; i < displayedStops.length; i++) {
      final stop = displayedStops[i];
      final stopName = stop['name']?.toString().trim() ?? '';
      if (stopName.isEmpty || _reachedStopNames.contains(stopName)) continue;
      
      final lat = (stop['lat'] ?? 0.0).toDouble();
      final lng = (stop['lng'] ?? 0.0).toDouble();
      if (lat == 0.0 || lng == 0.0) continue;

      final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
      
      // Check arrival condition: within dynamic radius OR dwelling near stop (<180m and speed < 12 km/h)
      if (dist <= arrivalRadius || (dist <= 180.0 && _speedKmH < 12.0)) {
        // Auto-mark this stop and all preceding unreached stops along the trip sequence
        for (int j = 0; j <= i; j++) {
          final priorName = displayedStops[j]['name']?.toString().trim() ?? '';
          if (priorName.isNotEmpty) {
            _reachedStopNames.add(priorName);
          }
        }

        _sessionStops = _reachedStopNames.length;
        HapticFeedback.heavyImpact();
        debugPrint('🎯 Auto Checked Stop: $stopName (distance: ${dist.toStringAsFixed(1)}m, speed: ${_speedKmH.toStringAsFixed(1)} km/h)');

        // Show non-intrusive floating HUD feedback on the cockpit
        if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
              duration: const Duration(seconds: 4),
              content: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accentGreen, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentGreen.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'AUTO STOP ARRIVAL DETECTED',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.accentGreen,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Arrived at $stopName • Checked in',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

        // Immediately update telemetry so students & manager get live stop status
        _emitLocation();
        break;
      }
    }
  }

  void _stopTracking() {
    HapticFeedback.mediumImpact();
    _positionStream?.cancel();
    _heartbeatTimer?.cancel();
    _tripDurationTimer?.cancel();

    // Notify server the trip has ended so it logs the end time
    if (_selectedBusId != null) {
      try {
        final socketService = Provider.of<SocketService>(context, listen: false);
        socketService.emitTripEnd(_selectedBusId!);
      } catch (e) {
        debugPrint('⚠️ Could not emit tripEnd: $e');
      }
    }

    setState(() {
      _isOnline         = false;
      _speedKmH            = 0;
      _smoothedSpeedKmH    = 0;
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
    final assignedBusNo = TimetableResolver.resolveAssignedBusNumber(
      routeName: _selectedRoute?.name ?? selectedBus?['routeName'],
    );
    
    final nextStop = _getNextStop();
    final nextStopName = nextStop?['name']?.toString();
    final distToNext = _getDistanceToNextStop();

    final effectiveRouteId = _selectedRoute?.id ?? (selectedBus != null ? selectedBus['routeId']?.toString() : null);
    final effectiveRouteName = _selectedRoute?.name ?? selectedBus?['routeName'] ?? 'SISTec Route';

    socketService.emitLocationUpdate({
      'driverId': user.id,
      'busId': _selectedBusId,
      'id': _selectedBusId,
      'busNumber': assignedBusNo,
      'routeId': effectiveRouteId,
      'routeName': effectiveRouteName,
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'currentLat': _currentPosition!.latitude,
      'currentLng': _currentPosition!.longitude,
      'heading': _currentPosition!.heading >= 0 ? _currentPosition!.heading : 0.0,
      'speed': double.parse(_speedKmH.toStringAsFixed(1)),
      'status': 'On-time',
      'occupancy': _currentOccupancy,
      'tripType': _selectedTripType,
      'reachedStops': _reachedStopNames.toList(),
      'completedStops': _reachedStopNames.length,
      'nextStop': nextStopName,
      'distanceToNextStopMeters': distToNext?.round(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Map<String, dynamic>? _getNextStop() {
    if (_selectedRoute == null || _selectedRoute!.stops.isEmpty) return null;
    final isDropoff = _selectedTripType == 'dropoff';
    final List<Map<String, dynamic>> stops = isDropoff 
        ? _selectedRoute!.stops.reversed.toList() 
        : _selectedRoute!.stops;
    
    for (final stop in stops) {
      final name = stop['name']?.toString().trim() ?? '';
      if (name.isNotEmpty && !_reachedStopNames.contains(name)) {
        return stop;
      }
    }
    return null;
  }

  double? _getDistanceToNextStop() {
    final nextStop = _getNextStop();
    if (nextStop == null || _currentPosition == null) return null;
    final lat = (nextStop['lat'] ?? 0.0).toDouble();
    final lng = (nextStop['lng'] ?? 0.0).toDouble();
    if (lat == 0.0 || lng == 0.0) return null;
    return Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
  }

  Future<void> _launchNavigationToTarget({double? targetLat, double? targetLng, String? destinationName}) async {
    double lat = targetLat ?? 23.1765; // fallback SISTec Ratibad
    double lng = targetLng ?? 77.3485;

    final nextStop = _getNextStop();
    if (targetLat == null && nextStop != null) {
      final sLat = (nextStop['lat'] ?? 0.0).toDouble();
      final sLng = (nextStop['lng'] ?? 0.0).toDouble();
      if (sLat != 0.0 && sLng != 0.0) {
        lat = sLat;
        lng = sLng;
      }
    }

    final googleMapsAppUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

    try {
      if (await canLaunchUrl(googleMapsAppUrl)) {
        await launchUrl(googleMapsAppUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open map navigation application')),
          );
        }
      }
    } catch (e) {
      debugPrint('Navigation error: $e');
    }
  }

  String _formatDuration(int totalSecs) {
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    final socketService = Provider.of<SocketService>(context);

    return PopScope(
      canPop: !_isOnline,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isOnline) {
          _showExitWarningDialog(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: ValueListenableBuilder<bool>(
          valueListenable: socketService.connectionStatus,
          builder: (context, isConnected, child) {
          return Stack(
            children: [
              // Background Map — centered on driver GPS
              _selectedRoute != null
                  ? BusMap(
                      buses: _buses.map((b) {
                        if (b['_id'] == _selectedBusId && _currentPosition != null) {
                          return Bus(
                            id: b['_id'],
                            busNumber: TimetableResolver.resolveAssignedBusNumber(routeName: _selectedRoute?.name),
                            routeId: b['routeId'] ?? '',
                            routeName: b['routeName'] ?? 'My Route',
                            routeColor: b['color'] ?? '#2D5BFF',
                            currentLat: _currentPosition!.latitude,
                            currentLng: _currentPosition!.longitude,
                            heading: _currentPosition!.heading,
                            speed: _speedKmH,
                            status: _isOnline ? 'Active' : 'Offline',
                            occupancy: _currentOccupancy,
                            tripType: _selectedTripType,
                            lastUpdated: DateTime.now(),
                          );
                        }
                        return Bus.fromJson(b);
                      }).toList(),
                      selectedRoute: _selectedRoute,
                      centerOnBusId: _selectedBusId,
                      initialDriveMode: _isOnline,
                      showMyLocation: false,
                      showMapControls: false,
                      showFocusedBusCard: false,
                      initialMapType: MapType.normal,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        color: AppColors.bg,
                      ),
                    ),

              // Top Floating Header Bar (Always present with sleek glass design)
              Positioned(
                top: 0,
                left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.bg.withValues(alpha: 0.95), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (Navigator.canPop(context)) ...[
                        _buildHeaderIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          tooltip: 'Back',
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'DRIVER COCKPIT',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.primaryLight,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_isOnline) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentGreen.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      'LIVE',
                                      style: GoogleFonts.plusJakartaSans(color: AppColors.accentGreen, fontSize: 7, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                _buildSignalStrength(isConnected),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isConnected ? (_isOnline ? 'GPS Active' : 'Ready') : 'Connecting...',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: isConnected ? AppColors.accentGreen : AppColors.danger,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
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
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeaderIconButton(
                            icon: Icons.navigation_rounded,
                            color: Colors.cyanAccent,
                            tooltip: 'Turn-by-turn Navigation',
                            onTap: () => _launchNavigationToTarget(),
                          ),
                          const SizedBox(width: 4),
                          _buildHeaderIconButton(
                            icon: Icons.qr_code_scanner_rounded,
                            color: AppColors.accentGreen,
                            tooltip: 'Boarding Pass Scan',
                            onTap: () => _showBoardingScanDialog(context),
                          ),
                          const SizedBox(width: 4),
                          _buildHeaderIconButton(
                            icon: Icons.warning_amber_rounded,
                            color: AppColors.accent,
                            tooltip: 'Report Delay',
                            onTap: () => _showDelayAlertDialog(context),
                          ),
                          const SizedBox(width: 4),
                          _buildHeaderIconButton(
                            icon: Icons.local_gas_station_rounded,
                            color: Colors.amberAccent,
                            tooltip: 'Log Fuel',
                            onTap: () => _showFuelRefillDialog(context),
                          ),
                          const SizedBox(width: 4),
                          _buildHeaderIconButton(
                            icon: Icons.person_outline_rounded,
                            color: Colors.white70,
                            tooltip: 'Profile',
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));
                            },
                          ),
                          const SizedBox(width: 4),
                          _buildHeaderIconButton(
                            icon: Icons.logout_rounded,
                            color: AppColors.danger,
                            tooltip: 'Logout',
                            onTap: () => _showLogoutDialog(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Main Draggable Bottom Sheet
              DraggableScrollableSheet(
                initialChildSize: 0.68,
                minChildSize: 0.38,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.98),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 36, spreadRadius: 4),
                      ],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        children: [
                          // Handle
                          Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 24, top: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          
                          _buildDriverHero(user),
                          const SizedBox(height: 18),
                          _buildTrackerCard(),
                          const SizedBox(height: 16),
                          _buildNextStopCard(),
                          const SizedBox(height: 16),
                          _buildBusSelector(),
                          const SizedBox(height: 14),
                          _buildTripDirectionSelector(),
                          const SizedBox(height: 14),
                          _buildOccupancySelector(),
                          const SizedBox(height: 18),
                          _buildStartButton(),
                          const SizedBox(height: 16),
                          _buildSOSButton(user),
                          const SizedBox(height: 24),
                          _buildTripStats(),
                          const SizedBox(height: 24),
                          _buildDriverStopsTimeline(),
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
    ),
  );
}

  Widget _buildDriverHero(User? user) {
    final assignedBus = TimetableResolver.resolveAssignedBusNumber(
      routeName: _selectedRoute?.name,
    );
    final busDetails = TimetableResolver.resolveBusDetails(
      routeName: _selectedRoute?.name,
      currentHour: DateTime.now().hour,
    );
    final shiftTag = TimetableResolver.resolveShiftLabel(
      routeName: _selectedRoute?.name,
      currentHour: DateTime.now().hour,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            height: 54, width: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF6366F1)]),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(child: Icon(Icons.directions_bus_rounded, color: Colors.white, size: 28)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      assignedBus,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.primaryLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        shiftTag,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white70,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (busDetails?.vehicleNo != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          busDetails!.vehicleNo,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white60,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  user?.username.toUpperCase() ?? 'CAPTAIN DRIVER',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  _selectedRoute?.name ?? 'SISTec Transit Route',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _speedColor(double speed) {
    if (speed < 20) return AppColors.primaryLight;
    if (speed < 45) return AppColors.accentGreen;
    if (speed < 65) return AppColors.accent;
    return AppColors.danger;
  }

  String _speedCategory(double speed) {
    if (!_isOnline) return 'OFFLINE';
    if (speed < 5) return 'STATIONARY';
    if (speed < 25) return 'LOW SPEED';
    if (speed < 50) return 'NORMAL';
    if (speed < 70) return 'CRUISING';
    return 'HIGH SPEED';
  }

  Widget _buildTrackerCard() {
    final sColor = _speedColor(_speedKmH);
    final sortedSpeeds = List<double>.from(_recentSpeeds)..sort();
    final maxRecentSpeed = sortedSpeeds.isNotEmpty ? sortedSpeeds.last : 1.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _isOnline ? sColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
        boxShadow: _isOnline ? [BoxShadow(color: sColor.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 2)] : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TELEMETRY SPEEDOMETER', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: GoogleFonts.plusJakartaSans(
                              color: _isOnline ? Colors.white : Colors.white38,
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -2,
                              height: 1.0,
                            ),
                            child: Text(_speedKmH.toStringAsFixed(1)),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6, left: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('KM/H', style: GoogleFonts.plusJakartaSans(color: sColor, fontSize: 10, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: sColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: sColor.withValues(alpha: 0.35)),
                                  ),
                                  child: Text(
                                    _speedCategory(_speedKmH),
                                    style: GoogleFonts.plusJakartaSans(color: sColor, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_currentPosition != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.gps_fixed_rounded, color: AppColors.textMuted, size: 11),
                          const SizedBox(width: 5),
                          Text(
                            'GPS Accuracy: ±${_currentPosition!.accuracy.toStringAsFixed(0)}m',
                            style: GoogleFonts.plusJakartaSans(
                              color: _currentPosition!.accuracy < 10 ? AppColors.accentGreen : AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _buildLiveIndicator(),
            ],
          ),
          const SizedBox(height: 16),
          // Speed history bar chart
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SPEED HISTOGRAM', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  Text('${maxRecentSpeed.toStringAsFixed(0)} KM/H PEAK', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 8.5, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _recentSpeeds.map((speed) {
                    final maxRef = maxRecentSpeed > 0 ? maxRecentSpeed : 1.0;
                    final double h = ((speed / maxRef) * 40).clamp(3.0, 40.0);
                    final barColor = _speedColor(speed);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 12,
                      height: h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: _isOnline
                            ? [barColor.withValues(alpha: 0.3), barColor]
                            : [Colors.white10, Colors.white10],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (_isOnline ? AppColors.accentGreen : Colors.white10).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (_isOnline ? AppColors.accentGreen : Colors.white24).withValues(alpha: 0.25)),
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
                      color: AppColors.accentGreen, 
                      size: 14,
                      key: ValueKey(time?.millisecondsSinceEpoch ?? 0),
                    ).animate(key: ValueKey(time?.millisecondsSinceEpoch ?? 0))
                     .scale(begin: const Offset(1,1), end: const Offset(1.4,1.4))
                     .fadeOut(duration: 400.ms);
                  },
                ),
                const SizedBox(width: 6),
                Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle),
                ).animate(onPlay: (c) => c.repeat()).scale(duration: 1.seconds, begin: const Offset(1,1), end: const Offset(1.5,1.5)).fadeOut(),
                const SizedBox(width: 6),
              ],
              Text(
                _isOnline ? 'LIVE BROADCAST' : 'OFFLINE',
                style: GoogleFonts.plusJakartaSans(
                  color: _isOnline ? AppColors.accentGreen : AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNextStopCard() {
    final nextStop = _getNextStop();
    if (nextStop == null) return const SizedBox.shrink();

    final stopName = nextStop['name']?.toString() ?? 'Next Stop';
    final dist = _getDistanceToNextStop();
    final distText = dist != null 
        ? (dist < 1000 ? '${dist.toStringAsFixed(0)} m away' : '${(dist / 1000).toStringAsFixed(1)} km away')
        : 'Approaching next';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.near_me_rounded, color: AppColors.primaryLight, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UPCOMING NEXT STOP',
                  style: GoogleFonts.plusJakartaSans(color: AppColors.primaryLight, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                ),
                Text(
                  stopName,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  distText,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final lat = (nextStop['lat'] ?? 0.0).toDouble();
              final lng = (nextStop['lng'] ?? 0.0).toDouble();
              _launchNavigationToTarget(targetLat: lat, targetLng: lng, destinationName: stopName);
            },
            icon: const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
            label: Text('NAV', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusSelector() {
    if (_isOnline) return const SizedBox.shrink(); 
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: AppColors.surface,
          value: _selectedBusId,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primaryLight),
          hint: Text('SELECT ASSIGNED ROUTE & BUS', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
          items: _buses.map((bus) {
            final assignedNo = TimetableResolver.resolveAssignedBusNumber(routeName: bus['routeName']);
            return DropdownMenuItem<String>(
              value: bus['_id'],
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      assignedNo,
                      style: GoogleFonts.plusJakartaSans(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bus['routeName'] ?? 'Unknown Route',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            setState(() => _selectedBusId = v);
            final bus = _buses.firstWhere((b) => b['_id'] == v, orElse: () => null);
            if (bus != null) _fetchRouteDetails(bus['routeId']);
          },
        ),
      ),
    );
  }

  Widget _buildTripDirectionSelector() {
    final isPickup = _selectedTripType == 'pickup';
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Morning Shift
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_selectedTripType != 'pickup') {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedTripType = 'pickup';
                    _reachedStopNames.clear();
                    _sessionStops = 0;
                  });
                  if (_isOnline && _currentPosition != null) {
                    _checkAutomaticStopArrival(_currentPosition!);
                    _emitLocation();
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: isPickup ? AppColors.primary.withValues(alpha: 0.20) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isPickup ? Border.all(color: AppColors.primary.withValues(alpha: 0.45)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wb_sunny_rounded, color: isPickup ? AppColors.primaryLight : AppColors.textMuted, size: 15),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'MORNING PICKUP',
                          style: GoogleFonts.plusJakartaSans(
                            color: isPickup ? Colors.white : AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          'Stops ➔ Campus',
                          style: GoogleFonts.plusJakartaSans(
                            color: isPickup ? AppColors.primaryLight : AppColors.textDisabled,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 2nd Shift / Return
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_selectedTripType != 'dropoff') {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedTripType = 'dropoff';
                    _reachedStopNames.clear();
                    _sessionStops = 0;
                  });
                  if (_isOnline && _currentPosition != null) {
                    _checkAutomaticStopArrival(_currentPosition!);
                    _emitLocation();
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: !isPickup ? AppColors.accent.withValues(alpha: 0.20) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: !isPickup ? Border.all(color: AppColors.accent.withValues(alpha: 0.45)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.nights_stay_rounded, color: !isPickup ? AppColors.accent : AppColors.textMuted, size: 15),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '2ND SHIFT RETURN',
                          style: GoogleFonts.plusJakartaSans(
                            color: !isPickup ? Colors.white : AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          'Campus ➔ Stops',
                          style: GoogleFonts.plusJakartaSans(
                            color: !isPickup ? AppColors.accent : AppColors.textDisabled,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOccupancySelector() {
    final options = [
      {'label': 'LOW (<50%)', 'val': 'Low', 'color': AppColors.accentGreen},
      {'label': 'MED (50-80%)', 'val': 'Medium', 'color': AppColors.accent},
      {'label': 'FULL (>80%)', 'val': 'Full', 'color': AppColors.danger},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SEAT OCCUPANCY STATUS', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              Text('$_currentOccupancy Load', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: options.map((opt) {
              final val = opt['val'] as String;
              final isSel = _currentOccupancy == val;
              final color = opt['color'] as Color;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _currentOccupancy = val);
                    if (_isOnline) _emitLocation();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? color.withValues(alpha: 0.2) : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSel ? color : Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Center(
                      child: Text(
                        opt['label'] as String,
                        style: GoogleFonts.plusJakartaSans(
                          color: isSel ? Colors.white : AppColors.textMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _toggleOnlineStatus,
      child: AnimatedContainer(
        duration: 300.ms,
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isOnline 
              ? [AppColors.danger, const Color(0xFFDC2626)] 
              : [AppColors.primary, const Color(0xFF4F46E5)]
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (_isOnline ? AppColors.danger : AppColors.primary).withValues(alpha: 0.35), 
              blurRadius: 18, 
              offset: const Offset(0, 6)
            )
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_isOnline ? Icons.stop_circle_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 10),
              Text(
                _isOnline ? 'FINISH LIVE TRACKING TRIP' : 'START LIVE GPS BROADCAST',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
      duration: 3.seconds,
      color: Colors.white.withValues(alpha: 0.1),
    );
  }

  Future<void> _triggerSOS(User? user) async {
    if (_isSosActive) return;
    setState(() => _isSosActive = true);

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
          content: Text('EMERGENCY SOS ALERT TRANSMITTED!', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3), width: 1.5),
        ),
        child: _isSosActive 
            ? const Center(child: CircularProgressIndicator(color: AppColors.danger))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_rounded, color: AppColors.danger, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'HOLD 2 SECONDS FOR EMERGENCY SOS',
                    style: GoogleFonts.plusJakartaSans(color: AppColors.danger, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.0),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTripStats() {
    final int totalStops = _selectedRoute?.stops.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LIVE TRIP TELEMETRY', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildSmallStat('DISTANCE', _sessionDistanceKm.toStringAsFixed(1), 'KM', AppColors.primary),
            const SizedBox(width: 8),
            _buildSmallStat('STOPS', '$_sessionStops/$totalStops', 'DONE', AppColors.accentGreen),
            const SizedBox(width: 8),
            _buildSmallStat('DURATION', _formatDuration(_tripDurationSeconds), '', AppColors.accent),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallStat(String label, String value, String unit, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Text(unit, style: GoogleFonts.plusJakartaSans(color: accent, fontSize: 9, fontWeight: FontWeight.w900)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverStopsTimeline() {
    if (_selectedRoute == null || _selectedRoute!.stops.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDropoff = _selectedTripType == 'dropoff';
    final List<Map<String, dynamic>> displayedStops = isDropoff 
        ? _selectedRoute!.stops.reversed.toList() 
        : _selectedRoute!.stops;

    final int nextTargetIdx = displayedStops.indexWhere((s) => !_reachedStopNames.contains(s['name']?.toString().trim() ?? ''));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(isDropoff ? Icons.departure_board_rounded : Icons.route_rounded, color: isDropoff ? AppColors.accent : AppColors.primaryLight, size: 15),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'AUTO-GEOFENCED STOPS CHECKLIST',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textMuted,
                        fontSize: 9.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_sessionStops/${displayedStops.length} REACHED',
                style: GoogleFonts.plusJakartaSans(
                  color: isDropoff ? AppColors.accent : AppColors.accentGreen,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayedStops.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final stop = displayedStops[idx];
            final stopName = stop['name']?.toString().trim() ?? 'Stop ${idx + 1}';
            final isReached = _reachedStopNames.contains(stopName);
            final isTarget = idx == nextTargetIdx;
            final isFirst = idx == 0;
            final isLast = idx == displayedStops.length - 1;

            final sLat = (stop['lat'] ?? 0.0).toDouble();
            final sLng = (stop['lng'] ?? 0.0).toDouble();
            double? distMeters;
            if (_currentPosition != null && sLat != 0.0 && sLng != 0.0) {
              distMeters = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, sLat, sLng);
            }

            final distText = distMeters != null
                ? (distMeters < 1000 ? '${distMeters.toInt()}m' : '${(distMeters / 1000).toStringAsFixed(1)}km')
                : null;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isReached 
                    ? AppColors.accentGreen.withValues(alpha: 0.08) 
                    : (isTarget ? AppColors.primary.withValues(alpha: 0.12) : AppColors.bgSecondary),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isReached 
                      ? AppColors.accentGreen.withValues(alpha: 0.35) 
                      : (isTarget ? AppColors.primaryLight.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05)),
                  width: isTarget ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isReached) {
                          _reachedStopNames.remove(stopName);
                        } else {
                          _reachedStopNames.add(stopName);
                        }
                        _sessionStops = _reachedStopNames.length;
                      });
                      if (_isOnline) _emitLocation();
                    },
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: isReached ? AppColors.accentGreen : (isTarget ? AppColors.primary : AppColors.surface),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isReached ? AppColors.accentGreen : (isTarget ? AppColors.primaryLight : Colors.white24),
                          width: 2,
                        ),
                      ),
                      child: isReached 
                          ? const Icon(Icons.check_rounded, color: Colors.black, size: 16)
                          : Center(
                              child: isTarget
                                  ? const Icon(Icons.near_me_rounded, color: Colors.white, size: 14)
                                  : Text(
                                      '${idx + 1}',
                                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stopName,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: (isReached || isTarget) ? FontWeight.w800 : FontWeight.w600,
                                  decoration: isReached ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                            if (isTarget && !isReached) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  'TARGET',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.primaryLight,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isFirst 
                                    ? (isDropoff ? 'Campus Origin Departure' : 'First Pickup Origin')
                                    : (isLast 
                                        ? (isDropoff ? 'Final City Drop-off Terminal' : 'Final Destination: SISTec Campus')
                                        : 'Transit Stop ${idx + 1}'),
                                style: GoogleFonts.plusJakartaSans(
                                  color: isReached ? AppColors.accentGreen : AppColors.textMuted,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (distText != null && !isReached) ...[
                              Text(' • ', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9)),
                              Text(
                                distText,
                                style: GoogleFonts.plusJakartaSans(
                                  color: isTarget ? AppColors.accentGreen : Colors.white60,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Calibrate Stop GPS button
                      IconButton(
                        icon: const Icon(Icons.gps_fixed_rounded, color: AppColors.primaryLight, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: 'Calibrate Stop GPS',
                        onPressed: () {
                          if (_selectedRoute != null) {
                            StopFeedbackSheet.show(
                              context,
                              routeId: _selectedRoute!.id,
                              routeName: _selectedRoute!.name,
                              stopName: stopName,
                              currentLat: sLat,
                              currentLng: sLng,
                            );
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            if (isReached) {
                              _reachedStopNames.remove(stopName);
                            } else {
                              _reachedStopNames.add(stopName);
                            }
                            _sessionStops = _reachedStopNames.length;
                          });
                          if (_isOnline) _emitLocation();
                        },
                        child: Text(
                          isReached ? 'DONE ✓' : (isTarget ? 'ARRIVE' : 'CHECK IN'),
                          style: GoogleFonts.plusJakartaSans(
                            color: isReached ? AppColors.accentGreen : (isTarget ? AppColors.primaryLight : Colors.white60),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
        ),
      ),
    );
  }

  Widget _buildSignalStrength(bool isConnected) {
    return Row(
      children: List.generate(4, (index) {
        final active = isConnected && index < 3;
        return Container(
          width: 3,
          height: 4.0 + (index * 3),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active ? AppColors.accentGreen : Colors.white12,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'LOGOUT DRIVER',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          _isOnline
              ? 'Tracking is currently ACTIVE. Logging out will stop live broadcast and end your shift. Do you wish to continue?'
              : 'Are you sure you want to end your driver session and log out?',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_isOnline) {
                _stopTracking();
              }
              Provider.of<AuthService>(context, listen: false).logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: Text('LOG OUT', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showExitWarningDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warning_rounded, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'LIVE TRACKING ACTIVE',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Your bus is currently broadcasting GPS to waiting students. Do you want to stop tracking and leave?',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('STAY IN COCKPIT', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopTracking();
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: Text('STOP & EXIT', style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showDelayAlertDialog(BuildContext context) {
    int selectedMins = 10;
    String selectedReason = 'Traffic Congestion';

    final delayOptions = [
      {'mins': 5, 'reason': 'Heavy Signal Delay'},
      {'mins': 10, 'reason': 'Traffic Congestion'},
      {'mins': 15, 'reason': 'Severe Road Jam'},
      {'mins': 20, 'reason': 'Puncture / Mechanical Issue'},
      {'mins': 15, 'reason': 'Inclement Weather / Rain'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            boxShadow: AppShadows.card,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'BROADCAST ROUTE DELAY',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.0),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Notify all waiting students on this route with an instant delay alert.',
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 16),
              ...delayOptions.map((opt) {
                final mins = opt['mins'] as int;
                final reason = opt['reason'] as String;
                final isSel = selectedMins == mins && selectedReason == reason;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setModalState(() {
                      selectedMins = mins;
                      selectedReason = reason;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.accent.withValues(alpha: 0.15) : AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSel ? AppColors.accent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          reason,
                          style: GoogleFonts.plusJakartaSans(
                            color: isSel ? Colors.white : AppColors.textSecondary,
                            fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.accent : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+$mins MINS',
                            style: GoogleFonts.plusJakartaSans(
                              color: isSel ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.w900,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    try {
                      final routeName = _selectedRoute?.name ?? 'SISTec Route';
                      await _apiService.post('notifications', {
                        'message': '⚠️ Delay Alert: Shuttle on $routeName is delayed by ~$selectedMins mins due to $selectedReason.',
                        'routeId': _selectedRoute?.id,
                        'type': 'important',
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.surface,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 18),
                                const SizedBox(width: 10),
                                Text('Delay alert broadcasted to students!', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      debugPrint('Error broadcasting delay: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'BROADCAST (+$selectedMins MINS)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.8),
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

  void _showFuelRefillDialog(BuildContext context) {
    final odoController = TextEditingController();
    final litersController = TextEditingController();
    final costController = TextEditingController();
    final stationController = TextEditingController(text: 'Indian Oil');
    bool isSubmitting = false;

    final selectedBus = _buses.firstWhere((b) => b['_id'] == _selectedBusId, orElse: () => null);
    final assignedBusNo = TimetableResolver.resolveAssignedBusNumber(
      routeName: _selectedRoute?.name ?? selectedBus?['routeName'],
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
              boxShadow: AppShadows.card,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.local_gas_station_rounded, color: Colors.amberAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'LOG FUEL REFILL ($assignedBusNo)', 
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.0),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: odoController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Current Odometer (km)',
                      labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12),
                      prefixIcon: const Icon(Icons.speed_rounded, color: Colors.amberAccent, size: 18),
                      filled: true,
                      fillColor: AppColors.bgSecondary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: litersController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Fuel (Liters)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12),
                            prefixIcon: const Icon(Icons.water_drop_rounded, color: Colors.cyanAccent, size: 18),
                            filled: true,
                            fillColor: AppColors.bgSecondary,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: costController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Cost (₹)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12),
                            prefixIcon: const Icon(Icons.currency_rupee_rounded, color: Colors.greenAccent, size: 18),
                            filled: true,
                            fillColor: AppColors.bgSecondary,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: stationController,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Fuel Station Name',
                      labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12),
                      prefixIcon: const Icon(Icons.storefront_rounded, color: Colors.white70, size: 18),
                      filled: true,
                      fillColor: AppColors.bgSecondary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : () async {
                        if (odoController.text.isEmpty || litersController.text.isEmpty || costController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fuel fields.')));
                          return;
                        }
                        setModalState(() => isSubmitting = true);
                        try {
                          await _apiService.post('driver/fuel-log', {
                            'busId': _selectedBusId ?? 'BUS_01',
                            'busNumber': assignedBusNo,
                            'odometerKm': double.parse(odoController.text),
                            'liters': double.parse(litersController.text),
                            'totalCost': double.parse(costController.text),
                            'fuelStation': stationController.text
                          });
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.surface,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                                ),
                                content: Row(
                                  children: [
                                    const Icon(Icons.local_gas_station_rounded, color: AppColors.accentGreen, size: 18),
                                    const SizedBox(width: 10),
                                    Text('Fuel refill logged successfully', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
                          }
                        } finally {
                          setModalState(() => isSubmitting = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: isSubmitting 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : Text('SUBMIT REFILL LOG', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black, letterSpacing: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBoardingScanDialog(BuildContext context) {
    final rollController = TextEditingController();
    bool isProcessing = false;

    final selectedBus = _buses.firstWhere((b) => b['_id'] == _selectedBusId, orElse: () => null);
    final assignedBusNo = TimetableResolver.resolveAssignedBusNumber(
      routeName: _selectedRoute?.name ?? selectedBus?['routeName'],
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
              boxShadow: AppShadows.card,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, color: AppColors.accentGreen, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'BOARDING PASS CHECK-IN', 
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.0),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Enter student roll number or scan student QR card to validate and log boarding.', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 16),

                  TextField(
                    controller: rollController,
                    autofocus: true,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'Student Roll No / ID (e.g. 0187CS211045)',
                      labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12),
                      prefixIcon: const Icon(Icons.badge_rounded, color: AppColors.accentGreen, size: 18),
                      filled: true,
                      fillColor: AppColors.bgSecondary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : () async {
                        final roll = rollController.text.trim();
                        if (roll.isEmpty) return;
                        setModalState(() => isProcessing = true);
                        HapticFeedback.mediumImpact();
                        try {
                          final res = await _apiService.post('driver/scan-pass', {
                            'qrData': roll,
                            'busId': _selectedBusId ?? 'BUS_01',
                            'busNumber': assignedBusNo,
                            'routeName': _selectedRoute?.name ?? 'SISTec Route'
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.surface,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: AppColors.accentGreen),
                                ),
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Valid: ${res['studentName'] ?? roll} — Boarding recorded!',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() => isProcessing = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Validation error: $e')));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : Text('VERIFY & LOG BOARDING', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
