import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/bus_store.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../models/route_model.dart';
import '../models/bus_model.dart';
import '../theme/app_theme.dart';
import '../utils/timetable_resolver.dart';
import '../components/dashboard_back_scope.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// GuestDashboard
///
/// Dedicated, ultra-lightweight real-time tracking dashboard for Guest users.
/// Designed specifically without heavy map dependencies.
/// Provides a high-fidelity linear transit timeline tracker, real-time telemetry,
/// stop ETAs, route switching, and live socket synchronization.
/// ─────────────────────────────────────────────────────────────────────────────
class GuestDashboard extends StatefulWidget {
  const GuestDashboard({super.key});

  @override
  State<GuestDashboard> createState() => _GuestDashboardState();
}

class _GuestDashboardState extends State<GuestDashboard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  List<RouteModel> _routes = [];
  RouteModel? _selectedRoute;
  bool _isLoading = true;
  String _searchQuery = '';
  String? _pinnedStop;
  String _tripDirection = (DateTime.now().hour < 12) ? 'pickup' : 'dropoff';
  bool _isRefreshing = false;
  bool _isSwapBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.95, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<SocketService>(context, listen: false).checkAndReconnect();
      _refreshLiveTelemetry();
    }
  }

  Future<void> _initData() async {
    final busStore = Provider.of<BusStore>(context, listen: false);

    // ── STEP 1: Quick Cache Restoration (Instant UI load) ─────────────────────
    try {
      final cachedRouteData = await ApiService.getPersisted('guest_routes') ??
                              await ApiService.getPersisted('routes');
      final cachedBusData = await ApiService.getPersisted('guest_buses') ??
                            await ApiService.getPersisted('buses');

      if (cachedRouteData is List && cachedRouteData.isNotEmpty && mounted) {
        setState(() {
          _routes = cachedRouteData.map((r) => RouteModel.fromJson(r)).toList();
          if (_routes.isNotEmpty && _selectedRoute == null) {
            _selectedRoute = _routes.first;
          }
          _isLoading = false;
        });

        if (cachedBusData is List && cachedBusData.isNotEmpty) {
          busStore.seedBuses(cachedBusData);
        }
      }
    } catch (_) {}

    // ── STEP 2: Live Network Sync ─────────────────────────────────────────────
    await _refreshLiveTelemetry();
  }

  Future<void> _refreshLiveTelemetry() async {
    if (_isRefreshing && mounted) return;
    setState(() => _isRefreshing = true);

    final busStore = Provider.of<BusStore>(context, listen: false);

    try {
      final results = await Future.wait([
        _apiService.get('guest/routes', requiresAuth: false, useCache: true, persistCache: true)
            .catchError((_) => _apiService.get('routes', requiresAuth: false, useCache: true, persistCache: true)),
        _apiService.get('guest/buses', requiresAuth: false, persistCache: true)
            .catchError((_) => _apiService.get('buses', requiresAuth: false, persistCache: true)),
      ]);

      final routesData = results[0];
      final busesData = results[1];

      if (mounted) {
        if (routesData is List && routesData.isNotEmpty) {
          _routes = routesData.map((r) => RouteModel.fromJson(r)).toList();
        }

        if (busesData is List && busesData.isNotEmpty) {
          busStore.seedBuses(busesData);
        }

        // Auto-select route that has an active live bus if none chosen
        if (_selectedRoute == null || !_routes.any((r) => r.id == _selectedRoute!.id)) {
          final liveBuses = busStore.activeBuses;
          if (liveBuses.isNotEmpty) {
            final active = liveBuses.first;
            final matched = _routes.where((r) =>
              (r.id.isNotEmpty && r.id.trim() == active.routeId.trim()) ||
              (r.name.isNotEmpty && r.name.trim().toLowerCase() == active.routeName.trim().toLowerCase())
            );
            if (matched.isNotEmpty) {
              _selectedRoute = matched.first;
            }
          }
          _selectedRoute ??= (_routes.isNotEmpty ? _routes.first : null);
        }
      }
    } catch (e) {
      debugPrint('[GuestDashboard] Live sync error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Bus? _findActiveBusForRoute(BusStore store, RouteModel? route) {
    if (route == null) return null;
    final allBuses = store.allBuses;
    final liveBuses = store.activeBuses;

    // First try live broadcasting buses on this route
    final liveMatches = liveBuses.where((b) =>
      (b.routeId.isNotEmpty && b.routeId.trim() == route.id.trim()) ||
      (b.routeName.isNotEmpty && b.routeName.trim().toLowerCase() == route.name.trim().toLowerCase())
    ).toList();
    if (liveMatches.isNotEmpty) return liveMatches.first;

    // Fallback to any registered bus assigned to this route
    final anyMatches = allBuses.where((b) =>
      (b.routeId.isNotEmpty && b.routeId.trim() == route.id.trim()) ||
      (b.routeName.isNotEmpty && b.routeName.trim().toLowerCase() == route.name.trim().toLowerCase())
    ).toList();
    if (anyMatches.isNotEmpty) return anyMatches.first;

    return null;
  }

  void _showExitGuestDialog() {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.login_rounded, color: AppColors.primaryLight, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Sign In to Account',
              style: GoogleFonts.outfit(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Sign in with your College Enrollment No. or Staff ID to unlock personalized stop geofence alerts, bus pass, SOS, and full navigation map.',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep Browsing',
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Provider.of<AuthService>(context, listen: false).logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: Text(
              'Sign In',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotificationsSheet(BusStore store) {
    HapticFeedback.lightImpact();
    final notifs = store.notifications;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transit Bulletins',
                          style: GoogleFonts.outfit(
                            color: AppColors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Live campus transport updates & schedule alerts',
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: notifs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_read_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'All caught up!',
                            style: GoogleFonts.outfit(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No active transit advisories at this moment.',
                            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: notifs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, idx) {
                        final n = notifs[idx];
                        Color iconColor = AppColors.info;
                        IconData icon = Icons.info_outline_rounded;
                        if (n.type == 'critical') {
                          iconColor = AppColors.danger;
                          icon = Icons.error_outline_rounded;
                        } else if (n.type == 'warning') {
                          iconColor = AppColors.warning;
                          icon = Icons.warning_amber_rounded;
                        }
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, color: iconColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n.message,
                                      style: GoogleFonts.inter(
                                        color: AppColors.text,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatTime(n.timestamp),
                                      style: GoogleFonts.inter(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        final activeBus = _findActiveBusForRoute(busStore, _selectedRoute);

        return DashboardBackScope(
          exitMessage: 'Press back again to exit SISTecChalo',
          child: Scaffold(
            backgroundColor: AppColors.bg,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildTopAppBar(busStore),
                  _buildGuestNoticeBanner(),
                  _buildGuestSwapBanner(busStore, activeBus),
                  Expanded(
                    child: _isLoading
                        ? _buildShimmerLoading()
                        : RefreshIndicator(
                            color: AppColors.primaryLight,
                            backgroundColor: AppColors.surface,
                            onRefresh: _refreshLiveTelemetry,
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildRouteSearchBar(),
                                        const SizedBox(height: 14),
                                        _buildRouteSelectorPills(busStore),
                                        const SizedBox(height: 14),
                                        if (_selectedRoute != null) ...[
                                          _buildTelemetryHud(activeBus),
                                          const SizedBox(height: 16),
                                          _buildLinearTrackingHeader(activeBus),
                                          const SizedBox(height: 12),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (_selectedRoute != null)
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                                    sliver: _buildLinearTimeline(activeBus),
                                  )
                                else
                                  SliverToBoxAdapter(
                                    child: _buildNoRouteSelectedState(),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Top App Bar ────────────────────────────────────────────────────────────

  Widget _buildTopAppBar(BusStore busStore) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // SISTecChalo Title & Guest Badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SISTec',
                      style: GoogleFonts.outfit(
                        color: AppColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Chalo',
                      style: GoogleFonts.outfit(
                        color: AppColors.primaryLight,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            'GUEST',
                            style: GoogleFonts.inter(
                              color: AppColors.accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  'Live Linear Route Tracker',
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Actions Row (Zero Overflow Layout)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notifications button
              InkWell(
                onTap: () => _showNotificationsSheet(busStore),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary, size: 20),
                      if (busStore.unreadCount > 0)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 2),

              // Refresh button
              InkWell(
                onTap: _isRefreshing ? null : _refreshLiveTelemetry,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  child: _isRefreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                        )
                      : const Icon(Icons.sync_rounded, color: AppColors.textSecondary, size: 20),
                ),
              ),

              const SizedBox(width: 6),

              // Sign In Action
              InkWell(
                onTap: _showExitGuestDialog,
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.login_rounded, size: 13, color: AppColors.primaryLight),
                      const SizedBox(width: 4),
                      Text(
                        'Sign In',
                        style: GoogleFonts.outfit(
                          color: AppColors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Guest Mode Notice Banner ───────────────────────────────────────────────

  Widget _buildGuestNoticeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Public linear tracking mode • Map view & geofence alerts require student login',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _showExitGuestDialog,
            child: Text(
              'Login',
              style: GoogleFonts.inter(
                color: AppColors.primaryLight,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Live Bus Swap Alert Banner ─────────────────────────────────────────────

  Widget _buildGuestSwapBanner(BusStore busStore, Bus? activeBus) {
    if (_selectedRoute == null || _isSwapBannerDismissed) {
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

    if (!isSwap && busStore.notifications.isNotEmpty) {
      for (final notif in busStore.notifications) {
        final msg = notif.message;
        if (msg.contains('⚡ Bus Update') && msg.contains(routeName)) {
          isSwap = true;
          final match = RegExp(r'Bus Update:\s*([A-Za-z0-9\-\s]+?)\s+has been assigned to\s+([^.\(]+)', caseSensitive: false).firstMatch(msg);
          if (match != null) assignedBusNum = match.group(1)!.trim();
          final reasonMatch = RegExp(r'\(([^)]+)\)', caseSensitive: false).firstMatch(msg);
          if (reasonMatch != null) situationReason = reasonMatch.group(1)!.trim();
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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF231604), Color(0xFF181002)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.black, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      'ROUTE NOTICE',
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  situationReason,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFFBBF24),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => setState(() => _isSwapBannerDismissed = true),
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Bus $assignedBusNum${officialPlate.isNotEmpty ? ' ($officialPlate)' : ''} is operating on ${defaultBus.isNotEmpty ? defaultBus : 'this route'} today.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          if (driverName.isNotEmpty || (driverPhone != null && driverPhone.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (driverName.isNotEmpty)
                  Expanded(
                    child: Text(
                      'Driver: $driverName',
                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (driverPhone != null && driverPhone.isNotEmpty)
                  InkWell(
                    onTap: () async {
                      final uri = Uri.parse('tel:$driverPhone');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF34D399), size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Call Driver',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF34D399),
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Route Search Bar ───────────────────────────────────────────────────────

  Widget _buildRouteSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.inter(color: AppColors.text, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'Search route or stop (e.g. Lalghati, Bairagarh)...',
          hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val.trim().toLowerCase());
        },
      ),
    );
  }

  // ─── Horizontal Route Selector Pills ────────────────────────────────────────

  Widget _buildRouteSelectorPills(BusStore busStore) {
    var filtered = _routes;
    if (_searchQuery.isNotEmpty) {
      filtered = _routes.where((r) {
        final matchesRouteName = r.name.toLowerCase().contains(_searchQuery);
        final matchesStop = r.stops.any((s) =>
          (s['name']?.toString() ?? '').toLowerCase().contains(_searchQuery)
        );
        return matchesRouteName || matchesStop;
      }).toList();
    }

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_off_rounded, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No routes matching "$_searchQuery"',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final route = filtered[idx];
          final isSelected = _selectedRoute?.id == route.id;
          final bus = _findActiveBusForRoute(busStore, route);
          final isLive = bus != null && bus.isBroadcastingLive;

          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedRoute = route;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryLight
                      : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLive) ...[
                    ScaleTransition(
                      scale: _pulseScale,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.statusOnline,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    route.name.isNotEmpty ? route.name : 'Route ${idx + 1}',
                    style: GoogleFonts.outfit(
                      color: isSelected ? AppColors.text : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${route.stops.length}',
                      style: GoogleFonts.inter(
                        color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
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

  void _showTransportHelpSheet(BuildContext context, TimetableRouteEntry? busDetail) {
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
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Ratibad Campus • 09:00 AM Shift Roster',
                            style: GoogleFonts.inter(
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
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Driver • ${busDetail.displayBusLabel} (${busDetail.vehicleNo})',
                                style: GoogleFonts.inter(
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
                              textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'COLLEGE TRANSPORT INCHARGES',
                  style: GoogleFonts.inter(
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
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                incharge.designation,
                                style: GoogleFonts.inter(
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
                            textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
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

  // ─── Live Telemetry HUD ─────────────────────────────────────────────────────

  Widget _buildTelemetryHud(Bus? activeBus) {
    final bool isLive = activeBus != null && activeBus.isBroadcastingLive;
    final busDetail = TimetableResolver.resolveBusDetails(
      routeName: _selectedRoute?.name,
      busNo: activeBus?.busNumber,
    );
    final String busLabel = (activeBus != null &&
            !activeBus.displayBusNumber.contains('Hex') &&
            !activeBus.displayBusNumber.contains('SHUTTLE'))
        ? activeBus.displayBusNumber
        : (busDetail?.displayBusLabel ?? 'BUS ASSIGNED');
    final double speed = activeBus?.speed ?? 0.0;
    final String status = activeBus?.status ?? (busDetail != null ? '${busDetail.morningDeparture} Shift' : 'Scheduled');
    final String? nextStop = activeBus?.nextStop;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLive ? AppColors.statusOnline.withValues(alpha: 0.3) : AppColors.border,
          width: 1.2,
        ),
        boxShadow: [
          if (isLive)
            BoxShadow(
              color: AppColors.statusOnline.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Bus number + Live/Offline badge + Shift (Overflow-Safe Responsive Layout)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isLive
                        ? [AppColors.primary, AppColors.primaryDark]
                        : [const Color(0xFF334155), const Color(0xFF1E293B)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_bus_rounded, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      busLabel,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Live Status Badge (Flexible with safe ellipsis)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isLive ? AppColors.statusOnline : AppColors.textMuted).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isLive ? AppColors.statusOnline : AppColors.textMuted).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulseScale,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isLive ? AppColors.statusOnline : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4.5),
                      Flexible(
                        child: Text(
                          isLive ? 'LIVE BROADCAST' : 'SCHEDULED',
                          style: GoogleFonts.inter(
                            color: isLive ? AppColors.statusOnline : AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // Direction toggle button
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _tripDirection = (_tripDirection == 'pickup') ? 'dropoff' : 'pickup';
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _tripDirection == 'pickup' ? Icons.login_rounded : Icons.logout_rounded,
                        size: 12,
                        color: AppColors.primaryLight,
                      ),
                      const SizedBox(width: 3.5),
                      Text(
                        _tripDirection == 'pickup' ? 'To Campus' : 'From Campus',
                        style: GoogleFonts.inter(
                          color: AppColors.primaryLight,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 3-Column Metrics Grid
          Row(
            children: [
              // Speed
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.speed_rounded,
                  iconColor: AppColors.accent,
                  label: 'CURRENT SPEED',
                  value: isLive ? '${speed.toStringAsFixed(0)} km/h' : '0 km/h',
                  subtext: isLive ? (speed > 5 ? 'Cruising' : 'At Stop / Idle') : 'Stationary',
                ),
              ),
              const SizedBox(width: 10),

              // Next Stop
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.near_me_rounded,
                  iconColor: AppColors.statusOnline,
                  label: 'APPROACHING',
                  value: nextStop ?? 'Route Start',
                  subtext: isLive ? 'Next Station' : 'Upcoming',
                  isHighlighted: nextStop != null,
                ),
              ),
              const SizedBox(width: 10),

              // Status
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.timer_outlined,
                  iconColor: AppColors.statusDelayed,
                  label: 'DISPATCH',
                  value: status,
                  subtext: isLive ? 'Real-Time GPS' : 'Timetable',
                ),
              ),
            ],
          ),

          // Official Assigned Driver & Vehicle Registration Card
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_pin_circle_rounded, size: 16, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              busDetail?.driverName ?? 'SISTec Transport Driver',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (busDetail != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                busDetail.vehicleNo,
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Shift Arrival: 09:00 AM • Return: 04:30 PM',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 10.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (busDetail != null && busDetail.driverPhone.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _makePhoneCall(busDetail.driverPhone),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phone_in_talk_rounded, size: 13, color: AppColors.accentGreen),
                          const SizedBox(width: 4),
                          Text(
                            'Call',
                            style: GoogleFonts.inter(
                              color: AppColors.accentGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _showTransportHelpSheet(context, busDetail),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.support_agent_rounded, size: 15, color: AppColors.primaryLight),
                  ),
                ),
              ],
            ),
          ),

          if (!isLive) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No driver is transmitting live GPS right now. Displaying complete scheduled route stops from the official 9:00 AM roster.',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subtext,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted ? iconColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 20,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.outfit(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─── Linear Tracking Section Header ─────────────────────────────────────────

  Widget _buildLinearTrackingHeader(Bus? activeBus) {
    final stopsCount = _selectedRoute?.stops.length ?? 0;
    final completedCount = activeBus != null && activeBus.isBroadcastingLive
        ? _calculateCompletedCount(activeBus)
        : 0;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.linear_scale_rounded, color: AppColors.primaryLight, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Route Progression',
                style: GoogleFonts.outfit(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$completedCount of $stopsCount stations covered',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (_pinnedStop != null) const SizedBox(width: 8),
        if (_pinnedStop != null)
          InkWell(
            onTap: () {
              setState(() => _pinnedStop = null);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.accentPurple.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.push_pin_rounded, color: AppColors.accentPurple, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    'Clear Pin',
                    style: GoogleFonts.inter(color: AppColors.accentPurple, fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  int _calculateCompletedCount(Bus activeBus) {
    if (_selectedRoute == null || _selectedRoute!.stops.isEmpty) return 0;
    final stops = _getOrderedStops();
    if (activeBus.nextStop == null || activeBus.nextStop!.isEmpty) {
      return activeBus.completedStops.clamp(0, stops.length);
    }
    final nextIdx = stops.indexWhere((s) =>
      s['name']?.toString().toLowerCase().trim() == activeBus.nextStop!.toLowerCase().trim()
    );
    if (nextIdx != -1) return nextIdx;
    return activeBus.completedStops.clamp(0, stops.length);
  }

  List<Map<String, dynamic>> _getOrderedStops() {
    if (_selectedRoute == null) return [];
    final list = List<Map<String, dynamic>>.from(_selectedRoute!.stops);
    if (_tripDirection == 'dropoff') {
      return list.reversed.toList();
    }
    return list;
  }

  // ─── Linear Timeline List ───────────────────────────────────────────────────

  Widget _buildLinearTimeline(Bus? activeBus) {
    final stops = _getOrderedStops();
    if (stops.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          child: Text(
            'No stops registered for this route.',
            style: GoogleFonts.inter(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final bool isLive = activeBus != null && activeBus.isBroadcastingLive;
    final int nextStopIdx = isLive ? _findNextStopIndex(stops, activeBus) : -1;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, idx) {
          final stop = stops[idx];
          final stopName = stop['name']?.toString() ?? 'Stop ${idx + 1}';
          final isFirst = idx == 0;
          final isLast = idx == stops.length - 1;

          // Determine Stop State
          final bool isPassed = isLive && (nextStopIdx != -1 ? idx < nextStopIdx : idx < activeBus.completedStops);
          final bool isNext = isLive && idx == nextStopIdx;
          final bool isPinned = _pinnedStop != null && _pinnedStop == stopName;
          final bool isLiveSegment = isLive && (idx == nextStopIdx - 1);

          // Find ETA for this stop if available
          BusETA? etaItem;
          if (activeBus != null && activeBus.etas.isNotEmpty) {
            try {
              etaItem = activeBus.etas.firstWhere(
                (e) => e.stopName.toLowerCase().trim() == stopName.toLowerCase().trim(),
              );
            } catch (_) {}
          }

          return _buildTimelineItem(
            stopName: stopName,
            index: idx,
            totalStops: stops.length,
            isFirst: isFirst,
            isLast: isLast,
            isPassed: isPassed,
            isNext: isNext,
            isPinned: isPinned,
            isLiveSegment: isLiveSegment,
            activeBus: activeBus,
            etaItem: etaItem,
          );
        },
        childCount: stops.length,
      ),
    );
  }

  int _findNextStopIndex(List<Map<String, dynamic>> stops, Bus activeBus) {
    if (activeBus.nextStop == null || activeBus.nextStop!.isEmpty) return -1;
    final cleanNext = activeBus.nextStop!.toLowerCase().trim();
    for (int i = 0; i < stops.length; i++) {
      final sName = (stops[i]['name']?.toString() ?? '').toLowerCase().trim();
      if (sName == cleanNext || sName.contains(cleanNext) || cleanNext.contains(sName)) {
        return i;
      }
    }
    return -1;
  }

  Widget _buildTimelineItem({
    required String stopName,
    required int index,
    required int totalStops,
    required bool isFirst,
    required bool isLast,
    required bool isPassed,
    required bool isNext,
    required bool isPinned,
    required bool isLiveSegment,
    required Bus? activeBus,
    required BusETA? etaItem,
  }) {
    final scheduledTime = TimetableResolver.getScheduledTimeForStop(_selectedRoute?.name, stopName);

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left Column: Timeline Status Badge / Tag ──────────────────
              SizedBox(
                width: 72,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isPassed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.statusOnline.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PASSED',
                            style: GoogleFonts.inter(
                              color: AppColors.statusOnline,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (isNext)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'APPROACH',
                            style: GoogleFonts.inter(
                              color: AppColors.primaryLight,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      else
                        Text(
                          scheduledTime ?? 'Stop ${index + 1}',
                          style: GoogleFonts.inter(
                            color: scheduledTime != null ? AppColors.accent : AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (etaItem != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '~${etaItem.minutes} min',
                          style: GoogleFonts.inter(
                            color: isNext ? AppColors.primaryLight : AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Center Column: Track Line & Stop Node ─────────────────────
              SizedBox(
                width: 32,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Top Connecting Track
                    if (!isFirst)
                      Positioned(
                        top: 0,
                        bottom: 24,
                        child: Container(
                          width: 3,
                          color: isPassed ? AppColors.statusOnline : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),

                    // Bottom Connecting Track
                    if (!isLast)
                      Positioned(
                        top: 24,
                        bottom: 0,
                        child: Container(
                          width: 3,
                          color: isPassed && !isLiveSegment
                              ? AppColors.statusOnline
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),

                    // Stop Node Icon / Ring
                    Positioned(
                      top: 10,
                      child: isPassed
                          ? Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: AppColors.statusOnline,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 13, color: Colors.white),
                            )
                          : isNext
                              ? ScaleTransition(
                                  scale: _pulseScale,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.primaryLight, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryLight.withValues(alpha: 0.4),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primaryLight,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: AppColors.bgSecondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isPinned ? AppColors.accentPurple : Colors.white.withValues(alpha: 0.3),
                                      width: isPinned ? 2.5 : 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: isPinned ? AppColors.accentPurple : Colors.white.withValues(alpha: 0.4),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),

              // ── Right Column: Stop Name & Interactive Card ────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 12),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (_pinnedStop == stopName) {
                          _pinnedStop = null;
                        } else {
                          _pinnedStop = stopName;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isNext
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : (isPinned
                                ? AppColors.accentPurple.withValues(alpha: 0.1)
                                : AppColors.surface),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isNext
                              ? AppColors.primaryLight.withValues(alpha: 0.5)
                              : (isPinned
                                  ? AppColors.accentPurple.withValues(alpha: 0.6)
                                  : AppColors.border),
                          width: (isNext || isPinned) ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        stopName,
                                        style: GoogleFonts.outfit(
                                          color: isNext
                                              ? AppColors.primaryLight
                                              : (isPassed ? AppColors.textSecondary : AppColors.text),
                                          fontSize: 14.5,
                                          fontWeight: (isNext || isPinned) ? FontWeight.w700 : FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isFirst || isLast || isPinned || scheduledTime != null) const SizedBox(width: 6),
                                    if (isFirst)
                                      _buildStopRoleBadge('ORIGIN', AppColors.accent)
                                    else if (isLast)
                                      _buildStopRoleBadge('DESTINATION', AppColors.statusOnline)
                                    else if (isPinned)
                                      _buildStopRoleBadge('YOUR STOP', AppColors.accentPurple)
                                    else if (scheduledTime != null)
                                      _buildStopRoleBadge(scheduledTime, AppColors.primaryLight),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 12,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        isPassed
                                            ? 'Bus has departed this station'
                                            : (isNext
                                                ? 'Bus is currently en route to this stop'
                                                : (scheduledTime != null
                                                    ? 'Scheduled: $scheduledTime • Campus: 09:00 AM'
                                                    : 'Scheduled stop along corridor')),
                                        style: GoogleFonts.inter(
                                          color: AppColors.textMuted,
                                          fontSize: 11,
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
                          const SizedBox(width: 8),
                          Icon(
                            isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            size: 16,
                            color: isPinned ? AppColors.accentPurple : Colors.white.withValues(alpha: 0.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Real-Time Live Bus Marker Between Stops on the Track ────────────
        if (isLiveSegment && activeBus != null)
          _buildLiveBusBetweenStopsCard(activeBus),
      ],
    );
  }

  Widget _buildStopRoleBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildLiveBusBetweenStopsCard(Bus activeBus) {
    final speed = activeBus.speed.toStringAsFixed(0);
    final busNo = activeBus.displayBusNumber;

    return Padding(
      padding: const EdgeInsets.only(left: 72, bottom: 12, right: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E3A8A), Color(0xFF1E40AF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ScaleTransition(
              scale: _pulseScale,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'BUS LIVE ON TRACK',
                        style: GoogleFonts.inter(
                          color: AppColors.primaryLight,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          busNo,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Moving at $speed km/h toward next station',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_downward_rounded, color: AppColors.primaryLight, size: 18),
          ],
        ),
      ),
    );
  }

  // ─── No Route Selected / Empty State ────────────────────────────────────────

  Widget _buildNoRouteSelectedState() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.alt_route_rounded, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Select a Route to Begin',
            style: GoogleFonts.outfit(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose any bus route above to see live stations and real-time tracking.',
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── Shimmer Loading ────────────────────────────────────────────────────────

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(height: 44, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
            const SizedBox(height: 14),
            Container(height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
            const SizedBox(height: 14),
            Container(height: 140, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18))),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, __) => Container(
                  height: 64,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
