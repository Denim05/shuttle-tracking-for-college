import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/bus_store.dart';
import '../components/bus_map.dart';
import '../models/route_model.dart';
import '../models/bus_model.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fleet_radar_screen.dart';
import 'schedule_screen.dart';
import 'complaint_screen.dart';
import 'profile_settings_screen.dart';
import '../main.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/timetable_resolver.dart';
import '../components/dashboard_back_scope.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/update_dialog.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final GlobalKey<BusMapState> _busMapKey = GlobalKey<BusMapState>();
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  final Set<String> _notifiedGeofenceStops = {};
  DateTime? _lastProximityAlertTime;
  
  List<RouteModel> _routes = [];
  bool _isLoading = true;
  RouteModel? _selectedRoute;
  Bus? _activeBus;
  String? _selectedShiftFilter;
  String _shiftTimelineDirection = (DateTime.now().hour < 12) ? 'pickup' : 'dropoff';
  int _currentIndex = 0;
  bool _showDebugOverlay = false;
  
  bool _isSosActive = false;

  bool _isDriveMode = false;
  int? _etaMinutes;          // ETA to user's assigned pickup stop
  bool _etaLoading = false;
  bool _delaySubscribed = false; // Whether user subscribed to delay alerts
  bool _isSwapBannerDismissed = false; // User dismissed active bus swap alert banner

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService().init();
    _fetchData();
    _initSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForAppUpdate(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sheetController.dispose();
    NotificationService().cancelLiveTrackingNotification();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<SocketService>(context, listen: false).checkAndReconnect();
      _fetchData();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _syncOngoingLockscreenNotification();
    }
  }

  void _syncOngoingLockscreenNotification() {
    if (!mounted) return;
    final busStore = Provider.of<BusStore>(context, listen: false);
    Bus? liveBus;
    for (final b in busStore.allBuses) {
      if (b.isBroadcastingLive && _selectedRoute != null && (b.routeId == _selectedRoute!.id || b.routeName.toLowerCase() == _selectedRoute!.name.toLowerCase())) {
        liveBus = b;
        break;
      }
    }

    if (liveBus != null) {
      final targetStop = liveBus.nextStop ?? (_selectedRoute?.stops.first['name']?.toString() ?? 'Next Stop');
      // Use road-distance-adjusted values for accurate notification
      final distM = liveBus.distanceToNextStopMeters ?? 650;
      final distStr = distM < 1000 ? '$distM m' : '${(distM / 1000).toStringAsFixed(1)} km';
      // Prefer server-computed ETA from driver broadcast (polyline-based)
      int etaMins;
      if (liveBus.etas.isNotEmpty) {
        etaMins = liveBus.etas.first.minutes;
      } else {
        final speedKmh = liveBus.speed > 5 ? liveBus.speed : 25.0;
        final speedMps = (speedKmh * 1000) / 3600;
        etaMins = math.max(1, (distM / speedMps / 60).round());
      }

      NotificationService().updateLiveTrackingNotification(
        busNumber: liveBus.displayBusNumber,
        targetStop: targetStop,
        etaMinutes: etaMins,
        distanceStr: distStr,
        speedKmh: liveBus.speed,
      );
    } else {
      NotificationService().cancelLiveTrackingNotification();
    }
  }

  void _checkProximityGeofence(Bus bus, String userPickup) {
    if (!bus.isBroadcastingLive || userPickup.isEmpty || _selectedRoute == null) return;

    if (_lastProximityAlertTime != null &&
        DateTime.now().difference(_lastProximityAlertTime!).inMinutes < 10) {
      return;
    }

    final pickupStop = _selectedRoute!.stops.firstWhere(
      (s) {
        final sName = (s['name'] ?? '').toString().toLowerCase().trim();
        return sName == userPickup || sName.contains(userPickup) || userPickup.contains(sName);
      },
      orElse: () => <String, dynamic>{},
    );

    if (pickupStop.isEmpty || pickupStop['lat'] == null || pickupStop['lng'] == null) return;

    final stopLat = (pickupStop['lat'] as num).toDouble();
    final stopLng = (pickupStop['lng'] as num).toDouble();
    if (stopLat == 0.0 || stopLng == 0.0) return;

    // Use road-distance estimation (1.5× Haversine for Indian roads) for accurate proximity
    final straightDistMeters = Geolocator.distanceBetween(bus.currentLat, bus.currentLng, stopLat, stopLng);
    final roadDistMeters = straightDistMeters * 1.5;
    // Prefer server-computed ETA from bus.etas matching this stop
    int etaMins;
    final matchedEta = bus.etas.where(
      (e) => e.stopName.toLowerCase().trim() == userPickup.toLowerCase().trim() ||
             e.stopName.toLowerCase().trim() == (pickupStop['name']?.toString() ?? '').toLowerCase().trim(),
    );
    if (matchedEta.isNotEmpty) {
      etaMins = matchedEta.first.minutes;
    } else {
      final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
      final speedMps = (speedKmh * 1000) / 3600;
      etaMins = math.max(1, (roadDistMeters / speedMps / 60).round());
    }

    // Trigger alert if within 800m road distance or ≤ 2 minutes
    if (roadDistMeters <= 800 || etaMins <= 2) {
      final stopName = pickupStop['name']?.toString() ?? userPickup;
      if (!_notifiedGeofenceStops.contains(stopName.toLowerCase())) {
        _notifiedGeofenceStops.add(stopName.toLowerCase());
        _lastProximityAlertTime = DateTime.now();

        final distStr = roadDistMeters < 1000 ? '${roadDistMeters.toStringAsFixed(0)} m' : '${(roadDistMeters / 1000).toStringAsFixed(1)} km';
        NotificationService().showProximityArrivalAlert(
          busNumber: bus.displayBusNumber,
          stopName: stopName,
          etaMinutes: etaMins,
          distanceStr: distStr,
        );
        HapticFeedback.heavyImpact();
      }
    }
  }

  /// Called when returning from ProfileSettingsScreen to reset any stale
  /// pickup-related state that was computed before the user changed their stop.
  ///
  /// Without this, _notifiedGeofenceStops and _etaMinutes would keep their
  /// old values for the original stop even after the pickup point changes,
  /// which causes wrong alerts and stale ETA display.
  void _refreshPickupState() {
    if (!mounted) return;
    setState(() {
      _notifiedGeofenceStops.clear();
      _lastProximityAlertTime = null;
      _etaMinutes = null;
    });
    // Re-fetch ETA for the updated pickup stop (no-op if no pickup configured)
    _fetchETA();
  }

  RouteModel? _resolveTargetRoute(AuthService auth, BusStore busStore, String? savedRouteId) {
    RouteModel? target;
    if (auth.currentUser?.routeId != null) {
      final matched = _routes.where((r) => r.id.trim() == auth.currentUser!.routeId!.trim());
      if (matched.isNotEmpty) target = matched.first;
    }
    if (target == null && savedRouteId != null && !auth.isGuest) {
      final matched = _routes.where((r) => r.id.trim() == savedRouteId.trim());
      if (matched.isNotEmpty) target = matched.first;
    }
    if (target == null && busStore.allBuses.isNotEmpty) {
      final onlineBuses = busStore.allBuses.where((b) => b.status.toLowerCase().trim() != 'offline').toList();
      if (onlineBuses.isNotEmpty) {
        final online = onlineBuses.first;
        final matched = _routes.where((r) =>
          (r.id.isNotEmpty && r.id.trim() == online.routeId.trim()) ||
          (r.name.isNotEmpty && r.name.trim().toLowerCase() == online.routeName.trim().toLowerCase())
        );
        if (matched.isNotEmpty) target = matched.first;
      }
    }
    target ??= (_routes.isNotEmpty ? _routes.first : null);
    return target;
  }

  Future<void> _fetchData() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final busStore = Provider.of<BusStore>(context, listen: false);
    final routeEndpoint = auth.isGuest ? 'guest/routes' : 'routes';
    final busEndpoint = auth.isGuest ? 'guest/buses' : 'buses';

    // ── ⚡ STEP 1: INSTANT LOCAL DISK CACHE RESTORATION (0-5ms) ───────────
    try {
      final cachedRouteData = await ApiService.getPersisted(routeEndpoint.replaceAll('/', '_')) ??
                              await ApiService.getPersisted('routes') ??
                              await ApiService.getPersisted('guest_routes');
      final cachedBusData = await ApiService.getPersisted(busEndpoint.replaceAll('/', '_')) ??
                            await ApiService.getPersisted('buses') ??
                            await ApiService.getPersisted('guest_buses');

      if (cachedRouteData is List && cachedRouteData.isNotEmpty && mounted) {
        _routes = cachedRouteData.map((r) => RouteModel.fromJson(r)).toList();
        if (cachedBusData is List && cachedBusData.isNotEmpty) {
          busStore.seedBuses(cachedBusData);
        }

        String? savedRouteId;
        try {
          const storage = FlutterSecureStorage();
          savedRouteId = await storage.read(key: 'last_selected_route_id');
        } catch (_) {}
        if (savedRouteId == null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            savedRouteId = prefs.getString('last_selected_route_id');
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            _selectedRoute = _resolveTargetRoute(auth, busStore, savedRouteId);
            _isLoading = false; // ← INSTANT ZERO-LATENCY LOAD! App renders in 0.05s!
            _updateActiveBus(busStore);
          });
        }
      }
    } catch (e) {
      debugPrint('Fast local cache restoration error: $e');
    }

    // ── ⚡ STEP 2: FRESH NETWORK REVALIDATION (STALE-WHILE-REVALIDATE) ─────
    try {
      // Resilient parallel requests: a failure in notifications or a single endpoint
      // will NEVER prevent routes and buses from loading!
      final routeFuture = _apiService
          .get(routeEndpoint, requiresAuth: !auth.isGuest, useCache: true, persistCache: true)
          .catchError((_) => _apiService.get('guest/routes', requiresAuth: false, useCache: true, persistCache: true))
          .catchError((e) {
            debugPrint('⚠️ Route fetch error: $e');
            return null;
          });

      final busFuture = _apiService
          .get(busEndpoint, requiresAuth: false, persistCache: true)
          .catchError((_) => _apiService.get('guest/buses', requiresAuth: false, persistCache: true))
          .catchError((e) {
            debugPrint('⚠️ Bus fetch error: $e');
            return null;
          });

      final notifFuture = (!auth.isGuest)
          ? _apiService.get('notifications').catchError((e) => [])
          : Future.value([]);

      final List<dynamic> results = await Future.wait([routeFuture, busFuture, notifFuture]);

      if (!mounted) return;

      final dynamic routeData = results[0];
      final dynamic busData = results[1];
      final dynamic notifData = results.length > 2 ? results[2] : [];

      if (routeData is List && routeData.isNotEmpty) {
        _routes = routeData.map((r) => RouteModel.fromJson(r)).toList();
      }

      if (busData is List && busData.isNotEmpty) {
        busStore.seedBuses(busData);
      }

      if (notifData is List && notifData.isNotEmpty) {
        busStore.seedNotifications(notifData);
      }

      // Read saved route preference from local storage
      String? savedRouteId;
      try {
        const storage = FlutterSecureStorage();
        savedRouteId = await storage.read(key: 'last_selected_route_id');
      } catch (_) {}
      if (savedRouteId == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          savedRouteId = prefs.getString('last_selected_route_id');
        } catch (_) {}
      }

      final targetRoute = _resolveTargetRoute(auth, busStore, savedRouteId);

      setState(() {
        // If current selection is still in the new list, retain it; otherwise targetRoute
        if (_selectedRoute != null && _routes.any((r) => r.id == _selectedRoute!.id)) {
          _selectedRoute = _routes.firstWhere((r) => r.id == _selectedRoute!.id);
        } else {
          _selectedRoute = targetRoute;
        }
        _isLoading = false;
        _updateActiveBus(busStore);
      });
      if (!mounted) return;
      if (_selectedRoute != null && _selectedRoute!.id.isNotEmpty) {
        final socketService = Provider.of<SocketService>(context, listen: false);
        socketService.joinRoute(_selectedRoute!.id);
      }
    } catch (e) {
      debugPrint('Error fetching user dashboard data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initSocket() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.initSocket();

    // Proximity approach alert (existing)
    socketService.listenToBusApproach((data) {
      if (mounted) {
        final auth = Provider.of<AuthService>(context, listen: false);
        final currentUser = auth.currentUser;
        if (currentUser != null && 
            currentUser.proximityAlertsEnabled &&
            currentUser.routeId == data['routeId'] && 
            currentUser.pickupPoint == data['stopName']) {
          
          NotificationService().showNotification(
            title: 'SISTecChalo Alert: Bus Nearby',
            body: data['message'] ?? 'Your bus is arriving!',
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bus arriving at ${data['stopName']}!'),
              backgroundColor: const Color(0xFF2D5BFF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            )
          );
        }
      }
    });

    // ── Delay alert listener (new) ──────────────────────────────────────────
    socketService.listenToBusDelayed((data) {
      if (!mounted) return;
      final auth = Provider.of<AuthService>(context, listen: false);
      final myRouteId = auth.currentUser?.routeId ?? _selectedRoute?.id;
      if (myRouteId == null) return;
      // Only notify if this delay concerns the user's route
      if (data['routeId'] == myRouteId) {
        final msg = data['message'] ?? 'Your bus is running late.';
        NotificationService().showNotification(
          title: 'Bus Delay Alert',
          body: msg,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(msg, style: GoogleFonts.plusJakartaSans(color: Colors.white))),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    });
  }

  // Fetch ETA to user's pickup stop from backend
  Future<void> _fetchETA() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final routeId = _selectedRoute?.id ?? auth.currentUser?.routeId;
    final stopName = auth.currentUser?.pickupPoint;
    if (routeId == null || stopName == null || stopName.isEmpty) return;

    setState(() => _etaLoading = true);
    try {
      final data = await _apiService.get(
        'eta?routeId=${Uri.encodeQueryComponent(routeId)}&stopName=${Uri.encodeQueryComponent(stopName)}',
      );
      if (mounted) {
        setState(() {
          _etaMinutes = data['eta'] as int?;
          _etaLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _etaLoading = false);
    }
  }

  // Subscribe user to delay notifications for selected route
  Future<void> _subscribeToDelay() async {
    final routeId = _selectedRoute?.id;
    if (routeId == null) return;
    try {
      await _apiService.post('subscribe-delay', { 'routeId': routeId });
      if (mounted) {
        setState(() => _delaySubscribed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text('You will be notified if this bus runs late.', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Bus? _resolveActiveBus(BusStore busStore, RouteModel? route) {
    if (route == null) {
      final online = busStore.activeBuses;
      return online.isNotEmpty ? online.first : null;
    }

    final selId = route.id.trim().toLowerCase();
    final selName = route.name.trim().toLowerCase();

    // 1. Search ONLY for live buses actively broadcasting on this route
    final onlineBuses = busStore.allBuses.where((b) {
      if (!b.isBroadcastingLive) return false;
      final rId = b.routeId.trim().toLowerCase();
      final rName = b.routeName.trim().toLowerCase();
      return (rId.isNotEmpty && (rId == selId || selId.contains(rId) || rId.contains(selId))) ||
             (rName.isNotEmpty && (rName == selName || rName.contains(selName) || selName.contains(rName)));
    }).toList();

    if (onlineBuses.isNotEmpty) {
      onlineBuses.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      return onlineBuses.first;
    }

    // Do NOT fall back to offline buses as active buses — shuttle must only show when driver broadcasts
    return null;
  }

  void _updateActiveBus(BusStore busStore) {
    _activeBus = _resolveActiveBus(busStore, _selectedRoute);
  }

  void _changeSelectedRoute(RouteModel? route, [Bus? liveBus]) {
    final prevRouteId = _selectedRoute?.id;
    setState(() {
      _selectedRoute = route;
      _isSwapBannerDismissed = false;
      if (liveBus != null) {
        _activeBus = liveBus;
      } else {
        final store = Provider.of<BusStore>(context, listen: false);
        _updateActiveBus(store);
      }
    });

    final socketService = Provider.of<SocketService>(context, listen: false);
    if (prevRouteId != null && prevRouteId != route?.id) {
      socketService.leaveRoute(prevRouteId);
    }
    if (route != null && route.id.isNotEmpty) {
      socketService.joinRoute(route.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth     = Provider.of<AuthService>(context, listen: false);
    final busStore = Provider.of<BusStore>(context, listen: false);

    _activeBus = _resolveActiveBus(busStore, _selectedRoute);

    return DashboardBackScope(
      onWillHandleBack: () {
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return true;
        }
        if (_sheetController.isAttached && _sheetController.size > 0.40) {
          _sheetController.animateTo(
            0.35,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
          return true;
        }
        return false;
      },
      exitMessage: 'Press back again to exit SISTecChalo',
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [
                _isLoading
                    ? Container(
                        color: AppColors.bg,
                        child: Center(child: _buildShimmerLoader()),
                      )
                    : _buildTrackingTab(),
                _buildAlertsTab(),          // has own Consumer<BusStore>
                _buildProfileTab(auth),     // has own Consumer<AuthService>
              ],
            ),
            if (_showDebugOverlay) _buildDebugOverlay(busStore),
            if (_currentIndex == 0) _buildFloatingHeader(busStore),
            if (_currentIndex == 0) _buildLiveBusSwapAlertBanner(busStore),
          ],
        ),
        bottomNavigationBar: _buildModernBottomNav(), // Selector<BusStore,int>
      ),
    );
  }

  Widget _buildDebugOverlay(BusStore busStore) {
    final buses = busStore.allBuses;
    return Positioned(
      top: 150, left: 20, right: 20,
      child: Container(
        height: 250,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DEBUG TELEMETRY', style: GoogleFonts.plusJakartaSans(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                IconButton(icon: const Icon(Icons.close, color: AppColors.textMuted, size: 16), onPressed: () => setState(() => _showDebugOverlay = false)),
              ],
            ),
            Divider(color: Colors.white.withValues(alpha: 0.06)),
            Expanded(
              child: buses.isEmpty 
                ? Center(child: Text('NO DATA RECEIVED YET', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: buses.length,
                    itemBuilder: (context, i) {
                      final bus = buses[i];
                      final isFresh = DateTime.now().difference(bus.lastUpdated).inSeconds < 10;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.04))),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: isFresh ? AppColors.accentGreen : AppColors.danger, shape: BoxShape.circle)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ID: ${bus.id.substring(math.max(0, bus.id.length - 6))}', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  Text('Route: ${bus.routeName}', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 8)),
                                ],
                              ),
                            ),
                            Text('${bus.speed.toInt()} KM/H', style: GoogleFonts.plusJakartaSans(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildFloatingHeader(BusStore busStore) {
    if (_isDriveMode) return const SizedBox.shrink();
    final socketService = Provider.of<SocketService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Interactive Route Title and Live Status Indicator
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showRouteSelection();
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                            ),
                            child: const Icon(
                              Icons.alt_route_rounded,
                              color: AppColors.primaryLight,
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'SISTEC SHUTTLE',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppColors.textMuted,
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    ValueListenableBuilder<DateTime?>(
                                      valueListenable: socketService.lastDataReceived,
                                      builder: (context, lastPacket, _) {
                                        final isRecent = lastPacket != null &&
                                            DateTime.now().difference(lastPacket).inSeconds < 15;
                                        return Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: isRecent ? AppColors.accentGreen : AppColors.textMuted,
                                            shape: BoxShape.circle,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _selectedRoute?.name ?? 'Tap to select route',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: _selectedRoute != null ? Colors.white : AppColors.textMuted,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.unfold_more_rounded,
                            color: AppColors.textMuted,
                            size: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Route Switcher Quick Action
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showRouteSelection();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 20),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Emergency SOS Button (Always accessible)
                  GestureDetector(
                    onLongPress: () => _triggerSOS(auth),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.emergency_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                'Hold down to send Emergency SOS',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: AppColors.danger,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.emergency_rounded, color: AppColors.danger, size: 19),
                    ),
                  ),

                  // If Guest: Provide Sign-In Shortcut
                  if (auth.isGuest) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _handleLogout(context, auth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'Sign In',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.primaryLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1),
    );
  }

  Widget _buildTrackingTab() {
    // Listen to AuthService so that if the user changes their pickup stop
    // from profile settings the tracking tab rebuilds immediately with the
    // new pickupPoint — without this the stale listen:false ref causes
    // _checkProximityGeofence to keep running against the old stop name.
    final auth = Provider.of<AuthService>(context);

    return Consumer<BusStore>(
      builder: (context, store, _) {
        Bus? currentActiveBus = _resolveActiveBus(store, _selectedRoute);
        _activeBus = currentActiveBus;

        // In Guest Mode: If current route has no live bus, auto-switch to active live shuttle
        if (auth.isGuest && (currentActiveBus == null || !currentActiveBus.isBroadcastingLive)) {
          final liveBuses = store.activeBuses;
          if (liveBuses.isNotEmpty) {
            final liveBus = liveBuses.first;
            RouteModel? matchingRoute;
            for (final r in _routes) {
              final rId = r.id.trim();
              final rName = r.name.trim().toLowerCase();
              if ((rId.isNotEmpty && rId == liveBus.routeId.trim()) ||
                  (rName.isNotEmpty && rName == liveBus.routeName.trim().toLowerCase())) {
                matchingRoute = r;
                break;
              }
            }
            if (matchingRoute != null && matchingRoute.id != _selectedRoute?.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedRoute?.id != matchingRoute?.id) {
                  _changeSelectedRoute(matchingRoute, liveBus);
                }
              });
            }
          }
        }

        final mapBuses = store.allBuses.where((b) {
          if (!b.isBroadcastingLive) return false;
          if (_selectedRoute == null) return true;
          final rId = b.routeId.trim().toLowerCase();
          final rName = b.routeName.trim().toLowerCase();
          final selId = _selectedRoute!.id.trim().toLowerCase();
          final selName = _selectedRoute!.name.trim().toLowerCase();
          return (rId.isNotEmpty && (rId == selId || selId.contains(rId) || rId.contains(selId))) ||
                 (rName.isNotEmpty && (rName == selName || rName.contains(selName) || selName.contains(rName)));
        }).toList();

        // Safety guarantee: If currentActiveBus is live, ensure it is present in mapBuses
        if (currentActiveBus != null &&
            currentActiveBus.isBroadcastingLive &&
            !mapBuses.any((b) => b.id == currentActiveBus!.id)) {
          mapBuses.add(currentActiveBus);
        } else if ((currentActiveBus == null || !currentActiveBus.isBroadcastingLive) && mapBuses.isNotEmpty) {
          currentActiveBus = mapBuses.first;
          _activeBus = currentActiveBus;
        }

        // Proximity Geofencing check for student's pickup stop
        if (currentActiveBus != null && currentActiveBus.isBroadcastingLive) {
          final userPickup = auth.currentUser?.pickupPoint?.toLowerCase().trim() ?? '';
          _checkProximityGeofence(currentActiveBus, userPickup);
        }

        return Stack(
          children: [
            BusMap(
              key: _busMapKey,
              buses: mapBuses,
              selectedRoute: _selectedRoute,
              centerOnBusId: (currentActiveBus != null && currentActiveBus.isBroadcastingLive) ? currentActiveBus.id : null,
              showFocusedBusCard: false,
              onDriveModeChanged: (isDrive) {
                setState(() => _isDriveMode = isDrive);
              },
            ),
            if (auth.isGuest && _selectedRoute != null)
              _buildGuestLiveSwitchBanner(store),
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.35,
              minChildSize: 0.16,
              maxChildSize: 0.88,
              snap: true,
              snapSizes: const [0.16, 0.35, 0.88],
              builder: (context, scrollController) => Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 30,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_selectedRoute == null) ...[
                      Text(
                        'OVERVIEW',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ready for Transit',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select a shuttle route to begin live GPS tracking.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildActionCard('Active Fleet Radar', 'View all operational college buses', Icons.radar_rounded, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const FleetRadarScreen()));
                      }),
                      const SizedBox(height: 12),
                      _buildActionCard('Select Route', 'Synchronize with your assigned commute line', Icons.alt_route_rounded, _showRouteSelection),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Bus Line Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.directions_bus_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(
                                  _getAssignedBusLabel(store),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Route Title & Schedule Metadata
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedRoute!.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.3,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                GestureDetector(
                                  onTap: () => _showShiftAllocationModal(store),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${_getAssignedShiftLabel()} • ${_selectedRoute!.stops.length} Stops',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textMuted,
                                            letterSpacing: 0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textMuted, size: 16),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Live vs Scheduled Single Status Pill
                          ValueListenableBuilder<DateTime?>(
                            valueListenable: Provider.of<SocketService>(context, listen: false).lastDataReceived,
                            builder: (context, lastPacket, _) {
                              final isRecent = currentActiveBus != null &&
                                  currentActiveBus.isBroadcastingLive &&
                                  lastPacket != null && 
                                  DateTime.now().difference(lastPacket).inSeconds < 25;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isRecent 
                                      ? AppColors.accentGreen.withValues(alpha: 0.15) 
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isRecent 
                                        ? AppColors.accentGreen.withValues(alpha: 0.4) 
                                        : Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isRecent ? AppColors.accentGreen : AppColors.textMuted,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isRecent ? 'LIVE' : 'SCHEDULED',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isRecent ? AppColors.accentGreen : AppColors.textMuted,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      _buildHeroTransitCard(store),
                      const SizedBox(height: 14),
                      _buildQuickActionsRow(),
                      const SizedBox(height: 20),
                      _buildStopsList(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuestLiveSwitchBanner(BusStore store) {
    final liveBuses = store.activeBuses;
    if (liveBuses.isEmpty) return const SizedBox.shrink();

    Bus? otherLiveBus;
    for (final b in liveBuses) {
      final rId = b.routeId.trim();
      final rName = b.routeName.trim().toLowerCase();
      final selId = _selectedRoute?.id.trim() ?? '';
      final selName = _selectedRoute?.name.trim().toLowerCase() ?? '';
      if (rId != selId && rName != selName) {
        otherLiveBus = b;
        break;
      }
    }

    if (otherLiveBus == null) return const SizedBox.shrink();

    RouteModel? matchingRoute;
    for (final r in _routes) {
      final rId = r.id.trim();
      final rName = r.name.trim().toLowerCase();
      if ((rId.isNotEmpty && rId == otherLiveBus.routeId.trim()) ||
          (rName.isNotEmpty && rName == otherLiveBus.routeName.trim().toLowerCase())) {
        matchingRoute = r;
        break;
      }
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 88,
      left: 20,
      right: 20,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (matchingRoute != null) {
            _changeSelectedRoute(matchingRoute, otherLiveBus);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentGreen.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accentGreen,
                  shape: BoxShape.circle,
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(duration: 600.ms, begin: const Offset(0.7, 0.7), end: const Offset(1.4, 1.4)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live Shuttle: ${otherLiveBus.routeName} (${otherLiveBus.displayBusNumber})',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'TRACK NOW',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.accentGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.2),
    );
  }

  Widget _buildLiveBusSwapAlertBanner(BusStore busStore) {
    if (_isDriveMode || _selectedRoute == null || _isSwapBannerDismissed) {
      return const SizedBox.shrink();
    }

    final routeName = _selectedRoute!.name;
    String defaultBus = '';
    final defaultEntry = TimetableResolver.lookupEntry(routeName: routeName);
    if (defaultEntry != null) {
      defaultBus = defaultEntry.displayBusLabel;
    } else {
      final match = RegExp(r'^(Bus\s*[^-\:]+)', caseSensitive: false).firstMatch(routeName);
      if (match != null) defaultBus = match.group(1)!.trim();
    }

    bool isSwap = false;
    String assignedBusNum = '';
    String officialPlate = '';
    String driverName = '';
    String? driverPhone;
    String situationReason = 'Emergency Substitution';

    // 1. Check if active bus running on this route differs from default bus
    final activeBus = _activeBus;
    if (activeBus != null && activeBus.isBroadcastingLive) {
      final activeBusNo = activeBus.displayBusNumber.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final defaultClean = defaultBus.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

      final defaultDigits = defaultClean.replaceAll(RegExp(r'\D'), '');
      final activeDigits = activeBusNo.replaceAll(RegExp(r'\D'), '');

      if (defaultDigits.isNotEmpty && activeDigits.isNotEmpty && defaultDigits != activeDigits) {
        isSwap = true;
        assignedBusNum = activeBus.displayBusNumber;
        officialPlate = activeBus.officialVehicleNo;
        driverName = activeBus.assignedDriverName;
        driverPhone = activeBus.assignedDriverPhone;
      }
    }

    // 2. Also check if there is an active swap notification in busStore
    if (!isSwap && busStore.notifications.isNotEmpty) {
      for (final notif in busStore.notifications) {
        final msg = notif.message;
        if (msg.contains('⚡ Bus Update') && msg.contains(routeName)) {
          isSwap = true;
          final match = RegExp(r'Bus Update:\s*([A-Za-z0-9\-\s]+?)\s+has been assigned to\s+([^.\(]+)', caseSensitive: false).firstMatch(msg);
          if (match != null) {
            assignedBusNum = match.group(1)!.trim();
          }
          final reasonMatch = RegExp(r'\(([^)]+)\)', caseSensitive: false).firstMatch(msg);
          if (reasonMatch != null) {
            situationReason = reasonMatch.group(1)!.trim();
          }
          final entry = TimetableResolver.lookupEntry(routeName: routeName, busNumber: assignedBusNum);
          if (entry != null) {
            driverName = entry.driverName;
            driverPhone = entry.driverPhone;
            officialPlate = entry.vehicleNo;
          }
          break;
        }
      }
    }

    if (!isSwap) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 78,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF231604), Color(0xFF181002)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row: Badge + Title + Dismiss Button
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.black, size: 13),
                        const SizedBox(width: 3),
                        Text(
                          'LIVE ROUTE NOTICE',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 9.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      situationReason,
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFFFBBF24),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _isSwapBannerDismissed = true);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Swap details
              Text(
                'Bus $assignedBusNum${officialPlate.isNotEmpty ? ' ($officialPlate)' : ''} is operating on ${defaultBus.isNotEmpty ? defaultBus : 'this route'} today.',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),

              // Driver & Action Row
              Row(
                children: [
                  if (driverName.isNotEmpty) ...[
                    const Icon(Icons.person_rounded, size: 13, color: Colors.white60),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Driver: $driverName',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (driverPhone != null && driverPhone.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final uri = Uri.parse('tel:$driverPhone');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF34D399), size: 13),
                            const SizedBox(width: 4),
                            Text(
                              'Call Driver',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF34D399),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.15);
  }

  String _getAssignedBusLabel(BusStore busStore) {
    if (_selectedShiftFilter != null) {
      return TimetableResolver.resolveAssignedBusNumber(
        routeName: _selectedRoute?.name,
        shift: _selectedShiftFilter,
      );
    }
    if (_activeBus != null) {
      return _activeBus!.displayBusNumber;
    }
    if (_selectedRoute != null) {
      final busesOnRoute = busStore.allBuses.where((b) => b.routeId == _selectedRoute!.id).toList();
      if (busesOnRoute.isNotEmpty) {
        return busesOnRoute.first.displayBusNumber;
      }
      return TimetableResolver.resolveAssignedBusNumber(
        routeName: _selectedRoute!.name,
      );
    }
    return 'BUS ASSIGNED';
  }

  String _getAssignedShiftLabel() {
    final isLive = _activeBus != null && _activeBus!.isBroadcastingLive;
    if (_selectedShiftFilter != null) {
      return TimetableResolver.resolveShiftLabel(
        explicitShift: _selectedShiftFilter,
        routeName: _selectedRoute?.name,
        direction: _shiftTimelineDirection,
      );
    }
    return TimetableResolver.resolveRealtimeShiftLabel(
      routeName: _selectedRoute?.name,
      direction: _shiftTimelineDirection,
      isLive: isLive,
    );
  }

  String _getCurrentDayLabel() {
    return TimetableResolver.getCurrentDayLabel();
  }

  void _showShiftAllocationModal(BusStore busStore) {
    HapticFeedback.mediumImpact();
    final routeName = _selectedRoute?.name ?? 'SISTec Transit Route';
    final availableShifts = TimetableResolver.getShiftsForRoute(routeName);
    final currentDay = _getCurrentDayLabel();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MANAGER BUS ALLOCATION',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryLight,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Day & Shift Schedule',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          '$currentDay • ACTIVE',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentGreen,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Official manager-assigned fleet vehicles and departure times for this corridor:',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: availableShifts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final entry = availableShifts[idx];
                        final isSelected = (_selectedShiftFilter == null && idx == 0) ||
                            (_selectedShiftFilter == entry.shift);

                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final bool isEveningOrDropoff = entry.period.toLowerCase().contains('afternoon') ||
                                entry.period.toLowerCase().contains('evening') ||
                                entry.shift.toLowerCase().contains('shift 2') ||
                                entry.shift.toLowerCase().contains('shift 3') ||
                                entry.shift.toLowerCase().contains('shift 4');
                            setState(() {
                              _selectedShiftFilter = entry.shift;
                              _shiftTimelineDirection = isEveningOrDropoff ? 'dropoff' : 'pickup';
                            });
                            Navigator.pop(ctx);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.06),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary : AppColors.surfaceLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      entry.busNumber,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            entry.displayBusLabel,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceLight,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              entry.shiftTag,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primaryLight,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Departs: ${entry.morningDeparture} • Reg: ${entry.vehicleNo}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                      Text(
                                        'Driver: ${entry.driverName}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10.5,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_selectedShiftFilter != null)
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedShiftFilter = null;
                            _shiftTimelineDirection = (DateTime.now().hour < 12) ? 'pickup' : 'dropoff';
                          });
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 14, color: AppColors.textMuted),
                        label: Text(
                          'Reset to Auto/Current Shift',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeroTransitCard(BusStore busStore) {
    final bus = _resolveActiveBus(busStore, _selectedRoute) ?? _activeBus;
    final isLive = bus != null && bus.isBroadcastingLive;
    final auth = Provider.of<AuthService>(context, listen: false);
    final hasPickup = (auth.currentUser?.pickupPoint ?? '').isNotEmpty;
    final pickupName = auth.currentUser?.pickupPoint ?? '';

    String etaDisplay = '--';
    String etaUnit = 'MIN';
    String targetStopHeader = 'ROUTE TERMINAL';
    String targetStopLabel = 'SISTEC CAMPUS';

    if (_etaLoading) {
      etaDisplay = '...';
      etaUnit = '';
    } else if (isLive) {
      int? mins;
      if (hasPickup) {
        targetStopHeader = (_shiftTimelineDirection == 'dropoff')
            ? 'ESTIMATED DROP-OFF AT YOUR STOP'
            : 'ESTIMATED ARRIVAL AT YOUR STOP';
        targetStopLabel = pickupName.toUpperCase();

        final matched = bus.etas.where(
          (e) => e.stopName.toLowerCase().trim() == pickupName.toLowerCase().trim(),
        );
        if (matched.isNotEmpty) {
          mins = matched.first.minutes;
        } else if (_selectedRoute != null && _selectedRoute!.stops.isNotEmpty) {
          final stop = _selectedRoute!.stops.firstWhere(
            (s) => (s['name'] ?? '').toString().toLowerCase().trim() == pickupName.toLowerCase().trim(),
            orElse: () => <String, dynamic>{},
          );
          if (stop.isNotEmpty && stop['lat'] != null && stop['lng'] != null) {
            // Use road-distance estimation (1.5× Haversine for Indian mixed roads)
            final straightDistM = Geolocator.distanceBetween(
              bus.currentLat, bus.currentLng,
              (stop['lat'] as num).toDouble(), (stop['lng'] as num).toDouble(),
            );
            final roadDistM = straightDistM * 1.5;
            final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
            final speedMps = (speedKmh * 1000) / 3600;
            mins = math.max(1, (roadDistM / speedMps / 60).round());
          }
        }
      } else {
        // Guest or unassigned student commuter: target the next upcoming stop
        targetStopHeader = 'NEXT UPCOMING STOP • LIVE ETA';
        if (bus.etas.isNotEmpty) {
          final nextEta = bus.etas.first;
          targetStopLabel = nextEta.stopName.toUpperCase();
          mins = nextEta.minutes;
        } else if (bus.nextStop != null && bus.nextStop!.isNotEmpty) {
          targetStopLabel = bus.nextStop!.toUpperCase();
          if (bus.distanceToNextStopMeters != null && bus.distanceToNextStopMeters! > 0) {
            // distanceToNextStopMeters is already road-adjusted from driver broadcast
            final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
            final speedMps = (speedKmh * 1000) / 3600;
            mins = math.max(1, (bus.distanceToNextStopMeters! / speedMps / 60).round());
          }
        }

        // If still not resolved, determine from route stops with road factor
        if (mins == null && _selectedRoute != null && _selectedRoute!.stops.isNotEmpty) {
          final unreached = _selectedRoute!.stops.where((s) {
            final sName = (s['name'] ?? '').toString();
            return !bus.reachedStops.contains(sName);
          }).toList();
          final candidateStop = unreached.isNotEmpty ? unreached.first : _selectedRoute!.stops.first;
          targetStopLabel = (candidateStop['name'] ?? 'CAMPUS TERMINAL').toString().toUpperCase();
          if (candidateStop['lat'] != null && candidateStop['lng'] != null) {
            // Road-distance estimation (1.5× for Indian mixed roads)
            final straightDistM = Geolocator.distanceBetween(
              bus.currentLat, bus.currentLng,
              (candidateStop['lat'] as num).toDouble(), (candidateStop['lng'] as num).toDouble(),
            );
            final roadDistM = straightDistM * 1.5;
            final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
            final speedMps = (speedKmh * 1000) / 3600;
            mins = math.max(1, (roadDistM / speedMps / 60).round());
          }
        }
      }

      if (mins != null) {
        etaDisplay = '$mins';
        etaUnit = 'MIN';
      } else if (_etaMinutes != null) {
        etaDisplay = '$_etaMinutes';
        etaUnit = 'MIN';
      }
    } else {
      if (hasPickup) {
        targetStopHeader = 'ASSIGNED PICKUP STOP';
        targetStopLabel = pickupName.toUpperCase();
      } else {
        targetStopHeader = (_shiftTimelineDirection == 'dropoff')
            ? 'CAMPUS DEPARTURE ➔ CITY DROP-OFF'
            : 'ORIGIN & ROUTE TERMINAL';
        targetStopLabel = (_selectedRoute?.stops.isNotEmpty == true)
            ? (_selectedRoute!.stops.first['name'] ?? 'SISTEC CAMPUS').toString().toUpperCase()
            : 'SISTEC CAMPUS';
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isLive ? AppColors.primary.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08),
          width: isLive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: (isLive ? AppColors.primary : Colors.black).withValues(alpha: isLive ? 0.15 : 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Hero Metrics Section
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLive) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              etaDisplay,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1.5,
                                height: 1.0,
                              ),
                            ),
                            if (etaUnit.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                etaUnit,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryLight,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.accentGreen,
                                shape: BoxShape.circle,
                              ),
                            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(duration: 800.ms, begin: const Offset(0.8, 0.8), end: const Offset(1.3, 1.3)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Approaching ${targetStopLabel.toLowerCase()}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accentGreen,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.schedule_rounded,
                                color: AppColors.primaryLight,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final shifts = TimetableResolver.getShiftsForRoute(_selectedRoute?.name);
                                  final entry = shifts.isNotEmpty ? shifts.first : TimetableResolver.masterFleet[1];
                                  final isDropoffDir = _shiftTimelineDirection == 'dropoff';
                                  final rawDepTime = isDropoffDir ? entry.returnDeparture : entry.morningDeparture;
                                  final depTime = rawDepTime.startsWith('0') ? rawDepTime.substring(1) : rawDepTime;
                                  final depTitle = isDropoffDir ? 'Return Departure • $depTime' : 'Morning Departure • $depTime';
                                  final depSub = isDropoffDir 
                                      ? 'Campus departure scheduled at $depTime'
                                      : 'Morning pickup scheduled at $depTime';
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        depTitle,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        depSub,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Right Side Widget: Speedometer or Refresh
                if (isLive) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.bgSecondary,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed_rounded, color: AppColors.accent, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              '${bus.speed.toInt()}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'KM/H',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasPickup) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _fetchETA();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.refresh_rounded, color: AppColors.primaryLight, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'Update ETA',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.primaryLight,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgSecondary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Text(
                      'STANDBY',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Assigned Stop Sub-Card inside Hero
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: hasPickup 
                          ? (_shiftTimelineDirection == 'dropoff' ? AppColors.accent.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15))
                          : (isLive ? AppColors.accentGreen.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      hasPickup 
                          ? (_shiftTimelineDirection == 'dropoff' ? Icons.departure_board_rounded : Icons.my_location_rounded) 
                          : (isLive ? Icons.near_me_rounded : Icons.location_on_rounded),
                      color: hasPickup 
                          ? (_shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primaryLight) 
                          : (isLive ? AppColors.accentGreen : AppColors.primaryLight),
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          targetStopHeader,
                          style: GoogleFonts.plusJakartaSans(
                            color: (isLive && !hasPickup) ? AppColors.accentGreen : AppColors.textMuted,
                            fontSize: 9.0,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          targetStopLabel,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (hasPickup)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primary).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (_shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primaryLight).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _shiftTimelineDirection == 'dropoff' ? 'MY DROP-OFF' : 'MY STOP',
                        style: GoogleFonts.plusJakartaSans(
                          color: _shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primaryLight,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else if (isLive && bus.etas.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'LIVE',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.accentGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Official Vehicle & Driver Information Bar from Institutional Roster
          Builder(
            builder: (context) {
              final busDetail = TimetableResolver.resolveBusDetails(
                routeName: _selectedRoute?.name,
                busNo: bus?.busNumber,
              );
              if (busDetail == null) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.directions_bus_rounded, size: 13, color: AppColors.primaryLight),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      busDetail.vehicleNo,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(color: Color(0xFF64748B), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Driver: ${busDetail.driverName}',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (busDetail.driverPhone.isNotEmpty)
                      GestureDetector(
                        onTap: () => _makePhoneCall(busDetail.driverPhone),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.phone_rounded, size: 10, color: AppColors.accentGreen),
                              const SizedBox(width: 4),
                              Text(
                                'CALL',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.accentGreen,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildQuickAction(
            icon: Icons.calendar_month_rounded,
            label: 'Schedule',
            color: AppColors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ScheduleScreen(route: _selectedRoute)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildQuickAction(
            icon: _delaySubscribed
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            label: _delaySubscribed ? 'Subscribed' : 'Alerts',
            color: _delaySubscribed ? AppColors.accentGreen : AppColors.warning,
            onTap: _delaySubscribed || _selectedRoute == null ? null : _subscribeToDelay,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildQuickAction(
            icon: Icons.headset_mic_rounded,
            label: 'Helpline',
            color: AppColors.accent,
            onTap: () => _showTransportHelpSheet(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildQuickAction(
            icon: Icons.report_problem_rounded,
            label: 'Report',
            color: AppColors.danger,
            onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ComplaintScreen(
                    selectedRoute: _selectedRoute,
                    activeBus: _activeBus,
                  ))),
          ),
        ),
      ],
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final clean = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not initiate call to $clean: $e');
    }
  }

  void _showTransportHelpSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    final busDetail = TimetableResolver.resolveBusDetails(
      routeName: _selectedRoute?.name,
      busNo: _activeBus?.busNumber,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.headset_mic_rounded, color: AppColors.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SISTec Transport Helpdesk',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Ratibad Campus • 09:00 AM Shift Roster',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (busDetail != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.person_rounded, color: AppColors.primaryLight, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                busDetail.driverName,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Driver • ${busDetail.displayBusLabel} (${busDetail.vehicleNo})',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (busDetail.driverPhone.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: () => _makePhoneCall(busDetail.driverPhone),
                            icon: const Icon(Icons.phone_rounded, size: 14),
                            label: const Text('Call'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'COLLEGE TRANSPORT INCHARGES',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ...TimetableResolver.transportIncharges.map((incharge) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.shield_outlined, color: AppColors.accent, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                incharge.name,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                incharge.designation,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _makePhoneCall(incharge.phone),
                          icon: const Icon(Icons.phone_rounded, size: 14),
                          label: const Text('Call'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: () {
        if (!disabled) {
          HapticFeedback.lightImpact();
          onTap();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.02)
              : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: disabled
                ? Colors.white.withValues(alpha: 0.03)
                : color.withValues(alpha: 0.20),
            width: 1.0,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: disabled
                    ? Colors.white.withValues(alpha: 0.04)
                    : color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: disabled ? AppColors.textDisabled : color,
                size: 18,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: disabled ? AppColors.textDisabled : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(String title, String sub, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        // Mark all read when alerts tab is visible — guarded so we only
        // schedule once per dirty unread cycle, not on every bus GPS tick.
        if (_currentIndex == 1 && busStore.unreadCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) busStore.markAllRead();
          });
        }

        final allAlerts = busStore.notifications;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 110,
              backgroundColor: AppColors.bgSecondary,
              pinned: true,
              actions: [
                if (allAlerts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70, size: 22),
                      tooltip: 'Clear All Notifications',
                      onPressed: () => _confirmClearAllNotifications(context, busStore),
                    ),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NOTIFICATIONS',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    if (allAlerts.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${allAlerts.length}',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.primaryLight,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              sliver: allAlerts.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                            ),
                            child: const Icon(Icons.notifications_none_rounded, color: AppColors.textMuted, size: 40),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'NO ALERTS YET',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Campus broadcasts and route updates will appear here in real-time.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildNotificationCard(
                        allAlerts[index],
                        index,
                        busStore,
                      ),
                      childCount: allAlerts.length,
                    ),
                  ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearAllNotifications(BuildContext context, BusStore busStore) async {
    HapticFeedback.lightImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'CLEAR ALL',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to clear all ${busStore.notifications.length} notifications?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR ALL', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      busStore.clearAllNotifications();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Text('All notifications cleared', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatAlertTime(String? timestamp) {
    if (timestamp == null) return 'JUST NOW';
    final date = DateTime.parse(timestamp).toLocal();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    return '${diff.inHours}H AGO';
  }

  Widget _buildNotificationCard(LiveNotification alert, int index, BusStore busStore) {
    final isCritical = alert.type == 'critical';
    final accentColor = isCritical ? AppColors.danger : AppColors.primary;

    return Dismissible(
      key: Key('notif_${alert.id}_$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        busStore.removeNotification(alert.id);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notification removed', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13)),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
        ),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('DELETE', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 12)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 22),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCritical ? Icons.warning_rounded : Icons.info_outline_rounded,
                color: isCritical ? AppColors.danger : AppColors.primaryLight,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          isCritical ? 'CRITICAL ALERT' : 'TRANSIT DIRECTIVE', 
                          style: GoogleFonts.plusJakartaSans(
                            color: isCritical ? AppColors.danger : AppColors.primaryLight,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatAlertTime(alert.timestamp.toIso8601String()),
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alert.message,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Delete notification',
              onPressed: () {
                busStore.removeNotification(alert.id);
              },
            ),
          ],
        ),
      ),
    );
    // Note: .animate() removed from list items — running staggered flutter_animate
    // inside a SliverList causes significant frame jank on mid-range devices.
  }

  Widget _buildProfileTab(AuthService auth) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        if (!authService.isAuthenticated || user == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_clock_rounded, color: Color(0xFF60A5FA), size: 36),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SESSION EXPIRED',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your login session has ended. Please sign in again to access live tracking and personalized alerts.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF94A3B8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const AuthWrapper()),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: Text(
                          'RETURN TO LOGIN',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final displayName = _getUserDisplayName(user, authService);
        final enrollmentId = _getEnrollmentId(user);
        final avatarInitials = _getAvatarInitials(user, authService);
        final roleName = (user.role).toUpperCase();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 70, 20, 100),
          children: [
            Center(
              child: Column(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        avatarInitials,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF60A5FA),
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (enrollmentId.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 6),
                              Text(
                                enrollmentId,
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFE2E8F0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          roleName,
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF60A5FA),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            Consumer<BusStore>(
              builder: (context, busStore, _) {
                final latestNotifs = busStore.notifications.take(3).toList();
                return _buildProfileSection('NOTIFICATION FEED', [
                  if (latestNotifs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'NO RECENT ACTIVITY',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    )
                  else
                    ...latestNotifs.map((n) => ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: n.type == 'critical'
                              ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                              : const Color(0xFF3B82F6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          n.type == 'critical' ? Icons.warning_rounded : Icons.info_outline_rounded,
                          color: n.type == 'critical' ? const Color(0xFFEF4444) : const Color(0xFF60A5FA),
                          size: 16,
                        ),
                      ),
                      title: Text(
                        n.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _formatAlertTime(n.timestamp.toIso8601String()),
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontSize: 10),
                      ),
                      onTap: () => setState(() => _currentIndex = 1),
                    )),
                  if (latestNotifs.isNotEmpty)
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _currentIndex = 1),
                        child: Text(
                          'VIEW ALL HISTORY',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF3B82F6),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 20),
            _buildProfileSection('PREFERENCES', [
              _ProximityPreferencesSection(auth: authService, user: user),
              _buildProfileTile('THEME', 'NEON DEPTH', Icons.dark_mode_outlined),
            ]),
            const SizedBox(height: 20),
            _buildProfileSection('TRANSPORT', [
              _buildProfileTile('PICKUP', user.pickupPoint ?? 'NOT SET', Icons.location_on_outlined),
              _buildProfileTile('ROUTE', _selectedRoute?.name ?? 'NOT ASSIGNED', Icons.alt_route_rounded),
            ]),
            if (!authService.isGuest) ...[
              const SizedBox(height: 20),
              _buildProfileSection('ACCOUNT', [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_outline_rounded, color: Color(0xFF60A5FA), size: 18),
                  ),
                  title: Text(
                    'Personal Profile',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Edit your name, email, and phone',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF475569)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
                    ).then((_) {
                      // Returning from ProfileSettingsScreen — reset any stale
                      // proximity/ETA state that was computed for the old pickup
                      // stop and re-compute with the (possibly new) pickup.
                      _refreshPickupState();
                    });
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lock_outline_rounded, color: Color(0xFFA78BFA), size: 18),
                  ),
                  title: Text(
                    'Change Password',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Update your login password',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF475569)),
                  onTap: () => _showChangePasswordSheet(authService),
                ),
              ]),
            ],
            const SizedBox(height: 28),
            if (authService.isGuest) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.info_outline_rounded, color: Color(0xFF60A5FA), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BROWSING IN GUEST MODE',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF60A5FA),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                'Sign in to access personalized alerts, route customization & emergency services.',
                                style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _handleLogout(context, authService),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: Text(
                          'SIGN IN WITH ACCOUNT',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _handleLogout(context, authService),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    'EXIT GUEST MODE',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _handleLogout(context, authService),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F1D1D).withValues(alpha: 0.25),
                    foregroundColor: const Color(0xFFF87171),
                    side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    'LOG OUT OF SESSION',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _handleLogout(BuildContext context, AuthService authService) async {
    HapticFeedback.mediumImpact();
    final bool isGuest = authService.isGuest;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              isGuest ? 'EXIT GUEST MODE' : 'LOG OUT',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          isGuest
              ? 'Are you sure you want to exit guest mode and return to the login screen?'
              : 'Are you sure you want to end your active session and log out?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isGuest ? 'EXIT GUEST' : 'LOG OUT',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await authService.logout();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    }
  }

  String _getUserDisplayName(User? user, AuthService auth) {
    if (auth.isGuest) return 'Guest Explorer';
    if (user == null) return 'Campus Commuter';
    if (user.name != null && user.name!.trim().isNotEmpty && user.name!.trim().toLowerCase() != user.username.trim().toLowerCase()) {
      return user.name!.trim();
    }
    return user.username;
  }

  String _getEnrollmentId(User? user) {
    if (user == null) return '';
    return user.userId ?? user.username;
  }

  String _getAvatarInitials(User? user, AuthService auth) {
    if (auth.isGuest) return 'G';
    if (user == null) return 'U';
    final name = (user.name != null && user.name!.trim().isNotEmpty) ? user.name!.trim() : user.username.trim();
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return 'U';
  }

  void _showChangePasswordSheet(AuthService auth) {
    final currentCtrl = TextEditingController();
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    bool showCurrent = false;
    bool showNew     = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final cur = currentCtrl.text.trim();
            final nw  = newCtrl.text.trim();
            final cnf = confirmCtrl.text.trim();
            if (cur.isEmpty || nw.isEmpty || cnf.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All fields are required.'), backgroundColor: Colors.redAccent));
              return;
            }
            if (nw.length < 6) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New password must be at least 6 characters.'), backgroundColor: Colors.redAccent));
              return;
            }
            if (nw != cnf) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New passwords do not match.'), backgroundColor: Colors.redAccent));
              return;
            }
            // Capture before async gap
            final messenger = ScaffoldMessenger.of(context);
            final nav = Navigator.of(ctx);
            setSheetState(() => saving = true);
            try {
              await auth.changePassword(cur, nw);
              if (mounted) {
                nav.pop();
                messenger.showSnackBar(SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 18),
                      const SizedBox(width: 10),
                      Text('Password changed successfully', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  backgroundColor: const Color(0xFF13222A),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                  ),
                ));
              }
            } catch (e) {
              setSheetState(() => saving = false);
              final msg = e.toString().replaceFirst('Exception: ', '');
              messenger.showSnackBar(SnackBar(
                content: Text(msg),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ));
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Change Password',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter your current password, then set a new one.',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    _pwField(ctx, 'Current Password', currentCtrl, showCurrent, () => setSheetState(() => showCurrent = !showCurrent)),
                    const SizedBox(height: 12),
                    _pwField(ctx, 'New Password (min 6 chars)', newCtrl, showNew, () => setSheetState(() => showNew = !showNew)),
                    const SizedBox(height: 12),
                    _pwField(ctx, 'Confirm New Password', confirmCtrl, showNew, null),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: saving ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: saving
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('UPDATE PASSWORD', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pwField(BuildContext ctx, String hint, TextEditingController ctrl, bool visible, VoidCallback? onToggle) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: !visible,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          suffixIcon: onToggle != null
              ? IconButton(
                  icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.textMuted, size: 18),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildProfileSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileTile(String label, String val, IconData icon) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF60A5FA), size: 18),
      ),
      title: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: const Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(
          val,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }



  Widget _buildModernBottomNav() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Selector<int>: ONLY rebuilds when the notification badge count changes.
    // Previously Consumer<BusStore> caused the entire bottom nav (and Scaffold)
    // to rebuild on every bus GPS update — the root cause of navigation jank.
    return Selector<BusStore, int>(
      selector: (_, store) => store.unreadCount,
      builder: (context, unreadCount, _) {
        return Container(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPadding > 0 ? bottomPadding : 16),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.explore_rounded, 'TRACK', 0),
              _buildNavItem(1, Icons.notifications_rounded, 'ALERTS', unreadCount),
              _buildNavItem(2, Icons.person_rounded, 'PROFILE', 0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, int badge) {
    bool isSel = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: 300.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSel ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSel ? Border.all(color: AppColors.primary.withValues(alpha: 0.35)) : null,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: isSel ? AppColors.primary : AppColors.textMuted, size: 22),
                if (badge > 0)
                  Positioned(
                    top: -4, right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
              ],
            ),
            if (isSel) ...[
              const SizedBox(width: 8),
              Text(
                label, 
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white, 
                  fontWeight: FontWeight.w900, 
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _triggerSOS(AuthService auth) async {
    if (_isSosActive) return;
    setState(() => _isSosActive = true);

    // Cache BEFORE any awaits
    final socketService = context.read<SocketService>();

    try {
      Position pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      socketService.emitSOSAlert({
        'name': auth.currentUser?.username ?? 'Guest',
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('EMERGENCY SOS SENT!'), backgroundColor: Colors.red));
    } catch (e) {
      debugPrint('SOS Error: $e');
    } finally {
      if (mounted) setState(() => _isSosActive = false);
    }
  }

  void _showRouteSelection() {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available Shuttle Routes',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontSize: 17,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select your route to synchronize GPS',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedRoute != null)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedRoute = null;
                            _activeBus = null;
                          });
                          Navigator.pop(context);
                        },
                        child: Text(
                          'CLEAR',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: TextField(
                    onChanged: (v) => setModalState(() => searchQuery = v),
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search routes or pickup stops...',
                      hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 13),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      icon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final busStore = Provider.of<BusStore>(context, listen: false);
                    final filteredRoutes = _routes.where((r) => r.matches(searchQuery)).toList();
                    filteredRoutes.sort((a, b) {
                      final aLive = busStore.allBuses.any((x) =>
                        x.status.toLowerCase().trim() != 'offline' &&
                        ((x.routeId.isNotEmpty && x.routeId.trim() == a.id.trim()) ||
                         (x.routeName.isNotEmpty && x.routeName.trim().toLowerCase() == a.name.trim().toLowerCase()))
                      );
                      final bLive = busStore.allBuses.any((x) =>
                        x.status.toLowerCase().trim() != 'offline' &&
                        ((x.routeId.isNotEmpty && x.routeId.trim() == b.id.trim()) ||
                         (x.routeName.isNotEmpty && x.routeName.trim().toLowerCase() == b.name.trim().toLowerCase()))
                      );
                      if (aLive && !bLive) return -1;
                      if (!aLive && bLive) return 1;
                      return 0;
                    });

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      itemCount: filteredRoutes.length,
                      itemBuilder: (context, i) {
                        final route = filteredRoutes[i];
                        final isSel = _selectedRoute?.id == route.id;
                        final hasLiveBus = busStore.allBuses.any((x) =>
                          x.status.toLowerCase().trim() != 'offline' &&
                          ((x.routeId.isNotEmpty && x.routeId.trim() == route.id.trim()) ||
                           (x.routeName.isNotEmpty && x.routeName.trim().toLowerCase() == route.name.trim().toLowerCase()))
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: isSel 
                              ? AppColors.primary.withValues(alpha: 0.12) 
                              : (hasLiveBus ? AppColors.accentGreen.withValues(alpha: 0.05) : AppColors.surface),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSel 
                                ? AppColors.primary.withValues(alpha: 0.40) 
                                : (hasLiveBus ? AppColors.accentGreen.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              onTap: () async {
                                _changeSelectedRoute(route);
                                try {
                                  const storage = FlutterSecureStorage();
                                  await storage.write(key: 'last_selected_route_id', value: route.id);
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('last_selected_route_id', route.id);
                                } catch (_) {}
                                if (context.mounted) Navigator.pop(context);
                              },
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: (isSel ? AppColors.primary : (hasLiveBus ? AppColors.accentGreen : AppColors.surfaceLight)).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (isSel ? AppColors.primaryLight : (hasLiveBus ? AppColors.accentGreen : Colors.white.withValues(alpha: 0.1))),
                                    width: 1.0,
                                  ),
                                ),
                                child: Center(
                                  child: route.busNumber.isNotEmpty
                                      ? Text(
                                          route.busNumber.replaceAll('BUS ', '').replaceAll('Bus ', ''),
                                          style: GoogleFonts.plusJakartaSans(
                                            color: isSel ? AppColors.primaryLight : (hasLiveBus ? AppColors.accentGreen : Colors.white),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                          ),
                                        )
                                      : Icon(
                                          Icons.directions_bus_rounded,
                                          color: isSel ? AppColors.primaryLight : (hasLiveBus ? AppColors.accentGreen : AppColors.textMuted),
                                          size: 20,
                                        ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  if (route.busNumber.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        route.busNumber,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppColors.primaryLight,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      route.corridorName,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${route.stops.length} STOPS • 09:00 AM ROSTER',
                                style: GoogleFonts.plusJakartaSans(
                                  color: isSel ? AppColors.primaryLight : AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasLiveBus) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentGreen.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: AppColors.accentGreen,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'LIVE',
                                            style: GoogleFonts.plusJakartaSans(
                                              color: AppColors.accentGreen,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  isSel 
                                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryLight, size: 20)
                                    : const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: (i * 25).ms).slideX(begin: 0.04);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopsList() {
    if (_selectedRoute == null || _selectedRoute!.stops.isEmpty) {
      return const SizedBox.shrink();
    }

    final auth = Provider.of<AuthService>(context, listen: false);
    final busStore = Provider.of<BusStore>(context, listen: false);
    final userPickup = auth.currentUser?.pickupPoint?.toLowerCase().trim() ?? '';
    final isDropoff = _shiftTimelineDirection == 'dropoff';

    // Resolve active bus for this route if available and live
    Bus? activeBus;
    for (final bus in busStore.allBuses) {
      if (bus.routeId == _selectedRoute!.id ||
          (bus.routeName.isNotEmpty && (
            bus.routeName.toLowerCase() == _selectedRoute!.name.toLowerCase() ||
            bus.routeName.toLowerCase().contains(_selectedRoute!.name.toLowerCase()) ||
            _selectedRoute!.name.toLowerCase().contains(bus.routeName.toLowerCase())
          ))) {
        activeBus = bus;
        break;
      }
    }
    final isBusLive = activeBus != null && activeBus.isBroadcastingLive;

    // In morning (Shift 1 / Pickup): Stops -> Campus (regular order)
    // In 2nd shift (Shift 2+ / Dropoff): Campus -> Stops (reversed order)
    final List<Map<String, dynamic>> displayedStops = isDropoff 
        ? _selectedRoute!.stops.reversed.toList() 
        : _selectedRoute!.stops;
    final int totalStops = displayedStops.length;

    final String firstStopName = displayedStops.first['name']?.toString() ?? 'Origin';
    final String lastStopName = displayedStops.last['name']?.toString() ?? 'Destination';

    // ── Real-Time Positioning & Telemetry Math ──────────────────────
    int nextStopIndex = 0;
    if (isBusLive) {
      int? matchedIndex;

      // 1. Match by bus.nextStop
      if (activeBus.nextStop != null && activeBus.nextStop!.trim().isNotEmpty) {
        final target = activeBus.nextStop!.trim().toLowerCase();
        for (int i = 0; i < totalStops; i++) {
          final sName = (displayedStops[i]['name'] ?? '').toString().trim().toLowerCase();
          if (sName == target || sName.contains(target) || target.contains(sName)) {
            matchedIndex = i;
            break;
          }
        }
      }

      // 2. Match by first ETA stop
      if (matchedIndex == null && activeBus.etas.isNotEmpty) {
        final target = activeBus.etas.first.stopName.trim().toLowerCase();
        for (int i = 0; i < totalStops; i++) {
          final sName = (displayedStops[i]['name'] ?? '').toString().trim().toLowerCase();
          if (sName == target || sName.contains(target) || target.contains(sName)) {
            matchedIndex = i;
            break;
          }
        }
      }

      // 3. Match by first unreached stop in order
      if (matchedIndex == null && activeBus.reachedStops.isNotEmpty) {
        for (int i = 0; i < totalStops; i++) {
          final sName = (displayedStops[i]['name'] ?? '').toString().trim().toLowerCase();
          final reached = activeBus.reachedStops.any((r) {
            final rTrim = r.trim().toLowerCase();
            return rTrim == sName || sName.contains(rTrim) || rTrim.contains(sName);
          });
          if (!reached) {
            matchedIndex = i;
            break;
          }
        }
      }

      // 4. Match by closest GPS distance
      if (matchedIndex == null) {
        double minDistance = double.infinity;
        int closestIndex = 0;
        for (int i = 0; i < totalStops; i++) {
          final lat = (displayedStops[i]['lat'] as num?)?.toDouble();
          final lng = (displayedStops[i]['lng'] as num?)?.toDouble();
          if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
            final d = Geolocator.distanceBetween(activeBus.currentLat, activeBus.currentLng, lat, lng);
            if (d < minDistance) {
              minDistance = d;
              closestIndex = i;
            }
          }
        }
        matchedIndex = closestIndex;
      }

      nextStopIndex = matchedIndex.clamp(0, totalStops);
    }

    final double busSpeedKmh = (activeBus != null && activeBus.speed > 5) ? activeBus.speed : 25.0;
    final double busSpeedMps = (busSpeedKmh * 1000) / 3600;

    String formatDistance(double meters) {
      if (meters < 1000) {
        return '${meters.toStringAsFixed(0)} m';
      } else {
        return '${(meters / 1000).toStringAsFixed(1)} km';
      }
    }

    // Distance to next upcoming stop
    double distToNextMeters = 500;
    int etaToNextMins = 2;

    if (isBusLive && nextStopIndex < totalStops) {
      final nextStop = displayedStops[nextStopIndex];
      final nextLat = (nextStop['lat'] as num?)?.toDouble();
      final nextLng = (nextStop['lng'] as num?)?.toDouble();

      if (activeBus.distanceToNextStopMeters != null && activeBus.distanceToNextStopMeters! > 0) {
        distToNextMeters = activeBus.distanceToNextStopMeters!.toDouble();
      } else if (nextLat != null && nextLng != null && nextLat != 0.0 && nextLng != 0.0) {
        distToNextMeters = Geolocator.distanceBetween(
          activeBus.currentLat, activeBus.currentLng, nextLat, nextLng,
        );
      }

      // Match ETA
      for (final e in activeBus.etas) {
        final eName = e.stopName.trim().toLowerCase();
        final sName = (nextStop['name'] ?? '').toString().trim().toLowerCase();
        if (eName == sName || sName.contains(eName) || eName.contains(sName)) {
          etaToNextMins = e.minutes;
          break;
        }
      }
      if (etaToNextMins <= 0) {
        etaToNextMins = math.max(1, (distToNextMeters / busSpeedMps / 60).round());
      }
    }

    double getDistanceToStop(int index) {
      if (!isBusLive || activeBus == null) return 0.0;
      if (index < nextStopIndex) return 0.0;
      if (index == nextStopIndex) return distToNextMeters;

      double cumDist = distToNextMeters;
      for (int j = nextStopIndex; j < index; j++) {
        final aLat = (displayedStops[j]['lat'] as num?)?.toDouble();
        final aLng = (displayedStops[j]['lng'] as num?)?.toDouble();
        final bLat = (displayedStops[j + 1]['lat'] as num?)?.toDouble();
        final bLng = (displayedStops[j + 1]['lng'] as num?)?.toDouble();
        if (aLat != null && aLng != null && bLat != null && bLng != null && aLat != 0 && bLat != 0) {
          cumDist += Geolocator.distanceBetween(aLat, aLng, bLat, bLng);
        } else {
          cumDist += 850;
        }
      }
      return cumDist;
    }

    int getEtaMinutesToStop(int index) {
      if (!isBusLive || activeBus == null) return 0;
      if (index < nextStopIndex) return 0;
      if (index == nextStopIndex) return etaToNextMins;

      final sName = (displayedStops[index]['name'] ?? '').toString().trim().toLowerCase();
      for (final e in activeBus.etas) {
        final eName = e.stopName.trim().toLowerCase();
        if (eName == sName || sName.contains(eName) || eName.contains(sName)) {
          return e.minutes;
        }
      }

      final totalDist = getDistanceToStop(index);
      return math.max(1, (totalDist / busSpeedMps / 60).round());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Route & Stops',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Text(
                    '$totalStops stops',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (isBusLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'LIVE PROGRESS',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.accentGreen,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 12),

        // ── iOS Style Segmented Shift Pill Switcher ──
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              // Morning Shift Tab
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _shiftTimelineDirection = 'pickup');
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !isDropoff ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: !isDropoff 
                          ? Border.all(color: AppColors.primaryLight.withValues(alpha: 0.25))
                          : null,
                      boxShadow: !isDropoff ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wb_sunny_rounded,
                          size: 13,
                          color: !isDropoff ? AppColors.primaryLight : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Morning Shift',
                              style: GoogleFonts.plusJakartaSans(
                                color: !isDropoff ? Colors.white : AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: !isDropoff ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            Text(
                              'To Campus',
                              style: GoogleFonts.plusJakartaSans(
                                color: !isDropoff ? AppColors.primaryLight : AppColors.textDisabled,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
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

              // Return / Afternoon Shift Tab
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _shiftTimelineDirection = 'dropoff');
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isDropoff ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: isDropoff 
                          ? Border.all(color: AppColors.accent.withValues(alpha: 0.35))
                          : null,
                      boxShadow: isDropoff ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ] : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.nights_stay_rounded,
                          size: 13,
                          color: isDropoff ? AppColors.accent : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Return Shift',
                              style: GoogleFonts.plusJakartaSans(
                                color: isDropoff ? Colors.white : AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: isDropoff ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            Text(
                              'To City / Stops',
                              style: GoogleFonts.plusJakartaSans(
                                color: isDropoff ? AppColors.accent : AppColors.textDisabled,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
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
        ),

        // Elegant Direction Sub-Header Breadcrumb
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          child: Row(
            children: [
              Icon(
                isDropoff ? Icons.flight_takeoff_rounded : Icons.explore_rounded,
                size: 13,
                color: isDropoff ? AppColors.accent : AppColors.primaryLight,
              ),
              const SizedBox(width: 6),
              Text(
                isDropoff ? 'Campus' : firstStopName,
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 11, color: AppColors.textDisabled),
              ),
              Expanded(
                child: Text(
                  isDropoff ? lastStopName : 'SISTec Campus',
                  style: GoogleFonts.plusJakartaSans(
                    color: isDropoff ? AppColors.accent : AppColors.primaryLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // ── Vertical Stops Timeline ──────────────────────────────────
        ..._buildVerticalTimelineNodes(
          displayedStops: displayedStops,
          totalStops: totalStops,
          isBusLive: isBusLive,
          activeBus: activeBus,
          nextStopIndex: nextStopIndex,
          userPickup: userPickup,
          isDropoff: isDropoff,
          distToNextMeters: distToNextMeters,
          etaToNextMins: etaToNextMins,
          formatDistance: formatDistance,
          getDistanceToStop: getDistanceToStop,
          getEtaMinutesToStop: getEtaMinutesToStop,
        ),
      ],
    );
  }

  List<Widget> _buildVerticalTimelineNodes({
    required List<Map<String, dynamic>> displayedStops,
    required int totalStops,
    required bool isBusLive,
    required Bus? activeBus,
    required int nextStopIndex,
    required String userPickup,
    required bool isDropoff,
    required double distToNextMeters,
    required int etaToNextMins,
    required String Function(double) formatDistance,
    required double Function(int) getDistanceToStop,
    required int Function(int) getEtaMinutesToStop,
  }) {
    final List<Widget> items = [];

    for (int index = 0; index < totalStops; index++) {
      // If the bus is live and approaching this stop, insert the Live Bus Node on the track
      if (isBusLive && activeBus != null && index == nextStopIndex) {
        final nextStopName = displayedStops[index]['name']?.toString() ?? 'Next Stop';
        items.add(
          _buildLiveBusTrackItem(
            bus: activeBus,
            nextStopName: nextStopName,
            distMeters: distToNextMeters,
            etaMinutes: etaToNextMins,
            formatDistance: formatDistance,
          ),
        );
      }

      final stop = displayedStops[index];
      final stopName = stop['name']?.toString() ?? 'Stop ${index + 1}';
      final schedTime = TimetableResolver.getScheduledTimeForStop(_selectedRoute?.name, stopName);
      final isFirst = index == 0;
      final isLast = index == totalStops - 1;
      final isUserStop = userPickup.isNotEmpty &&
          (stopName.toLowerCase().trim() == userPickup ||
           stopName.toLowerCase().contains(userPickup) ||
           userPickup.contains(stopName.toLowerCase().trim()));

      final bool hasPassed = isBusLive 
          ? (index < nextStopIndex || (activeBus != null && activeBus.reachedStops.any((s) => s.toLowerCase().trim() == stopName.toLowerCase().trim())))
          : false;

      final bool isNextStop = isBusLive && (index == nextStopIndex);

      final double distMeters = getDistanceToStop(index);
      final int stopEtaMins = getEtaMinutesToStop(index);

      Color nodeColor;
      String subtitle;
      IconData? nodeIcon;

      if (isUserStop) {
        nodeColor = isDropoff ? AppColors.accent : AppColors.primary;
        subtitle = hasPassed
            ? 'Your Assigned Stop • Passed'
            : (isNextStop
                ? 'Your Assigned Stop • Arriving Next (~$stopEtaMins min)'
                : 'Your Assigned Stop • ~${formatDistance(distMeters)} away');
        nodeIcon = isDropoff ? Icons.location_on_rounded : Icons.my_location_rounded;
      } else if (hasPassed) {
        nodeColor = const Color(0xFF64748B);
        subtitle = 'Departed / Passed';
        nodeIcon = Icons.check_rounded;
      } else if (isNextStop) {
        nodeColor = AppColors.accentGreen;
        subtitle = stopEtaMins <= 1
            ? 'Approaching Now • Next Stop' 
            : 'Next Stop • ${formatDistance(distMeters)} away';
        nodeIcon = Icons.navigation_rounded;
      } else if (isFirst) {
        nodeColor = isDropoff ? AppColors.accentGreen : AppColors.primaryLight;
        subtitle = isDropoff ? 'Campus Terminal • Departure Origin' : 'Origin • Stop 1';
        nodeIcon = isDropoff ? Icons.school_rounded : Icons.play_arrow_rounded;
      } else if (isLast) {
        nodeColor = isDropoff ? AppColors.accent : AppColors.accentGreen;
        subtitle = isDropoff ? 'Final Terminal Drop-off' : 'Destination • SISTec Campus';
        nodeIcon = isDropoff ? Icons.flag_rounded : Icons.school_rounded;
      } else {
        nodeColor = const Color(0xFF475569);
        subtitle = isBusLive 
            ? 'Transit Stop ${index + 1} • ${formatDistance(distMeters)} away'
            : 'Transit Stop ${index + 1}';
        nodeIcon = null;
      }

      items.add(
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            final sLat = (stop['lat'] as num?)?.toDouble();
            final sLng = (stop['lng'] as num?)?.toDouble();

            if (sLat != null && sLng != null && sLat != 0.0 && sLng != 0.0) {
              // Smoothly glide Google Map to the chosen stop
              _busMapKey.currentState?.focusOnCoordinates(
                LatLng(sLat, sLng),
                name: stopName,
                zoom: 16.8,
              );

              // Seamlessly retract bottom sheet so commuter sees the map zoom
              if (_sheetController.isAttached) {
                _sheetController.animateTo(
                  0.35,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              }
            }

            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFF00E5FF), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isBusLive && !hasPassed
                            ? '$stopName: ${formatDistance(distMeters)} away • ETA ~$stopEtaMins min'
                            : '$stopName • Stop ${index + 1}',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.bgSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                ),
              ),
            );
          },
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Vertical Rail Node Column
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: (isUserStop || isFirst || isLast || isNextStop) ? 18 : 12,
                        height: (isUserStop || isFirst || isLast || isNextStop) ? 18 : 12,
                        decoration: BoxDecoration(
                          color: (isFirst || isLast || isUserStop || isNextStop || hasPassed) ? nodeColor : AppColors.surface,
                          border: Border.all(color: nodeColor, width: isUserStop ? 2.5 : 2),
                          shape: BoxShape.circle,
                          boxShadow: (isUserStop || isNextStop) ? [
                            BoxShadow(
                              color: nodeColor.withValues(alpha: 0.4),
                              blurRadius: 7,
                              spreadRadius: 1,
                            ),
                          ] : null,
                        ),
                        child: nodeIcon != null
                            ? Center(
                                child: Icon(nodeIcon, size: 9, color: Colors.white),
                              )
                            : (isUserStop
                                ? const Center(
                                    child: Icon(Icons.circle, size: 4, color: Colors.white),
                                  )
                                : null),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: hasPassed 
                                ? const Color(0xFF334155) 
                                : const Color(0xFF1E293B),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Stop Info Card
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: (isUserStop || isNextStop)
                        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                        : const EdgeInsets.symmetric(vertical: 2),
                    decoration: isUserStop
                        ? BoxDecoration(
                            color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          )
                        : (isNextStop
                            ? BoxDecoration(
                                color: AppColors.accentGreen.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.accentGreen.withValues(alpha: 0.45),
                                  width: 1.2,
                                ),
                              )
                            : null),
                    child: Row(
                      children: [
                        // Stop Name & Subtitle
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
                                        color: isUserStop 
                                            ? Colors.white 
                                            : (hasPassed 
                                                ? const Color(0xFF94A3B8) 
                                                : (isNextStop ? AppColors.accentGreen : AppColors.text)),
                                        fontSize: 13.5,
                                        fontWeight: (isUserStop || isNextStop) ? FontWeight.w800 : FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: GoogleFonts.plusJakartaSans(
                                  color: isUserStop 
                                      ? (isDropoff ? AppColors.accent : AppColors.primaryLight) 
                                      : (isNextStop 
                                          ? AppColors.accentGreen.withValues(alpha: 0.9) 
                                          : AppColors.textMuted),
                                  fontSize: 10,
                                  fontWeight: (isUserStop || isNextStop) ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Badges on Right
                        if (schedTime != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.schedule_rounded, size: 10, color: AppColors.primaryLight),
                                const SizedBox(width: 3),
                                Text(
                                  schedTime,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (isUserStop) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              isDropoff ? 'MY DROP-OFF' : 'MY PICKUP',
                              style: GoogleFonts.plusJakartaSans(
                                color: isDropoff ? AppColors.accent : AppColors.primaryLight,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],

                        if (isBusLive) ...[
                          if (hasPassed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 10, color: Color(0xFF64748B)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'PASSED',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFF94A3B8),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (isNextStop || stopEtaMins <= 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentGreen.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.accentGreen,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    stopEtaMins <= 1 ? 'ARRIVING' : '$stopEtaMins MIN',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.accentGreen,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                '~$stopEtaMins MIN',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primaryLight,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If bus completed all stops, render arrival card at the bottom
    if (isBusLive && activeBus != null && nextStopIndex >= totalStops) {
      items.add(
        _buildLiveBusTrackItem(
          bus: activeBus,
          nextStopName: displayedStops.last['name']?.toString() ?? 'Campus Terminal',
          distMeters: 0,
          etaMinutes: 0,
          formatDistance: formatDistance,
          isCompleted: true,
        ),
      );
    }

    return items;
  }

  Widget _buildLiveBusTrackItem({
    required Bus bus,
    required String nextStopName,
    required double distMeters,
    required int etaMinutes,
    required String Function(double) formatDistance,
    bool isCompleted = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _busMapKey.currentState?.focusOnCoordinates(
          LatLng(bus.currentLat, bus.currentLng),
          name: 'Bus ${bus.displayBusNumber}',
          zoom: 17.2,
        );
        if (_sheetController.isAttached) {
          _sheetController.animateTo(
            0.35,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Rail vehicle marker
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 2.5,
                      height: 10,
                      color: const Color(0xFF00E5FF),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF00E5FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.directions_bus_rounded, size: 13, color: Colors.white),
                      ),
                    ).animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
                     .scaleXY(begin: 0.94, end: 1.08, duration: 900.ms, curve: Curves.easeInOut),
                    Expanded(
                      child: Container(
                        width: 2.5,
                        color: const Color(0xFF00E5FF),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 14),

            // Live In-Transit Vehicle Card
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isCompleted 
                                  ? 'BUS ${bus.displayBusNumber} • TRIP COMPLETED'
                                  : 'BUS ${bus.displayBusNumber} • LIVE EN ROUTE',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF38BDF8),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.speed_rounded, size: 10, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 4),
                              Text(
                                '${bus.speed > 1 ? bus.speed.toStringAsFixed(0) : '0'} km/h',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF38BDF8),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          isCompleted ? Icons.check_circle_outline_rounded : Icons.near_me_rounded, 
                          size: 13, 
                          color: isCompleted ? AppColors.accentGreen : const Color(0xFF38BDF8),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            isCompleted ? 'Arrived at $nextStopName' : 'En route to $nextStopName',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (!isCompleted) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${formatDistance(distMeters)} away • ETA ~$etaMinutes min',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF94A3B8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2D5BFF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2D5BFF).withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F0FF)),
                ),
                const SizedBox(width: 10),
                Text(
                  'Connecting to SISTec Cloud...',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF00F0FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Shimmer.fromColors(
              baseColor: Colors.white.withValues(alpha: 0.05),
              highlightColor: Colors.white.withValues(alpha: 0.1),
              child: Column(
                children: List.generate(
                  4,
                  (i) => Container(
                    height: 90,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProximityPreferencesSection extends StatefulWidget {
  final AuthService auth;
  final User? user;

  const _ProximityPreferencesSection({
    required this.auth,
    required this.user,
  });

  @override
  State<_ProximityPreferencesSection> createState() => _ProximityPreferencesSectionState();
}

class _ProximityPreferencesSectionState extends State<_ProximityPreferencesSection> {
  late bool _enabled;
  late double _radiusKm;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _enabled = widget.user?.proximityAlertsEnabled ?? true;
    _radiusKm = (widget.user?.proximityRadiusKm ?? 1.0).clamp(0.5, 3.0);
  }

  @override
  void didUpdateWidget(covariant _ProximityPreferencesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_debounceTimer == null || !_debounceTimer!.isActive) {
      if (widget.user != null) {
        _enabled = widget.user!.proximityAlertsEnabled;
        _radiusKm = widget.user!.proximityRadiusKm.clamp(0.5, 3.0);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleToggle(bool newVal) {
    HapticFeedback.mediumImpact();
    setState(() {
      _enabled = newVal;
    });
    widget.auth.updateProximityAlerts(newVal);
  }

  void _handleRadiusChanged(double val) {
    final rounded = ((val * 2).round() / 2).clamp(0.5, 3.0);
    if (rounded != _radiusKm) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _radiusKm = rounded;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      widget.auth.updateProximityRadius(_radiusKm);
    });
  }

  void _handleRadiusEnd(double val) {
    _debounceTimer?.cancel();
    final rounded = ((val * 2).round() / 2).clamp(0.5, 3.0);
    widget.auth.updateProximityRadius(rounded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // PROXIMITY ALERTS TOGGLE ROW
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          onTap: () => _handleToggle(!_enabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROXIMITY ALERTS',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _enabled ? 'Notify when bus enters your zone' : 'Notifications disabled',
                        style: GoogleFonts.plusJakartaSans(
                          color: _enabled ? const Color(0xFF60A5FA) : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _CleanToggleSwitch(
                  value: _enabled,
                  onChanged: _handleToggle,
                ),
              ],
            ),
          ),
        ),

        // RADIUS CONTROLLER (Animated CrossFade)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _enabled ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ALERT RADIUS',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${_radiusKm.toStringAsFixed(1)} KM',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF60A5FA),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: const Color(0xFF2563EB),
                    inactiveTrackColor: const Color(0xFF334155),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2),
                    overlayColor: Colors.transparent,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    valueIndicatorColor: const Color(0xFF2563EB),
                    valueIndicatorTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  child: Slider(
                    value: _radiusKm,
                    min: 0.5,
                    max: 3.0,
                    divisions: 5,
                    onChanged: _handleRadiusChanged,
                    onChangeEnd: _handleRadiusEnd,
                  ),
                ),
                const SizedBox(height: 6),
                // QUICK RADIUS PRESET PILLS (Expanded to prevent overflow)
                Row(
                  children: [0.5, 1.0, 1.5, 2.0, 3.0].map((preset) {
                    final isSelected = (_radiusKm - preset).abs() < 0.05;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _handleRadiusChanged(preset);
                            _handleRadiusEnd(preset);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF60A5FA) : const Color(0xFF334155),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${preset.toStringAsFixed(1)}k',
                              style: GoogleFonts.plusJakartaSans(
                                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CleanToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CleanToggleSwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onChanged(!value);
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          HapticFeedback.lightImpact();
          if (details.primaryVelocity! > 25) {
            onChanged(true);
          } else if (details.primaryVelocity! < -25) {
            onChanged(false);
          } else {
            onChanged(!value);
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? const Color(0xFF2563EB) : const Color(0xFF334155),
          border: Border.all(
            color: value ? const Color(0xFF60A5FA).withValues(alpha: 0.5) : const Color(0xFF475569),
            width: 1.2,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



