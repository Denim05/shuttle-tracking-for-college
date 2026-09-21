import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
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

import 'fleet_radar_screen.dart';
import 'schedule_screen.dart';
import 'complaint_screen.dart';
import 'profile_settings_screen.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

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
  }

  Future<void> _fetchData() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final endpoint = auth.isGuest ? 'guest/routes' : 'routes';
    try {
      final List<dynamic> data = await _apiService.get(endpoint, requiresAuth: !auth.isGuest);
      if (!mounted) return;
      _routes = data.map((r) => RouteModel.fromJson(r)).toList();
      
      final busEndpoint = auth.isGuest ? 'guest/buses' : 'buses';
      final List<dynamic> busData = await _apiService.get(busEndpoint, requiresAuth: !auth.isGuest);
      if (!mounted) return;
      
      final busStore = Provider.of<BusStore>(context, listen: false);
      busStore.seedBuses(busData);

      // Read saved route preference from local storage
      String? savedRouteId;
      try {
        const storage = FlutterSecureStorage();
        savedRouteId = await storage.read(key: 'last_selected_route_id');
      } catch (_) {}

      // Smart route resolution order:
      // 1. User's profile assigned routeId
      // 2. Previously selected route saved in storage
      // 3. Route of a currently LIVE online bus
      // 4. Fallback: first route
      RouteModel? targetRoute;
      if (auth.currentUser?.routeId != null) {
        final matched = _routes.where((r) => r.id == auth.currentUser!.routeId);
        if (matched.isNotEmpty) targetRoute = matched.first;
      }
      
      if (targetRoute == null && savedRouteId != null) {
        final matched = _routes.where((r) => r.id == savedRouteId);
        if (matched.isNotEmpty) targetRoute = matched.first;
      }

      if (targetRoute == null && busStore.allBuses.isNotEmpty) {
        final onlineBuses = busStore.allBuses.where((b) => b.status != 'Offline').toList();
        if (onlineBuses.isNotEmpty) {
          final matched = _routes.where((r) => r.id == onlineBuses.first.routeId);
          if (matched.isNotEmpty) targetRoute = matched.first;
        }
      }

      targetRoute ??= (_routes.isNotEmpty ? _routes.first : null);

      setState(() {
        _selectedRoute = targetRoute;
        _isLoading = false;
        _updateActiveBus(busStore);
      });

      // Load notification history (only for logged-in users)
      if (!auth.isGuest) {
        try {
          final notifData = await _apiService.get('notifications');
          busStore.seedNotifications(notifData as List);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
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

  void _updateActiveBus(BusStore busStore) {
    if (_selectedRoute == null) {
      _activeBus = null;
      return;
    }
    
    final busesOnRoute = busStore.allBuses.where((b) => b.routeId == _selectedRoute!.id).toList();
    
    if (busesOnRoute.isEmpty) {
      _activeBus = null;
    } else {
      busesOnRoute.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      _activeBus = busesOnRoute.first;
    }
  }


  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context, listen: false);
    
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        // Compute active bus inline — always fresh on every BusStore rebuild
        if (_selectedRoute != null) {
          final busesOnRoute = busStore.allBuses
              .where((b) => b.routeId == _selectedRoute!.id)
              .toList();
          if (busesOnRoute.isEmpty) {
            _activeBus = null;
          } else {
            busesOnRoute.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
            _activeBus = busesOnRoute.first;
          }
        } else {
          _activeBus = null;
        }

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: ValueListenableBuilder<bool>(
            valueListenable: socketService.connectionStatus,
            builder: (context, isConnected, child) {
              return Stack(
                children: [
                  child!,
                  if (!isConnected)
                    Positioned(
                      top: MediaQuery.of(context).padding.top,
                      left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        color: AppColors.danger.withValues(alpha: 0.8),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 8,
                                height: 8,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'SYNCHRONIZING LIVE TRACKER...',
                                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
                    ),
                  if (_showDebugOverlay) _buildDebugOverlay(busStore),
                  if (_currentIndex == 0) _buildFloatingHeader(busStore),
                ],
              );
            },
            child: _getViewForIndex(auth, _currentIndex, busStore),
          ),
          bottomNavigationBar: _buildModernBottomNav(),
        );
      },
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary.withValues(alpha: 0.90),
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
                GestureDetector(
                  onTap: () {
                    _tapCounter++;
                    if (_tapCounter >= 3) {
                      setState(() => _showDebugOverlay = !_showDebugOverlay);
                      _tapCounter = 0;
                    }
                    Future.delayed(1.seconds, () => _tapCounter = 0);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(
                      Icons.directions_bus_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1),
    );
  }

  Widget _getViewForIndex(AuthService auth, int index, BusStore busStore) {
    switch (index) {
      case 1: return _buildAlertsTab();
      case 2: return _buildProfileTab(auth);
      default:
        if (_isLoading) {
          return Container(
            color: AppColors.bg,
            child: Center(child: _buildShimmerLoader()),
          );
        }
        return _buildTrackingTab(busStore);
    }
  }

  Widget _buildTrackingTab(BusStore busStore) {
    return Stack(
      children: [
        BusMap(
          buses: busStore.allBuses.where((b) => 
            b.routeId == _selectedRoute?.id && 
            b.status != 'Offline'
          ).toList(),
          selectedRoute: _selectedRoute,
          onDriveModeChanged: (isDrive) {
            setState(() => _isDriveMode = isDrive);
          },
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.32,
          minChildSize: 0.16,
          maxChildSize: 0.78,
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
                                  if (_activeBus != null && _activeBus!.status != 'Offline') ...[
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
                                  if (_activeBus != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                      ),
                                      child: Text(
                                        'BUS #${_activeBus!.id.substring(math.max(0, _activeBus!.id.length - 4)).toUpperCase()}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryLight,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ],
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
                            final isRecent = lastPacket != null && 
                                DateTime.now().difference(lastPacket).inSeconds < 15;
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

                    const SizedBox(height: 24),
                    _buildStatGrid(),
                    const SizedBox(height: 28),
                    if (_activeBus != null && _activeBus!.status != 'Offline')
                      LinearTrackingView(bus: _activeBus!, route: _selectedRoute!)
                    else
                      _buildStopsList(),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

  Widget _buildStatGrid() {
    final isLive = _activeBus != null && _activeBus!.status != 'Offline';
    final auth = Provider.of<AuthService>(context, listen: false);
    final hasPickup = (auth.currentUser?.pickupPoint ?? '').isNotEmpty;

    String etaDisplay = '--';
    if (_etaLoading) {
      etaDisplay = '...';
    } else if (_etaMinutes != null) {
      etaDisplay = '$_etaMinutes MIN';
    } else if (isLive) {
      if (_activeBus!.etas.isNotEmpty) {
        etaDisplay = '${_activeBus!.etas.first.minutes} MIN';
      }
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatItem(
                label: hasPickup ? 'ETA TO STOP' : 'ESTIMATED ARRIVAL',
                val: etaDisplay,
                icon: Icons.schedule_rounded,
                iconColor: AppColors.primary,
                onTapAction: (hasPickup && isLive) ? _fetchETA : null,
                actionIcon: (hasPickup && isLive) ? Icons.refresh_rounded : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatItem(
                label: 'BUS VELOCITY',
                val: isLive ? '${_activeBus!.speed.toInt()} KM/H' : '--',
                icon: Icons.speed_rounded,
                iconColor: AppColors.accent,
              ),
            ),
          ],
        ),
        if (hasPickup && _selectedRoute != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ASSIGNED PICKUP STOP',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        auth.currentUser!.pickupPoint!.toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'MY STOP',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.primaryLight,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Quick Actions Row (Equal width expanded items)
        Row(
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
      onTap: onTap,
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

  Widget _buildStatItem({
    required String label,
    required String val,
    required IconData icon,
    Color iconColor = AppColors.primary,
    VoidCallback? onTapAction,
    IconData? actionIcon,
  }) {
    return GestureDetector(
      onTap: onTapAction,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 17),
                ),
                if (actionIcon != null)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(actionIcon, color: iconColor, size: 13),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                val,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        // Mark all read when tab is open
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (busStore.unreadCount > 0) busStore.markAllRead();
        });

        final allAlerts = busStore.notifications;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 110,
              backgroundColor: AppColors.bgSecondary,
              pinned: true,
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
                        {
                          'message' : allAlerts[index].message,
                          'timestamp': allAlerts[index].timestamp.toIso8601String(),
                          'priority' : allAlerts[index].type == 'critical' ? 'critical' : 'important',
                        },
                        index,
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

  String _formatAlertTime(String? timestamp) {
    if (timestamp == null) return 'JUST NOW';
    final date = DateTime.parse(timestamp).toLocal();
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';
    return '${diff.inHours}H AGO';
  }

  Widget _buildNotificationCard(Map<String, dynamic> alert, int index) {
    final isCritical = alert['priority'] == 'critical';
    final accentColor = isCritical ? AppColors.danger : AppColors.primary;

    return Container(
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
                    Text(
                      isCritical ? 'CRITICAL ALERT' : 'TRANSIT DIRECTIVE', 
                      style: GoogleFonts.plusJakartaSans(
                        color: isCritical ? AppColors.danger : AppColors.primaryLight,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      _formatAlertTime(alert['timestamp']),
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
                  alert['message'] ?? '',
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
        ],
      ),
    ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.05);
  }

  Widget _buildProfileTab(AuthService auth) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        final displayName = _getUserDisplayName(user);
        final enrollmentId = _getEnrollmentId(user);
        final avatarInitials = _getAvatarInitials(user);
        final roleName = (user?.role ?? 'User').toUpperCase();

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
              _buildProfileTile('PICKUP', user?.pickupPoint ?? 'NOT SET', Icons.location_on_outlined),
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
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: ElevatedButton(
                onPressed: () => authService.logout(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F1D1D).withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFFF87171),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: Text(
                  'TERMINATE SESSION',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ).animate().fadeIn();
      },
    );
  }

  String _getUserDisplayName(User? user) {
    if (user == null) return 'Guest User';
    if (user.name != null && user.name!.trim().isNotEmpty && user.name!.trim().toLowerCase() != user.username.trim().toLowerCase()) {
      return user.name!.trim();
    }
    return user.username;
  }

  String _getEnrollmentId(User? user) {
    if (user == null) return '';
    return user.userId ?? user.username;
  }

  String _getAvatarInitials(User? user) {
    if (user == null) return 'G';
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
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
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
              _buildNavItem(1, Icons.notifications_rounded, 'ALERTS', busStore.unreadCount),
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
                    Column(
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
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: _routes.where((r) => r.name.toLowerCase().contains(searchQuery.toLowerCase())).length,
                  itemBuilder: (context, i) {
                    final filteredRoutes = _routes.where((r) => r.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
                    final route = filteredRoutes[i];
                    final isSel = _selectedRoute?.id == route.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isSel ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSel ? AppColors.primary.withValues(alpha: 0.40) : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          onTap: () async {
                            final busStore = Provider.of<BusStore>(context, listen: false);
                            setState(() {
                              _selectedRoute = route;
                              _updateActiveBus(busStore);
                            });
                            try {
                              const storage = FlutterSecureStorage();
                              await storage.write(key: 'last_selected_route_id', value: route.id);
                            } catch (_) {}
                            if (context.mounted) Navigator.pop(context);
                          },
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: (isSel ? AppColors.primary : AppColors.surfaceLight).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.directions_bus_rounded,
                              color: isSel ? AppColors.primaryLight : AppColors.textMuted,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            route.name,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 14,
                            ),
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
                          trailing: isSel 
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryLight, size: 20)
                            : const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                        ),
                      ),
                    ).animate().fadeIn(delay: (i * 25).ms).slideX(begin: 0.04);
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
    final auth = Provider.of<AuthService>(context, listen: false);
    final userPickup = auth.currentUser?.pickupPoint?.toLowerCase().trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ROUTE TIMELINE',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Text(
                '${_selectedRoute!.stops.length} STOPS',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.primaryLight,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...List.generate(_selectedRoute!.stops.length, (index) {
          final stop = _selectedRoute!.stops[index];
          final stopName = stop['name']?.toString() ?? 'Stop ${index + 1}';
          final isFirst = index == 0;
          final isLast = index == _selectedRoute!.stops.length - 1;
          final isUserStop = userPickup.isNotEmpty &&
              (stopName.toLowerCase().trim() == userPickup ||
               stopName.toLowerCase().contains(userPickup) ||
               userPickup.contains(stopName.toLowerCase().trim()));

          Color nodeColor = isUserStop
              ? AppColors.primary
              : isFirst
                  ? AppColors.primaryLight
                  : isLast
                      ? AppColors.accentGreen
                      : const Color(0xFF475569);

          String subtitle = isUserStop
              ? 'Your Assigned Pickup Stop'
              : isFirst
                  ? 'Departure Origin • Stop 1'
                  : isLast
                      ? 'Destination • SISTec Campus'
                      : 'Transit Stop ${index + 1}';

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: isUserStop ? 16 : 12,
                        height: isUserStop ? 16 : 12,
                        decoration: BoxDecoration(
                          color: (isFirst || isLast || isUserStop) ? nodeColor : AppColors.surface,
                          border: Border.all(color: nodeColor, width: isUserStop ? 3 : 2),
                          shape: BoxShape.circle,
                        ),
                        child: isUserStop
                            ? const Center(
                                child: Icon(Icons.circle, size: 4, color: Colors.white),
                              )
                            : null,
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: const Color(0xFF1E293B),
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
                        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                        : EdgeInsets.zero,
                    decoration: isUserStop
                        ? BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stopName,
                          style: GoogleFonts.plusJakartaSans(
                            color: isUserStop ? Colors.white : AppColors.text,
                            fontSize: 13.5,
                            fontWeight: isUserStop ? FontWeight.w800 : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: GoogleFonts.plusJakartaSans(
                            color: isUserStop ? AppColors.primaryLight : AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: Column(
        children: List.generate(
          4,
          (i) => Container(
            height: 100,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
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



