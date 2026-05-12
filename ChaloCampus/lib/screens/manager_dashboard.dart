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
import 'registration_manager_screen.dart';

import 'package:url_launcher/url_launcher.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  // _buses removed â€” fleet data now comes from BusStore (Consumer<BusStore>)
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
    // âš ï¸ Do NOT call listenToBusUpdates here â€” that would overwrite BusStore's
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

  Future<void> _downloadReport({String? busId}) async {
    final uri = busId != null 
        ? 'https://smart-shuttle-backend-2h13.onrender.com/api/manager/reports/bus-trip-report?busId=$busId'
        : 'https://smart-shuttle-backend-2h13.onrender.com/api/manager/reports/bus-trip-report';
        
    final url = Uri.parse(uri);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloading ${busId != null ? 'Bus' : 'Fleet'} Report...'), backgroundColor: Colors.blueAccent),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open report download link'), backgroundColor: Colors.redAccent),
        );
      }
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
      length: 7,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
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
                      colors: [Color(0xFF0F172A), Color(0xFF121212)],
                    ),
                  ),
                ),

                if (!isConnected)
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
                    left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.redAccent.withOpacity(0.8),
                      child: Center(
                        child: Text(
                          'ðŸ“¡ Connecting...',
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
                                    decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                                  ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.seconds),
                                  const SizedBox(width: 8),
                                  Text('Admin Panel', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _buildAppBarAction(Icons.download_rounded, _downloadReport),
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
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.1)),
                      ),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicator: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurpleAccent.withOpacity(0.2),
                              Colors.blueAccent.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
                        ),
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.blueAccent,
                        unselectedLabelColor: Colors.white24,
                        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 10),
                        tabs: [
                          const Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: 'Fleet'),
                          const Tab(icon: Icon(Icons.map_rounded, size: 20), text: 'Map'),
                          const Tab(icon: Icon(Icons.badge_rounded, size: 20), text: 'Drivers'),
                          const Tab(icon: Icon(Icons.people_alt_rounded, size: 20), text: 'Users'),
                          const Tab(icon: Icon(Icons.assignment_ind_rounded, size: 20), text: 'Register'),
                          const Tab(icon: Icon(Icons.route_rounded, size: 20), text: 'Routes'),
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
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${store.unreadCount > 9 ? '9+' : store.unreadCount}',
                                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
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
                              RegistrationManagerScreen(routes: _routes),
                              _buildRoutesTab(),
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
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
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
        baseColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.white.withOpacity(0.1),
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
                  _buildAnalyticsCard('FLEET CAPACITY', '$activeBuses/${buses.length}', Icons.sensors_rounded, Colors.deepPurpleAccent),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('OPTIMIZED', '$onTimeBuses', Icons.bolt_rounded, Colors.blueAccent),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('ANOMALIES', '$delayedBuses', Icons.error_outline_rounded, Colors.redAccent),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('Total Users', '${_users.length}', Icons.query_stats_rounded, Colors.white),
                ],
              ).animate().slideX(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(),
            ),
            // Fleet List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                backgroundColor: const Color(0xFF0D0B14),
                color: Colors.deepPurpleAccent,
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
                                        'Route: ${bus.routeName.toUpperCase()}',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    // â”€â”€ Live speed badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                                    if (bus.status != 'Offline')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                                        ),
                                        child: Text(
                                          '${bus.speed.toStringAsFixed(1)} KM/H',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.blueAccent,
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
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildActionButton(Icons.bar_chart_rounded, () => _showBusReportSheet(bus)),
                              const SizedBox(height: 8),
                              _buildActionButton(Icons.tune_rounded, () => _showBusActionDialog(bus)),
                            ],
                          ),
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
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
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
              color: color.withOpacity(0.1),
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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))
              ),
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
                        (isActive ? Colors.deepPurpleAccent : Colors.redAccent).withOpacity(0.2),
                        (isActive ? Colors.blueAccent : Colors.redAccent).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: (isActive ? Colors.deepPurpleAccent : Colors.redAccent).withOpacity(0.3)),
                  ),
                  child: Icon(Icons.shield_rounded, color: isActive ? Colors.blueAccent : Colors.redAccent),
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
                  color: const Color(0xFF1E1E1E),
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
                    color: Colors.deepPurpleAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: Colors.blueAccent, size: 20),
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
                          const Icon(Icons.location_on_rounded, color: Colors.deepPurpleAccent, size: 12),
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
            // â”€â”€ Broadcast Composer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Text('Broadcast Message', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text('Send notifications to all app users.', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.05), blurRadius: 20),
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
                            backgroundColor: Colors.blueAccent,
                            behavior: SnackBarBehavior.floating,
                            content: Text('Message sent successfully', style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
                            ? [Colors.deepPurpleAccent.withOpacity(0.4), Colors.blueAccent.withOpacity(0.4)]
                            : [Colors.deepPurpleAccent, Colors.blueAccent],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: _isSending
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Send Notification', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // â”€â”€ Live Notification Feed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Notifications', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                      ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.seconds),
                      const SizedBox(width: 6),
                      Text('REAL-TIME', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
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
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                final accent = isInfo ? Colors.deepPurpleAccent : Colors.redAccent;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.1),
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
            color: const Color(0xFF1E1E1E).withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.blueAccent, size: 20),
              ).animate(onPlay: (controller) => controller.repeat()).shake(duration: 500.ms),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CORE DIRECTIVE', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
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
                border: Border.all(color: Colors.redAccent, width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 40, spreadRadius: 5),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 72),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.15,1.15), duration: 600.ms),
                  const SizedBox(height: 32),
                  Text(
                    'Emergency Alert',
                    style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check on the driver.',
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
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Dismiss Alert', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
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
          Icon(icon, color: Colors.deepPurpleAccent, size: 16),
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
        color: const Color(0xFF1E1E1E).withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
        color: isGood ? Colors.blueAccent : Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isGood ? Colors.blueAccent : Colors.redAccent).withOpacity(0.4),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool active) {
    final color = active ? Colors.blueAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(label, style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.deepPurpleAccent, size: 22),
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
              color: Colors.deepPurpleAccent.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: Colors.deepPurpleAccent.withOpacity(0.5)),
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
            'No activity detected.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Color _getOccupancyColor(String occ) {
    switch (occ.toLowerCase()) {
      case 'low': return Colors.blueAccent;
      case 'medium': return Colors.orangeAccent;
      case 'high': return Colors.redAccent;
      default: return Colors.deepPurpleAccent;
    }
  }

  Color _getStatusColor(String status) {
    return status == 'On-time' ? Colors.blueAccent : Colors.orangeAccent;
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
            border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('SYSTEM CONTROL', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('UNIT_${bus.id.substring(bus.id.length - 4).toUpperCase()}', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 32),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _buildDialogOption('Mark Operational', Icons.check_circle_rounded, Colors.blueAccent, () => _updateBus(bus, status: 'On-time')),
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
            border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('SECTOR ASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('USER: ${user['name']?.toUpperCase() ?? user['username']?.toUpperCase() ?? 'IDENTIFIED'}', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
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
          color: color.withOpacity(0.1), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2))
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // ROUTES TAB
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildRoutesTab() {
    if (_routes.isEmpty) return _buildEmptyState('No routes configured', Icons.route_rounded);
    return RefreshIndicator(
      onRefresh: _loadData,
      backgroundColor: const Color(0xFF0D0B14),
      color: Colors.deepPurpleAccent,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _routes.length,
        itemBuilder: (context, index) {
          final route = _routes[index];
          Color routeColor;
          try {
            routeColor = Color(int.parse(route.color.replaceAll('#', '0xFF')));
          } catch (_) {
            routeColor = Colors.deepPurpleAccent;
          }
          return _buildGlassCard(
            index: index,
            child: Row(
              children: [
                Container(
                  height: 48, width: 6,
                  decoration: BoxDecoration(
                    color: routeColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: routeColor.withOpacity(0.5), blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${route.stops.length} stops',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _buildActionButton(Icons.edit_rounded, () => _showRouteEditSheet(route)),
              ],
            ),
          ).animate().fadeIn(delay: (index * 80).ms).slideY(begin: 0.2);
        },
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // ROUTE EDIT BOTTOM SHEET
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showRouteEditSheet(RouteModel route) {
    final nameCtrl = TextEditingController(text: route.name);
    // Mutable stops list â€“ copies the current stops
    final stops = route.stops
        .map((s) => {'name': s['name'] as String, 'lat': s['lat'].toString(), 'lng': s['lng'].toString()})
        .toList();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: const BoxDecoration(
              color: Color(0xFF0D0B14),
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('EDIT ROUTE', style: GoogleFonts.plusJakartaSans(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
                        ),
                        child: Text('${stops.length} STOPS',
                            style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      // Route Name Field
                      Text('ROUTE NAME', style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.07)),
                        ),
                        child: TextField(
                          controller: nameCtrl,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            hintText: 'e.g. Gandinagar Route',
                            hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Stops Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('STOPS', style: GoogleFonts.plusJakartaSans(
                              color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                          GestureDetector(
                            onTap: () {
                              setSheetState(() => stops.add({'name': '', 'lat': '0', 'lng': '0'}));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.add_rounded, color: Colors.blueAccent, size: 14),
                                const SizedBox(width: 4),
                                Text('ADD STOP', style: GoogleFonts.plusJakartaSans(
                                    color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...stops.asMap().entries.map((entry) {
                        final i = entry.key;
                        final stop = entry.value;
                        final ctrl = TextEditingController(text: stop['name']);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurpleAccent.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.3)),
                                ),
                                child: Center(
                                  child: Text('${i + 1}', style: GoogleFonts.plusJakartaSans(
                                      color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w900)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: ctrl,
                                  onChanged: (v) => stops[i]['name'] = v,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Stop nameâ€¦',
                                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setSheetState(() => stops.removeAt(i)),
                                child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                // Save Button
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 16),
                  child: GestureDetector(
                    onTap: isSaving ? null : () async {
                      setSheetState(() => isSaving = true);
                      try {
                        await _apiService.put(
                          'manager/routes/${route.id}',
                          {
                            'name': nameCtrl.text.trim(),
                            'stops': stops
                                .where((s) => s['name']!.isNotEmpty)
                                .map((s) => {
                                      'name': s['name'],
                                      'lat': double.tryParse(s['lat']!) ?? 0.0,
                                      'lng': double.tryParse(s['lng']!) ?? 0.0,
                                    })
                                .toList(),
                          },
                        );
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Route updated!',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900)),
                          backgroundColor: Colors.blueAccent,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ));
                      } catch (e) {
                        setSheetState(() => isSaving = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Save failed: $e'),
                          backgroundColor: Colors.redAccent,
                        ));
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 60,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSaving
                              ? [Colors.deepPurpleAccent.withOpacity(0.4), Colors.blueAccent.withOpacity(0.4)]
                              : [Colors.deepPurpleAccent, Colors.blueAccent],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: isSaving
                            ? const SizedBox(width: 24, height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('SAVE CHANGES', style: GoogleFonts.plusJakartaSans(
                                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
                      ),
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

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // IN-APP BUS REPORT BOTTOM SHEET
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showBusReportSheet(Bus bus) async {
    // Show loading sheet immediately
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BusReportSheet(bus: bus, apiService: _apiService, onDownload: () => _downloadReport(busId: bus.id)),
    );
  }
}


// ---------------------------------------------------------------------------
// SEPARATE STATEFUL WIDGET: In-App Bus Daily Report Sheet
// ---------------------------------------------------------------------------
class _BusReportSheet extends StatefulWidget {
  final Bus bus;
  final ApiService apiService;
  final VoidCallback onDownload;

  const _BusReportSheet({required this.bus, required this.apiService, required this.onDownload});

  @override
  State<_BusReportSheet> createState() => _BusReportSheetState();
}

class _BusReportSheetState extends State<_BusReportSheet> {
  bool _loading = true;
  Map<String, dynamic>? _report;
  String? _error;
  final Set<int> _expandedDays = {};

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      final data = await widget.apiService.get('manager/reports/bus/${widget.bus.id}/summary');
      if (mounted) setState(() { _report = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0B14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('BUS OPERATIONS LOG',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    Text(widget.bus.routeName,
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                ),
                GestureDetector(
                  onTap: () { Navigator.pop(context); widget.onDownload(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.download_rounded, color: Colors.blueAccent, size: 16),
                      const SizedBox(width: 6),
                      Text('CSV',
                          style: GoogleFonts.plusJakartaSans(
                              color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2))
                  : _error != null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 12),
                            Text('Failed to load report',
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
                          ]),
                        )
                      : _buildReportContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent() {
    final busInfo      = _report!['bus']           as Map<String, dynamic>;
    final routeInfo    = _report!['route']         as Map<String, dynamic>?;
    final summary      = _report!['summary']       as Map<String, dynamic>;
    final dailyRecords = (_report!['dailyRecords'] as List<dynamic>?) ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        // Bus Identity Card
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
          ),
          child: Column(children: [
            _infoRow(Icons.directions_bus_rounded, 'Bus Number',
                busInfo['busNumber']?.toString() ?? 'N/A', Colors.blueAccent),
            const Divider(color: Colors.white10, height: 20),
            _infoRow(Icons.person_rounded, 'Driver',
                busInfo['driverName']?.toString() ?? 'N/A', Colors.deepPurpleAccent),
            const Divider(color: Colors.white10, height: 20),
            _infoRow(Icons.alt_route_rounded, 'Route',
                busInfo['routeName']?.toString() ?? 'N/A', Colors.orangeAccent),
            if (routeInfo != null) ...[
              const Divider(color: Colors.white10, height: 20),
              _infoRow(Icons.trip_origin_rounded, 'Origin Stop',
                  routeInfo['originStop']?.toString() ?? 'N/A', Colors.greenAccent),
              const Divider(color: Colors.white10, height: 20),
              _infoRow(Icons.school_rounded, 'Campus Stop',
                  routeInfo['campusStop']?.toString() ?? 'Campus', Colors.cyanAccent),
              const Divider(color: Colors.white10, height: 20),
              _infoRow(Icons.place_rounded, 'Total Stops',
                  '${routeInfo['totalStops']} stops', Colors.white54),
            ],
          ]),
        ),

        // KPI Grid
        Text('30-DAY SUMMARY',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.55,
          children: [
            _kpiCard('OPERATING\nDAYS',
                '${summary['totalOperatingDays']}', Icons.calendar_month_rounded, Colors.blueAccent),
            _kpiCard('ON-TIME\nPERCENT',
                '${summary['onTimePercent']}%', Icons.check_circle_rounded, Colors.greenAccent),
            _kpiCard('AVG SPEED',
                '${summary['avgSpeedKmh']} KM/H', Icons.speed_rounded, Colors.orangeAccent),
            _kpiCard('AVG STUDENTS\n/DAY',
                '${summary['avgStudentsPerDay']}', Icons.people_rounded, Colors.deepPurpleAccent),
            _kpiCard('TOTAL STUDENTS\nSERVED',
                '${summary['totalStudentsServed']}', Icons.school_rounded, Colors.cyanAccent),
            _kpiCard('DELAYED\nDAYS',
                '${summary['delayedDays']}', Icons.warning_rounded, Colors.redAccent),
          ],
        ),
        const SizedBox(height: 28),

        // Daily Log Header
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('DAILY OPERATIONS LOG',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
          Text('${dailyRecords.length} ENTRIES',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),

        // Daily Records
        ...dailyRecords.asMap().entries.map((entry) {
          final idx      = entry.key;
          final record   = entry.value as Map<String, dynamic>;
          final isOnTime = record['status'] == 'On-time';
          final accent   = isOnTime ? Colors.blueAccent : Colors.orangeAccent;
          final expanded = _expandedDays.contains(idx);
          final timeline = (record['stopTimeline'] as List<dynamic>?) ?? [];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.15)),
            ),
            child: Column(children: [
              // Day summary row
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Date chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withOpacity(0.25)),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(record['dayName']?.toString() ?? '',
                          style: GoogleFonts.plusJakartaSans(
                              color: accent, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      Text(
                        (record['date']?.toString() ?? '').split(' ').first,
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        (record['date']?.toString() ?? '').split(' ').skip(1).join(' '),
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white54, fontSize: 8, fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  // Timings + stats
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Departure -> Arrival row
                      Row(children: [
                        const Icon(Icons.arrow_circle_right_rounded, color: Colors.greenAccent, size: 12),
                        const SizedBox(width: 4),
                        Text(record['departureTime']?.toString() ?? '',
                            style: GoogleFonts.plusJakartaSans(
                                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('->',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11)),
                        ),
                        const Icon(Icons.school_rounded, color: Colors.cyanAccent, size: 12),
                        const SizedBox(width: 4),
                        Text(record['arrivalTime']?.toString() ?? '',
                            style: GoogleFonts.plusJakartaSans(
                                color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 6),
                      // Route info
                      Text(
                        '${record['originStop'] ?? ''} -> ${record['destinationStop'] ?? ''}',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      // Stats chips
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        _statChip(Icons.timer_rounded, '${record['tripDurationMins']} min'),
                        _statChip(Icons.people_rounded, '${record['studentCount']} students'),
                        _statChip(Icons.speed_rounded, '${record['avgSpeedKmh']} km/h avg'),
                        _statChip(Icons.directions_run_rounded, '${record['maxSpeedKmh']} km/h max'),
                        _statChip(Icons.place_rounded, '${record['totalStops']} stops'),
                        _statChip(Icons.person_rounded, record['driverName']?.toString() ?? 'N/A'),
                      ]),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  // Status badge + expand toggle
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accent.withOpacity(0.25)),
                      ),
                      child: Text(
                        isOnTime ? 'ON\nTIME' : 'LATE',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            color: accent, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                      ),
                    ),
                    if (!isOnTime && (record['delayMins'] ?? 0) > 0) ...[
                      const SizedBox(height: 3),
                      Text('+${record['delayMins']}m',
                          style: GoogleFonts.plusJakartaSans(
                              color: Colors.orangeAccent, fontSize: 8, fontWeight: FontWeight.w700)),
                    ],
                    if (timeline.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          if (expanded) _expandedDays.remove(idx); else _expandedDays.add(idx);
                        }),
                        child: Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white24,
                          size: 20,
                        ),
                      ),
                    ],
                  ]),
                ]),
              ),

              // Expandable stop timeline
              if (expanded && timeline.isNotEmpty) ...[
                const Divider(color: Colors.white10, height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('STOP-BY-STOP PICKUP TIMELINE',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    ...timeline.asMap().entries.map((stopEntry) {
                      final stop    = stopEntry.value as Map<String, dynamic>;
                      final isFirst = stop['isOrigin'] == true;
                      final isLast  = stop['isCampus'] == true;
                      final dotCol  = isFirst
                          ? Colors.greenAccent
                          : isLast
                              ? Colors.cyanAccent
                              : Colors.white24;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: dotCol,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: dotCol.withOpacity(0.5), blurRadius: 5)],
                              ),
                            ),
                            if (stopEntry.key < timeline.length - 1)
                              Container(width: 1, height: 24, color: Colors.white10),
                          ]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      stop['stopName']?.toString() ?? '',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isFirst || isLast ? Colors.white : Colors.white54,
                                        fontSize: 11,
                                        fontWeight: isFirst || isLast
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    stop['time']?.toString() ?? '',
                                    style: GoogleFonts.plusJakartaSans(
                                        color: dotCol, fontSize: 10, fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ]),
                ),
              ],
            ]),
          ).animate().fadeIn(delay: (idx * 35).ms).slideY(begin: 0.08);
        }),
      ],
    );
  }

  Widget _statChip(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: Colors.white24),
      const SizedBox(width: 3),
      Text(text, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9.5)),
    ]);
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 15),
      ),
      const SizedBox(width: 12),
      Text(label,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700)),
      const Spacer(),
      Flexible(
        child: Text(value,
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 15),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)),
              ),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ]),
    );
  }
}
