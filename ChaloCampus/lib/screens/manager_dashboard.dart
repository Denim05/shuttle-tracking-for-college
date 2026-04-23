import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../services/socket_service.dart';
import '../services/bus_store.dart';
import '../components/bus_map.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  // _buses removed — fleet data now comes from BusStore (Consumer<BusStore>)
  List<RouteModel> _routes = [];
  List<dynamic> _users = [];
  List<dynamic> _drivers = [];
  late SocketService _socketService;
  late BusStore _busStore;
  final TextEditingController _notifController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _socketService = Provider.of<SocketService>(context, listen: false);
    _busStore = Provider.of<BusStore>(context, listen: false);
    _loadData();
    _initSocket();
    _loadNotificationHistory();
  }

  void _initSocket() {
    // ⚠️ Do NOT call listenToBusUpdates here — that would overwrite BusStore's
    // listener and break real-time updates across all dashboards.
    // The fleet tab reads from BusStore via Consumer<BusStore> instead.

    _socketService.listenToSystemAlerts((data) {
      if (mounted && data != null && data['message'] != null) {
        _showSystemAlertSnackBar(data['message']);
      }
    });

    _socketService.listenToSOSAlerts((data) {
      if (mounted && data != null) {
        _showEmergencySOSOverlay(data);
      }
    });
  }

  Future<void> _loadNotificationHistory() async {
    try {
      final data = await _apiService.get('notifications');
      _busStore.seedNotifications(data as List);
    } catch (e) {
      debugPrint('Notification history load failed: $e');
    }
  }

  @override
  void dispose() {
    _notifController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final busData = await _apiService.get('buses');
      final routeData = await _apiService.get('routes');
      
      // We use try-catch for these as they might be protected or fail if no users exist
      dynamic userData = [];
      dynamic driverData = [];
      try {
        userData = await _apiService.get('manager/users');
        driverData = await _apiService.get('manager/drivers');
      } catch (e) {
        debugPrint('Optional data failed to load: $e');
      }
      
      if (!mounted) return;
      setState(() {
        _routes = (routeData as List).map((r) => RouteModel.fromJson(r)).toList();
        _users = userData as List;
        _drivers = driverData as List;
        _isLoading = false;
      });
      // Seed BusStore with initial bus data (real-time updates come via socket)
      final busStore = Provider.of<BusStore>(context, listen: false);
      busStore.seedBuses(busData as List);
    } catch (e) {
      debugPrint('Error loading manager data: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      // If routes are empty, show a hint
      if (e.toString().contains('404') || e.toString().contains('empty')) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database is empty. Please add routes first.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (e.toString().contains('401')) {
        // Auto-logout on session expiration
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Session expired. Getting fresh token...'), backgroundColor: Colors.orange)
           );
           Provider.of<AuthService>(context, listen: false).logout();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _seedDatabase() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.post('manager/seed', {});
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database seeded successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('401')) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Session expired. Logging out...'), backgroundColor: Colors.orange)
           );
           Provider.of<AuthService>(context, listen: false).logout();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Seed failed: ${e.toString().replaceAll('Exception:', '').trim()}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFF02040A),
        body: ValueListenableBuilder<bool>(
          valueListenable: socketService.connectionStatus,
          builder: (context, isConnected, child) {
            return Stack(
              children: [
                // Background Gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.5,
                      colors: [Color(0xFF0F172A), Color(0xFF02040A)],
                    ),
                  ),
                ),

                if (!isConnected)
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
                    left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFFF2E63).withValues(alpha: 0.8),
                      child: Center(
                        child: Text(
                          '📡 SYNCHRONIZING WITH FLEET...',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
                        ),
                      ),
                    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
                  ),

                // Header Content
                Column(
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + (isConnected ? 10 : 30), 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CHALO CAMPUS',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 6, height: 6,
                                    decoration: const BoxDecoration(color: Color(0xFF00F0FF), shape: BoxShape.circle),
                                  ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.seconds),
                                  const SizedBox(width: 8),
                                  Text('COMMAND CENTER', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _buildAppBarAction(Icons.auto_awesome_rounded, _seedDatabase),
                              _buildAppBarAction(Icons.logout_rounded, () {
                                 Provider.of<AuthService>(context, listen: false).logout();
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Custom Tab Bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161420),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.1)),
                      ),
                      child: TabBar(
                        indicator: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF6C63FF).withValues(alpha: 0.2),
                              const Color(0xFF00F0FF).withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
                        ),
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: const Color(0xFF00F0FF),
                        unselectedLabelColor: Colors.white24,
                        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 10),
                        tabs: [
                          const Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: 'Fleet'),
                          const Tab(icon: Icon(Icons.map_rounded, size: 20), text: 'Map'),
                          const Tab(icon: Icon(Icons.badge_rounded, size: 20), text: 'Drivers'),
                          const Tab(icon: Icon(Icons.people_alt_rounded, size: 20), text: 'Users'),
                          Tab(
                            icon: Consumer<BusStore>(
                              builder: (_, store, __) => Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 20),
                                  if (store.unreadCount > 0)
                                    Positioned(
                                      top: -4, right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFFF2E63),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${store.unreadCount > 9 ? '9+' : store.unreadCount}',
                                          style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            text: 'Alerts',
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: _isLoading 
                        ? _buildLoadingState()
                        : TabBarView(
                            children: [
                              _buildFleetTab(),
                              _buildMapTab(),
                              _buildDriverTab(),
                              _buildUserTab(),
                              _buildAlertTab(),
                            ],
                          ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBarAction(IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  Widget _buildFleetTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        final buses = busStore.allBuses;
        if (buses.isEmpty) return _buildEmptyState('No fleet active', Icons.bus_alert_rounded);

        final int activeBuses  = buses.where((b) => b.status != 'Offline').length;
        final int onTimeBuses  = buses.where((b) => b.status == 'On-time').length;
        final int delayedBuses = buses.where((b) => b.status == 'Delayed').length;

        return Column(
          children: [
            // Analytics Header
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  _buildAnalyticsCard('FLEET CAPACITY', '$activeBuses/${buses.length}', Icons.sensors_rounded, const Color(0xFF6C63FF)),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('OPTIMIZED', '$onTimeBuses', Icons.bolt_rounded, const Color(0xFF00F0FF)),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('ANOMALIES', '$delayedBuses', Icons.error_outline_rounded, const Color(0xFFFF2E63)),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('PULSE USERS', '${_users.length}', Icons.query_stats_rounded, Colors.white),
                ],
              ).animate().slideX(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(),
            ),
            // Fleet List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                backgroundColor: const Color(0xFF0D0B14),
                color: const Color(0xFF6C63FF),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: buses.length,
                  itemBuilder: (context, index) {
                    final bus = buses[index];
                    return _buildGlassCard(
                      index: index,
                      child: Row(
                        children: [
                          _buildStatusIndicator(bus.status == 'On-time'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'UNIT_${bus.id.substring(bus.id.length - 4).toUpperCase()}',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'CORE_ROUTE: ${bus.routeName.toUpperCase()}',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    // ── Live speed badge ───────────────────────────
                                    if (bus.status != 'Offline')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00F0FF).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          '${bus.speed.toStringAsFixed(1)} KM/H',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: const Color(0xFF00F0FF),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _buildBadge(bus.occupancy, _getOccupancyColor(bus.occupancy)),
                                    const SizedBox(width: 8),
                                    _buildBadge(bus.status, _getStatusColor(bus.status)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _buildActionButton(Icons.tune_rounded, () => _showBusActionDialog(bus)),
                        ],
                      ),
                    ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.2);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161420),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2
          )
        ]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
              Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverTab() {
    if (_drivers.isEmpty) return _buildEmptyState('No drivers available', Icons.person_off_rounded);
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _drivers.length,
        itemBuilder: (context, index) {
          final driver = _drivers[index];
          final bool isActive = driver['status'] != 'Suspended';
          return _buildGlassCard(
            index: index,
            child: Row(
              children: [
                Container(
                  height: 54, width: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        (isActive ? const Color(0xFF6C63FF) : const Color(0xFFFF2E63)).withValues(alpha: 0.2),
                        (isActive ? const Color(0xFF00F0FF) : const Color(0xFFFF2E63)).withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: (isActive ? const Color(0xFF6C63FF) : const Color(0xFFFF2E63)).withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.shield_rounded, color: isActive ? const Color(0xFF00F0FF) : const Color(0xFFFF2E63)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (driver['name'] ?? driver['username']).toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ASSIGNED: ${driver['assignedBus'] ?? 'UNASSIGNED'}',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(isActive ? 'OPERATIONAL' : 'SUSPENDED', isActive),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white38),
                  color: const Color(0xFF161420),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.white10),
                  ),
                  onSelected: (value) async {
                    final newStatus = value == 'Suspend' ? 'Suspended' : 'Active';
                    await _apiService.put('manager/drivers/${driver['_id']}', {'status': newStatus});
                    _loadData();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: isActive ? 'Suspend' : 'Activate',
                      child: Text(isActive ? 'Suspend' : 'Activate', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.2);
        },
      ),
    );
  }

  Widget _buildUserTab() {
    if (_users.isEmpty) return _buildEmptyState('No registered users', Icons.group_outlined);
    
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return _buildGlassCard(
            index: index,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: Color(0xFF00F0FF), size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['name'] ?? user['username'] ?? 'Unknown', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('UID: ${user['userId'] ?? user['studentId'] ?? user['roll'] ?? 'N/A'}', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: Color(0xFF6C63FF), size: 12),
                          const SizedBox(width: 4),
                          Expanded(child: Text(user['pickupPoint'] ?? 'NOT CONFIGURED', style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500))),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildActionButton(Icons.route_rounded, () => _showUserRouteDialog(user)),
              ],
            ),
          ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.2);
        },
      ),
    );
  }

  Widget _buildAlertTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        // Mark all read when this tab is viewed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (busStore.unreadCount > 0) busStore.markAllRead();
        });

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            // ── Broadcast Composer ─────────────────────────────────────
            Text('CORE BROADCAST', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text('Dispatch real-time directives to all active units.', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF161420),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.05), blurRadius: 20),
                ]
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _notifController,
                    maxLines: 4,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Enter mission-critical directive...',
                      hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _isSending ? null : () async {
                      final msg = _notifController.text.trim();
                      if (msg.isEmpty) return;
                      setState(() => _isSending = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await _apiService.post('manager/notifications', {'message': msg});
                        if (!mounted) return;
                        _notifController.clear();
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF00F0FF),
                            behavior: SnackBarBehavior.floating,
                            content: Text('DIRECTIVE DISPATCHED', style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                      } finally {
                        if (mounted) setState(() => _isSending = false);
                      }
                    },
                    child: AnimatedContainer(
                      duration: 300.ms,
                      height: 64,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isSending
                            ? [const Color(0xFF6C63FF).withValues(alpha: 0.4), const Color(0xFF00F0FF).withValues(alpha: 0.4)]
                            : [const Color(0xFF6C63FF), const Color(0xFF00F0FF)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: _isSending
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('INITIATE BROADCAST', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Live Notification Feed ──────────────────────────────────
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('LIVE FEED', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F0FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(color: Color(0xFF00F0FF), shape: BoxShape.circle),
                      ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.seconds),
                      const SizedBox(width: 6),
                      Text('REAL-TIME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (busStore.notifications.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF161420),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 40),
                      const SizedBox(height: 12),
                      Text('NO BROADCASTS YET', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    ],
                  ),
                ),
              )
            else
              ...busStore.notifications.asMap().entries.map((entry) {
                final i = entry.key;
                final n = entry.value;
                final isInfo = n.type == 'info';
                final accent = isInfo ? const Color(0xFF6C63FF) : const Color(0xFFFF2E63);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161420),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(isInfo ? Icons.bolt_rounded : Icons.warning_rounded, color: accent, size: 16),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DIRECTIVE', style: GoogleFonts.plusJakartaSans(color: accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                            const SizedBox(height: 4),
                            Text(n.message, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 6),
                            Text(_formatTime(n.timestamp), style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: (i * 60).ms).slideX(begin: 0.1);
              }),
            const SizedBox(height: 20),
          ],
        );
      },
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes} MINS AGO';
    if (diff.inHours < 24) return '${diff.inHours} HOURS AGO';
    return '${diff.inDays} DAYS AGO';
  }

  Widget _buildMapTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) => BusMap(
        buses: busStore.allBuses,
        selectedRoute: null,
      ),
    );
  }

  void _showSystemAlertSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 50, left: 20, right: 20),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161420).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded, color: Color(0xFF00F0FF), size: 20),
              ).animate(onPlay: (controller) => controller.repeat()).shake(duration: 500.ms),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CORE DIRECTIVE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF00F0FF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 2),
                    Text(message, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showEmergencySOSOverlay(dynamic data) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xF2000000),
      transitionDuration: 400.ms,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0B14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFFF2E63), width: 3),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF2E63).withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 5),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2E63).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF2E63), size: 72),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.15,1.15), duration: 600.ms),
                  const SizedBox(height: 32),
                  Text(
                    'PRIORITY 1 SOS',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFFF2E63), fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'IMMEDIATE ATTENTION REQUIRED',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        _buildProfileTile('SOURCE', (data['role']?.toString().toUpperCase() ?? 'USER'), Icons.person_pin_rounded),
                        _buildProfileTile('ID', data['name'] ?? 'UNKNOWN', Icons.badge_rounded),
                        _buildProfileTile('LAT', data['latitude']?.toString() ?? 'N/A', Icons.location_on_rounded),
                        _buildProfileTile('LNG', data['longitude']?.toString() ?? 'N/A', Icons.location_on_rounded),
                        _buildProfileTile('TIMESTAMP', DateTime.tryParse(data['timestamp'] ?? '')?.toLocal().toString().split('.').first ?? 'NOW', Icons.timer_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2E63),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('ACKNOWLEDGE MISSION', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
        );
      },
    );
  }

  Widget _buildProfileTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6C63FF), size: 16),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const Spacer(),
          Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // Helper Widgets
  Widget _buildGlassCard({required Widget child, required int index}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161420).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool isGood) {
    return Container(
      height: 44, width: 4,
      decoration: BoxDecoration(
        color: isGood ? const Color(0xFF00F0FF) : const Color(0xFFFF2E63),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isGood ? const Color(0xFF00F0FF) : const Color(0xFFFF2E63)).withValues(alpha: 0.4),
            blurRadius: 10,
          )
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool active) {
    final color = active ? const Color(0xFF00F0FF) : const Color(0xFFFF2E63);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: const Color(0xFF6C63FF), size: 22),
      onPressed: onTap,
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: const Color(0xFF6C63FF).withValues(alpha: 0.5)),
          ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text(
            msg.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            'SYSTEMS OPERATING IN STANDBY MODE',
            style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Color _getOccupancyColor(String occ) {
    switch (occ.toLowerCase()) {
      case 'low': return const Color(0xFF00F0FF);
      case 'medium': return Colors.orangeAccent;
      case 'high': return const Color(0xFFFF2E63);
      default: return const Color(0xFF6C63FF);
    }
  }

  Color _getStatusColor(String status) {
    return status == 'On-time' ? const Color(0xFF00F0FF) : Colors.orangeAccent;
  }

  // Dialogs
  void _showBusActionDialog(Bus bus) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('SYSTEM CONTROL', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('UNIT_${bus.id.substring(bus.id.length - 4).toUpperCase()}', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 32),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _buildDialogOption('Mark Operational', Icons.check_circle_rounded, const Color(0xFF00F0FF), () => _updateBus(bus, status: 'On-time')),
                    _buildDialogOption('Signal Delay', Icons.bolt_rounded, Colors.orangeAccent, () => _updateBus(bus, status: 'Delayed')),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(color: Colors.white10),
                    ),
                    Text('SECTOR REASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 16),
                    ..._routes.map((r) => _buildDialogOption(
                      r.name.toUpperCase(), 
                      Icons.radar_rounded, 
                      Color(int.parse(r.color.replaceAll('#', '0xFF'))), 
                      () => _updateBus(bus, routeId: r.id, routeName: r.name, routeColor: r.color)
                    )),
                  ],
                ),
              ),
            ],
          ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  void _showUserRouteDialog(dynamic user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('SECTOR ASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('USER: ${user['name']?.toUpperCase() ?? user['username']?.toUpperCase() ?? 'IDENTIFIED'}', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 32),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final r = _routes[index];
                    final color = Color(int.parse(r.color.replaceAll('#', '0xFF')));
                    return _buildDialogOption(r.name.toUpperCase(), Icons.hub_rounded, color, () async {
                      try {
                        await _apiService.put('manager/users/${user['_id']}', {'routeId': r.id});
                        if (!mounted) return;
                        _loadData();
                      } catch (e) {
                        debugPrint('Error assigning route: $e');
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _buildDialogOption(String title, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2))
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 16),
    );
  }

  Future<void> _updateBus(Bus bus, {String? status, String? routeId, String? routeName, String? routeColor}) async {
    try {
      await _apiService.put('buses/${bus.id}/status', {
        'status': status ?? bus.status,
        'routeId': routeId,
        'routeName': routeName,
        'routeColor': routeColor,
      });
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }
}

