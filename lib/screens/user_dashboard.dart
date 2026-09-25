import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/bus_store.dart';
import '../components/bus_map.dart';
import '../components/linear_tracking_view.dart';
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
import '../components/update_dialog.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final ApiService _apiService = ApiService();
  
  List<RouteModel> _routes = [];
  bool _isLoading = true;
  RouteModel? _selectedRoute;
  Bus? _activeBus;
  String? _selectedShiftFilter;
  String _shiftTimelineDirection = (DateTime.now().hour < 12) ? 'pickup' : 'dropoff';
  int _currentIndex = 0;
  bool _showDebugOverlay = false;
  int _tapCounter = 0;
  
  bool _isSosActive = false;

  bool _isDriveMode = false;
  int? _etaMinutes;          // ETA to user's assigned pickup stop
  bool _etaLoading = false;
  bool _delaySubscribed = false; // Whether user subscribed to delay alerts

  @override
  void initState() {
    super.initState();
    _fetchData();
    _initSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForAppUpdate(context);
    });
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

    return Scaffold(
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
        ],
      ),
      bottomNavigationBar: _buildModernBottomNav(), // Selector<BusStore,int>
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
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 4),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _tapCounter++;
                      if (_tapCounter >= 3) {
                        setState(() => _showDebugOverlay = !_showDebugOverlay);
                        _tapCounter = 0;
                      }
                      Future.delayed(1.seconds, () => _tapCounter = 0);
                    },
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SISTEC SHUTTLE',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
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
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _selectedRoute?.name ?? 'Tap ⇄ to select route',
                              style: GoogleFonts.plusJakartaSans(
                                color: _selectedRoute != null ? Colors.white : AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showRouteSelection,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onLongPress: () => _triggerSOS(auth),
                  onTap: () {
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
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.emergency_rounded, color: AppColors.danger, size: 19),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _handleLogout(context, auth),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: auth.isGuest
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                          : const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: auth.isGuest
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
                            : const Color(0xFFEF4444).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      auth.isGuest ? Icons.login_rounded : Icons.logout_rounded,
                      color: auth.isGuest ? const Color(0xFF60A5FA) : const Color(0xFFF87171),
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1),
      );
    }

  Widget _buildTrackingTab() {
    final auth = Provider.of<AuthService>(context, listen: false);

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

        return Stack(
          children: [
            BusMap(
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
              initialChildSize: 0.28,
              minChildSize: 0.14,
              maxChildSize: 0.82,
              snap: true,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedRoute!.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.visible,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (currentActiveBus != null && currentActiveBus.isBroadcastingLive) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentGreen.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(20),
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
                                            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(duration: 800.ms, begin: const Offset(0.8, 0.8), end: const Offset(1.3, 1.3)),
                                            const SizedBox(width: 6),
                                            Text(
                                              'LIVE',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.accentGreen,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceLight,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: const BoxDecoration(
                                                color: AppColors.textMuted,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'OFFLINE',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textMuted,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    // Manager Assigned Bus Number Pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                      ),
                                      child: Text(
                                        _getAssignedBusLabel(store),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryLight,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                    // Current Day & Shift Tag
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 11),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${_getCurrentDayLabel()} • ${_getAssignedShiftLabel()}',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textSecondary,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Realtime telemetry status pill
                          ValueListenableBuilder<DateTime?>(
                            valueListenable: Provider.of<SocketService>(context, listen: false).lastDataReceived,
                            builder: (context, lastPacket, _) {
                              final isRecent = currentActiveBus != null &&
                                  currentActiveBus.isBroadcastingLive &&
                                  lastPacket != null && 
                                  DateTime.now().difference(lastPacket).inSeconds < 25;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isRecent ? AppColors.accentGreen.withValues(alpha: 0.14) : AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isRecent ? AppColors.accentGreen.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isRecent ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                                      color: isRecent ? AppColors.accentGreen : AppColors.textMuted,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isRecent ? 'CONNECTED' : 'STANDBY',
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
                      const SizedBox(height: 24),
                      if (currentActiveBus != null && currentActiveBus.isBroadcastingLive) ...[
                        LinearTrackingView(
                          bus: currentActiveBus, 
                          route: _selectedRoute!,
                          shiftDirection: _shiftTimelineDirection,
                        ),
                        const SizedBox(height: 24),
                        _buildStopsList(),
                      ] else
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
    if (_selectedShiftFilter != null) {
      return TimetableResolver.resolveShiftLabel(
        explicitShift: _selectedShiftFilter,
        routeName: _selectedRoute?.name,
      );
    }
    if (_activeBus != null) {
      return _activeBus!.shiftLabel;
    }
    if (_selectedRoute != null) {
      return TimetableResolver.resolveShiftLabel(
        routeName: _selectedRoute!.name,
        currentHour: DateTime.now().hour,
      );
    }
    return TimetableResolver.resolveShiftLabel();
  }

  String _getCurrentDayLabel() {
    return TimetableResolver.getCurrentDayLabel();
  }

  void _showShiftAllocationModal(BusStore busStore) {
    HapticFeedback.mediumImpact();
    final routeName = _selectedRoute?.name ?? 'SISTec Transit Route';
    final availableShifts = TimetableResolver.getShiftsForRoute(routeName);
    final currentDay = TimetableResolver.getCurrentDayLabel();

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
            final distM = Geolocator.distanceBetween(
              bus.currentLat, bus.currentLng,
              (stop['lat'] as num).toDouble(), (stop['lng'] as num).toDouble(),
            );
            final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
            final speedMps = (speedKmh * 1000) / 3600;
            mins = math.max(1, (distM / speedMps / 60).round());
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
            final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
            final speedMps = (speedKmh * 1000) / 3600;
            mins = math.max(1, (bus.distanceToNextStopMeters! / speedMps / 60).round());
          }
        }

        // If still not resolved, determine from route stops
        if (mins == null && _selectedRoute != null && _selectedRoute!.stops.isNotEmpty) {
          final unreached = _selectedRoute!.stops.where((s) {
            final sName = (s['name'] ?? '').toString();
            return !bus.reachedStops.contains(sName);
          }).toList();
          final candidateStop = unreached.isNotEmpty ? unreached.first : _selectedRoute!.stops.first;
          targetStopLabel = (candidateStop['name'] ?? 'CAMPUS TERMINAL').toString().toUpperCase();
          if (candidateStop['lat'] != null && candidateStop['lng'] != null) {
            final distM = Geolocator.distanceBetween(
              bus.currentLat, bus.currentLng,
              (candidateStop['lat'] as num).toDouble(), (candidateStop['lng'] as num).toDouble(),
            );
            final speedKmh = bus.speed > 5 ? bus.speed : 25.0;
            final speedMps = (speedKmh * 1000) / 3600;
            mins = math.max(1, (distM / speedMps / 60).round());
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
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Status chip + Manager Bus Pill + Shift + Refresh action
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isLive 
                              ? AppColors.accentGreen.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isLive ? AppColors.accentGreen.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isLive ? AppColors.accentGreen : AppColors.textMuted,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isLive ? 'LIVE' : 'SCHEDULED',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isLive ? AppColors.accentGreen : AppColors.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showShiftAllocationModal(busStore),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.directions_bus_rounded, size: 11, color: isLive ? AppColors.accentGreen : AppColors.primaryLight),
                              const SizedBox(width: 4),
                              Text(
                                _getAssignedBusLabel(busStore),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: isLive ? AppColors.accentGreen : AppColors.primaryLight,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showShiftAllocationModal(busStore),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: AppColors.bgSecondary,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule_rounded, size: 10, color: AppColors.textMuted),
                              const SizedBox(width: 3),
                              Text(
                                '${_getCurrentDayLabel()} • ${_getAssignedShiftLabel()}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasPickup && isLive)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _fetchETA();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh_rounded, color: AppColors.primaryLight, size: 16),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 14),

          // Main Hero Metrics: ETA Big Bold Typography + Speed Chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
                const Spacer(),
                // Velocity Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, color: AppColors.accent, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        isLive ? '${bus.speed.toInt()}' : '--',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'KM/H',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Assigned Stop Sub-Card inside Hero
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
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
                          ? (_shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primary) 
                          : (isLive ? AppColors.accentGreen : AppColors.primaryLight),
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          targetStopHeader,
                          style: GoogleFonts.plusJakartaSans(
                            color: (isLive && !hasPickup) ? AppColors.accentGreen : AppColors.textMuted,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          targetStopLabel,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12.5,
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
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (_shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primary).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _shiftTimelineDirection == 'dropoff' ? 'MY DROP-OFF' : 'MY STOP',
                        style: GoogleFonts.plusJakartaSans(
                          color: _shiftTimelineDirection == 'dropoff' ? AppColors.accent : AppColors.primaryLight,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else if (isLive && bus.etas.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'LIVE',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.accentGreen,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
            label: 'SCHEDULE',
            color: AppColors.primary,
            onTap: _selectedRoute != null
                ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ScheduleScreen(route: _selectedRoute!)))
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildQuickAction(
            icon: _delaySubscribed
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            label: _delaySubscribed ? 'SUBSCRIBED' : 'DELAY ALERT',
            color: _delaySubscribed ? AppColors.accentGreen : AppColors.warning,
            onTap: _delaySubscribed || _selectedRoute == null ? null : _subscribeToDelay,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildQuickAction(
            icon: Icons.report_problem_rounded,
            label: 'REPORT',
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.02)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: disabled
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: disabled
                    ? Colors.white.withValues(alpha: 0.04)
                    : color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: disabled ? AppColors.textDisabled : color,
                size: 16,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: disabled ? AppColors.textDisabled : AppColors.textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
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
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));
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
                    final filteredRoutes = _routes.where((r) => r.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
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
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: (isSel ? AppColors.primary : (hasLiveBus ? AppColors.accentGreen : AppColors.surfaceLight)).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.directions_bus_rounded,
                                  color: isSel ? AppColors.primaryLight : (hasLiveBus ? AppColors.accentGreen : AppColors.textMuted),
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      route.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${route.stops.length} STOPS • BHOPAL TRANSIT',
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
    final busStore = Provider.of<BusStore>(context);
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
    final isBusLive = activeBus != null && activeBus.status.toLowerCase() != 'offline';
    
    // In morning (Shift 1 / Pickup): Stops -> Campus (regular order)
    // In 2nd shift (Shift 2+ / Dropoff): Campus -> Stops (reversed order)
    final List<Map<String, dynamic>> displayedStops = isDropoff 
        ? _selectedRoute!.stops.reversed.toList() 
        : _selectedRoute!.stops;
    final int totalStops = displayedStops.length;

    final String firstStopName = displayedStops.first['name']?.toString() ?? 'Origin';
    final String lastStopName = displayedStops.last['name']?.toString() ?? 'Destination';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header & Shift Switcher
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDropoff ? Icons.departure_board_rounded : Icons.route_rounded,
                    color: isDropoff ? AppColors.accent : AppColors.primaryLight,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ROUTE TIMELINE',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                '$totalStops STOPS',
                style: GoogleFonts.plusJakartaSans(
                  color: isDropoff ? AppColors.accent : AppColors.primaryLight,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 14),

        // Interactive Shift Direction Segmented Toggle Bar
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: !isDropoff ? AppColors.primary.withValues(alpha: 0.20) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: !isDropoff 
                          ? Border.all(color: AppColors.primary.withValues(alpha: 0.40))
                          : null,
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
                              'MORNING SHIFT',
                              style: GoogleFonts.plusJakartaSans(
                                color: !isDropoff ? Colors.white : AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Stops ➔ Campus',
                              style: GoogleFonts.plusJakartaSans(
                                color: !isDropoff ? AppColors.primaryLight : AppColors.textDisabled,
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

              // 2nd Shift Tab (Campus -> Stops)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _shiftTimelineDirection = 'dropoff');
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isDropoff ? AppColors.accent.withValues(alpha: 0.20) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isDropoff 
                          ? Border.all(color: AppColors.accent.withValues(alpha: 0.45))
                          : null,
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
                              '2ND SHIFT / RETURN',
                              style: GoogleFonts.plusJakartaSans(
                                color: isDropoff ? Colors.white : AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Campus ➔ Stops',
                              style: GoogleFonts.plusJakartaSans(
                                color: isDropoff ? AppColors.accent : AppColors.textDisabled,
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
        ),

        const SizedBox(height: 12),

        // Direction Context Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isDropoff ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 14,
                color: isDropoff ? AppColors.accent : AppColors.primaryLight,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDropoff 
                      ? 'Drop-off Trip: SISTec Campus ➔ $lastStopName'
                      : 'Pickup Trip: $firstStopName ➔ SISTec Campus',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Stops Timeline Nodes
        ...List.generate(totalStops, (index) {
          final stop = displayedStops[index];
          final stopName = stop['name']?.toString() ?? 'Stop ${index + 1}';
          final isFirst = index == 0;
          final isLast = index == totalStops - 1;
          final isUserStop = userPickup.isNotEmpty &&
              (stopName.toLowerCase().trim() == userPickup ||
               stopName.toLowerCase().contains(userPickup) ||
               userPickup.contains(stopName.toLowerCase().trim()));

          final liveBus = isBusLive ? activeBus : null;
          final hasReached = liveBus != null && liveBus.reachedStops.any(
            (s) => s.toLowerCase().trim() == stopName.toLowerCase().trim() ||
                   stopName.toLowerCase().contains(s.toLowerCase().trim()),
          );

          BusETA? stopEta;
          if (liveBus != null && liveBus.etas.isNotEmpty) {
            for (final eta in liveBus.etas) {
              if (eta.stopName.toLowerCase().trim() == stopName.toLowerCase().trim() ||
                  stopName.toLowerCase().contains(eta.stopName.toLowerCase().trim()) ||
                  eta.stopName.toLowerCase().contains(stopName.toLowerCase().trim())) {
                stopEta = eta;
                break;
              }
            }
          }

          final isNextStop = liveBus != null && !hasReached && (
            (liveBus.nextStop != null && (
              liveBus.nextStop!.toLowerCase().trim() == stopName.toLowerCase().trim() ||
              stopName.toLowerCase().contains(liveBus.nextStop!.toLowerCase().trim())
            )) ||
            (liveBus.etas.isNotEmpty && (
              liveBus.etas.first.stopName.toLowerCase().trim() == stopName.toLowerCase().trim() ||
              stopName.toLowerCase().contains(liveBus.etas.first.stopName.toLowerCase().trim())
            ))
          );

          Color nodeColor;
          String subtitle;
          IconData? nodeIcon;

          if (isUserStop) {
            nodeColor = isDropoff ? AppColors.accent : AppColors.primary;
            subtitle = isDropoff ? 'Your Assigned Drop-off Stop' : 'Your Assigned Pickup Stop';
            nodeIcon = isDropoff ? Icons.location_on_rounded : Icons.my_location_rounded;
          } else if (hasReached) {
            nodeColor = const Color(0xFF64748B);
            subtitle = 'Departed / Passed';
            nodeIcon = Icons.check_rounded;
          } else if (isNextStop) {
            nodeColor = AppColors.accentGreen;
            subtitle = (stopEta != null && stopEta.minutes <= 1)
                ? 'Approaching Now • Next Stop' 
                : 'Next Stop on Route';
            nodeIcon = Icons.navigation_rounded;
          } else if (isFirst) {
            nodeColor = isDropoff ? AppColors.accentGreen : AppColors.primaryLight;
            subtitle = isDropoff ? 'Campus Departure • SISTec Ratibad' : 'Departure Origin • Stop 1';
            nodeIcon = isDropoff ? Icons.school_rounded : Icons.play_arrow_rounded;
          } else if (isLast) {
            nodeColor = isDropoff ? AppColors.accent : AppColors.accentGreen;
            subtitle = isDropoff ? 'Final Terminal Drop-off' : 'Destination • SISTec Campus';
            nodeIcon = isDropoff ? Icons.flag_rounded : Icons.school_rounded;
          } else {
            nodeColor = const Color(0xFF475569);
            subtitle = isDropoff ? 'Transit Drop-off Stop ${index + 1}' : 'Transit Stop ${index + 1}';
            nodeIcon = null;
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: (isUserStop || isFirst || isLast || isNextStop) ? 18 : 12,
                        height: (isUserStop || isFirst || isLast || isNextStop) ? 18 : 12,
                        decoration: BoxDecoration(
                          color: (isFirst || isLast || isUserStop || isNextStop || hasReached) ? nodeColor : AppColors.surface,
                          border: Border.all(color: nodeColor, width: isUserStop ? 3 : 2),
                          shape: BoxShape.circle,
                          boxShadow: (isUserStop || isFirst || isLast || isNextStop) ? [
                            BoxShadow(
                              color: nodeColor.withValues(alpha: 0.35),
                              blurRadius: 6,
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
                            color: hasReached 
                                ? const Color(0xFF334155) 
                                : const Color(0xFF1E293B),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: isUserStop
                        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                        : (isNextStop
                            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                            : EdgeInsets.zero),
                    decoration: isUserStop
                        ? BoxDecoration(
                            color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          )
                        : (isNextStop
                            ? BoxDecoration(
                                color: AppColors.accentGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.accentGreen.withValues(alpha: 0.3),
                                  width: 1.0,
                                ),
                              )
                            : null),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stopName,
                                style: GoogleFonts.plusJakartaSans(
                                  color: isUserStop 
                                      ? Colors.white 
                                      : (hasReached 
                                          ? const Color(0xFF94A3B8) 
                                          : (isNextStop ? AppColors.accentGreen : AppColors.text)),
                                  fontSize: 13.5,
                                  fontWeight: (isUserStop || isNextStop) ? FontWeight.w800 : FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: GoogleFonts.plusJakartaSans(
                                  color: isUserStop 
                                      ? (isDropoff ? AppColors.accent : AppColors.primaryLight) 
                                      : (isNextStop 
                                          ? AppColors.accentGreen.withValues(alpha: 0.8) 
                                          : AppColors.textMuted),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isUserStop) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (isDropoff ? AppColors.accent : AppColors.primary).withValues(alpha: 0.3),
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
                          if (hasReached)
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
                          else if (isNextStop || (stopEta != null && stopEta.minutes <= 1))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
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
                                    stopEta != null ? '${stopEta.minutes} MIN' : 'APPROACHING',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.accentGreen,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (stopEta != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '${stopEta.minutes} MIN',
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
          );
        }),
      ],
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



