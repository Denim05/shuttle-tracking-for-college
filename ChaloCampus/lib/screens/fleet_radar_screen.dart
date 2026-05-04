import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:provider/provider.dart';
import '../models/bus_model.dart';
import '../services/api_service.dart';
import '../services/bus_store.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../components/bus_map.dart';

// ─── Fleet Radar Screen ───────────────────────────────────────────────────────

class FleetRadarScreen extends StatefulWidget {
  const FleetRadarScreen({super.key});

  @override
  State<FleetRadarScreen> createState() => _FleetRadarScreenState();
}

enum _RadarFilter { all, active, delayed, offline }

class _FleetRadarScreenState extends State<FleetRadarScreen> {
  final ApiService _apiService = ApiService();

  bool   _isLoading     = true;
  String? _selectedBusId;
  _RadarFilter _filter  = _RadarFilter.all;

  // SOS overlay
  Map<String, dynamic>? _pendingSOSAlert;
  Timer? _sosTimer;

  // Ping refresh
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    _loadAndSeedBuses();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupListeners();
    });
  }

  void _setupListeners() {
    final socketSvc = context.read<SocketService>();
    // SOS alert overlay via ValueNotifier
    socketSvc.lastSOSAlert.addListener(_onSOSAlert);
    // Periodic latency ping every 10 s
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      socketSvc.pingServer();
    });
    socketSvc.pingServer(); // immediate first ping
  }

  void _onSOSAlert() {
    final sos = context.read<SocketService>().lastSOSAlert.value;
    if (sos == null || !mounted) return;
    setState(() => _pendingSOSAlert = sos);
    _sosTimer?.cancel();
    _sosTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _pendingSOSAlert = null);
    });
  }

  Future<void> _loadAndSeedBuses() async {
    try {
      final data = await _apiService.get('buses');
      if (mounted) {
        context.read<BusStore>().seedBuses(data as List);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('FleetRadar load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    context.read<SocketService>().lastSOSAlert.removeListener(_onSOSAlert);
    _sosTimer?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  // ─── Filter Logic ───────────────────────────────────────────────────────

  List<Bus> _applyFilter(List<Bus> buses) {
    switch (_filter) {
      case _RadarFilter.active:
        return buses.where((b) => b.status == 'On-time').toList();
      case _RadarFilter.delayed:
        return buses.where((b) => b.status == 'Delayed').toList();
      case _RadarFilter.offline:
        return buses.where((b) => b.status == 'Offline').toList();
      case _RadarFilter.all:
        return buses;
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<BusStore>(
      builder: (context, store, _) {
        final allBuses    = store.allBuses;
        final filtered    = _applyFilter(allBuses);
        final activeCount  = allBuses.where((b) => b.status == 'On-time').length;
        final delayedCount = allBuses.where((b) => b.status == 'Delayed').length;
        final offlineCount = allBuses.where((b) => b.status == 'Offline').length;

        return Scaffold(
          backgroundColor: AppColors.bg,
          extendBodyBehindAppBar: true,
          body: _isLoading
              ? _buildLoader()
              : Stack(
                  children: [
                    // ── Full-screen Map ──────────────────────────────────
                    BusMap(
                      buses:         allBuses,
                      selectedRoute: null,
                      centerOnBusId: _selectedBusId,
                    ),

                    // ── Reconnect Banner ─────────────────────────────────
                    _buildConnectionBanner(),

                    // ── App Bar ──────────────────────────────────────────
                    _buildAppBar(),

                    // ── SOS Overlay ──────────────────────────────────────
                    if (_pendingSOSAlert != null)
                      _buildSOSOverlay(_pendingSOSAlert!),

                    // ── Bottom Fleet Panel ───────────────────────────────
                    DraggableScrollableSheet(
                      initialChildSize: 0.38,
                      minChildSize:     0.12,
                      maxChildSize:     0.72,
                      snap:             true,
                      snapSizes: const [0.12, 0.38, 0.72],
                      builder: (context, scrollController) {
                        return _buildFleetPanel(
                          scrollController, filtered,
                          activeCount, delayedCount, offlineCount,
                        );
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }

  // ─── App Bar ────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fleet Tracker',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontWeight: FontWeight.w900,
                    fontSize: 16, letterSpacing: 3,
                  ),
                ),
              ),
              // Latency indicator
              ValueListenableBuilder<int?>(
                valueListenable: context.read<SocketService>().lastPingMs,
                builder: (_, ping, __) {
                  if (ping == null) return const SizedBox.shrink();
                  final color = ping < 100
                      ? AppColors.accent
                      : ping < 300
                          ? AppColors.warning
                          : AppColors.danger;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${ping}ms',
                      style: GoogleFonts.plusJakartaSans(color: color, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  );
                },
              ),
              // Connection dot
              ValueListenableBuilder<bool>(
                valueListenable: context.read<SocketService>().connectionStatus,
                builder: (_, connected, __) {
                  final color = connected ? AppColors.accent : AppColors.danger;
                  return Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
                    ),
                  ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.5.seconds);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Connection Banner ───────────────────────────────────────────────────

  Widget _buildConnectionBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: context.read<SocketService>().connectionStatus,
      builder: (_, connected, __) {
        if (connected) return const SizedBox.shrink();
        return Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 8),
                Text(
                  'Connecting to server...',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w900, letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
        );
      },
    );
  }

  // ─── SOS Overlay ────────────────────────────────────────────────────────

  Widget _buildSOSOverlay(Map<String, dynamic> sos) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 16, right: 16,
      child: GestureDetector(
        onTap: () => setState(() => _pendingSOSAlert = null),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.danger,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.danger.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 4)],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
              ).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(1,1), end: const Offset(1.15,1.15), duration: 600.ms),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🚨 Emergency Alert', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
                    const SizedBox(height: 2),
                    Text(
                      sos['name']?.toString() ?? sos['routeName']?.toString() ?? 'Alert received',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            ],
          ),
        ).animate().slideY(begin: -0.5, end: 0, curve: Curves.easeOutCubic).fadeIn(),
      ),
    );
  }

  // ─── Fleet Panel ─────────────────────────────────────────────────────────

  Widget _buildFleetPanel(
    ScrollController scrollController,
    List<Bus> filtered,
    int activeCount, int delayedCount, int offlineCount,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 10)],
      ),
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          // ── Drag Handle ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),

          // ── Stats Row ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildStatChip('ACTIVE',   activeCount,  AppColors.accent),
                  const SizedBox(width: 10),
                  _buildStatChip('DELAYED',  delayedCount, AppColors.warning),
                  const SizedBox(width: 10),
                  _buildStatChip('OFFLINE',  offlineCount, AppColors.danger),
                  const Spacer(),
                  Text(
                    '${context.read<BusStore>().allBuses.length} BUSES',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted, fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 14)),

          // ── Filter Chips ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 36,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('ALL',     _RadarFilter.all),
                  const SizedBox(width: 8),
                  _buildFilterChip('ACTIVE',  _RadarFilter.active),
                  const SizedBox(width: 8),
                  _buildFilterChip('DELAYED', _RadarFilter.delayed),
                  const SizedBox(width: 8),
                  _buildFilterChip('OFFLINE', _RadarFilter.offline),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 14)),

          // ── Section Label ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${filtered.length} BUS${filtered.length == 1 ? '' : 'ES'} IN VIEW',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted, fontSize: 9,
                  fontWeight: FontWeight.w900, letterSpacing: 2,
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Bus List ──────────────────────────────────────────────────
          filtered.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState())
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildBusCard(filtered[i], i),
                    childCount: filtered.length,
                  ),
                ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // ─── Stat Chip ───────────────────────────────────────────────────────────

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: GoogleFonts.plusJakartaSans(
              color: color, fontSize: 9,
              fontWeight: FontWeight.w900, letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter Chip ─────────────────────────────────────────────────────────

  Widget _buildFilterChip(String label, _RadarFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  // ─── Bus Card ────────────────────────────────────────────────────────────

  Widget _buildBusCard(Bus bus, int index) {
    final isSelected = _selectedBusId == bus.id;
    Color statusColor;
    IconData statusIcon;
    switch (bus.status) {
      case 'On-time':
        statusColor = AppColors.accent;
        statusIcon  = Icons.check_circle_rounded;
        break;
      case 'Delayed':
        statusColor = AppColors.warning;
        statusIcon  = Icons.schedule_rounded;
        break;
      default:
        statusColor = AppColors.danger;
        statusIcon  = Icons.wifi_off_rounded;
    }

    // Route color parse
    Color routeColor = AppColors.primary;
    try {
      routeColor = Color(int.parse(bus.routeColor.replaceAll('#', '0xFF')));
    } catch (_) {}

    final secondsAgo = DateTime.now().difference(bus.lastUpdated).inSeconds;
    final timeAgo = secondsAgo < 60
        ? '${secondsAgo}s ago'
        : '${(secondsAgo / 60).floor()}m ago';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedBusId = isSelected ? null : bus.id;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? routeColor.withValues(alpha: 0.08)
              : AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? routeColor.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: routeColor.withValues(alpha: 0.15), blurRadius: 20)]
              : null,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Route color stripe
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: routeColor,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                ),
              ),
              const SizedBox(width: 14),

              // Bus icon
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: routeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: routeColor.withValues(alpha: 0.25)),
                ),
                child: Icon(Icons.directions_bus_rounded, color: routeColor, size: 22),
              ),
              const SizedBox(width: 12),

              // Bus details
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bus.routeName,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.text, fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Speed chip
                          if (bus.status != 'Offline')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${bus.speed.toInt()} km/h',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primary, fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            bus.status.toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              color: statusColor, fontSize: 9,
                              fontWeight: FontWeight.w900, letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 3, height: 3, decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(
                            timeAgo,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textMuted, fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (bus.etas.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Next: ${bus.etas.first.stopName} in ${bus.etas.first.minutes}m',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondary, fontSize: 9,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Focus arrow
              Icon(
                isSelected ? Icons.gps_fixed_rounded : Icons.chevron_right_rounded,
                color: isSelected ? routeColor : AppColors.textMuted,
                size: isSelected ? 18 : 16,
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ).animate(delay: Duration(milliseconds: index * 40))
       .fadeIn(duration: 300.ms)
       .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
    );
  }

  // ─── Empty State ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.radar_rounded, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(
            'NO BUSES IN THIS FILTER',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted, fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Loading State ───────────────────────────────────────────────────────

  Widget _buildLoader() {
    return Container(
      color: AppColors.bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(
                color: AppColors.accent, strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted, fontSize: 11,
                fontWeight: FontWeight.w900, letterSpacing: 3,
              ),
            ),
          ],
        ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
      ),
    );
  }
}

