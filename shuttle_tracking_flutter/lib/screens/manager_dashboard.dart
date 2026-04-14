import 'dart:ui';
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
import '../components/bus_map.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<Bus> _buses = [];
  List<RouteModel> _routes = [];
  List<dynamic> _users = []; // Renamed from _students
  List<dynamic> _drivers = [];
  final SocketService _socketService = SocketService();

  @override
  void initState() {
    super.initState();
    _loadData();
    _initSocket();
  }

  void _initSocket() {
    _socketService.initSocket();
    _socketService.listenToBusUpdates((data) {
      if (mounted) {
        setState(() {
          final updatedBus = Bus.fromJson(data);
          final index = _buses.indexWhere((b) => b.id == updatedBus.id);
          if (index != -1) {
            _buses[index] = updatedBus;
          } else {
            _buses.add(updatedBus);
          }
        });
      }
    });

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

  @override
  void dispose() {
    _socketService.dispose();
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
        _buses = (busData as List).map((b) => Bus.fromJson(b)).toList();
        _routes = (routeData as List).map((r) => RouteModel.fromJson(r)).toList();
        _users = userData as List;
        _drivers = driverData as List;
        _isLoading = false;
      });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please logout and login again.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seed failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFF02040A), // Deepest black-blue
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 80,
          title: Text(
            'Transport Authority',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.2),
          actions: [
            _buildAppBarAction(Icons.auto_awesome_rounded, _seedDatabase),
            _buildAppBarAction(Icons.refresh_rounded, _loadData),
            _buildAppBarAction(Icons.logout_rounded, () => auth.logout()),
            const SizedBox(width: 16),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
                  ),
                  child: TabBar(
                    indicatorColor: const Color(0xFF1A4CFF),
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 3,
                    labelColor: const Color(0xFF1A4CFF),
                    unselectedLabelColor: Colors.white54,
                    labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: const [
                      Tab(icon: Icon(Icons.directions_bus_rounded, size: 20), text: 'Fleet'),
                      Tab(icon: Icon(Icons.map_rounded, size: 20), text: 'Live Map'),
                      Tab(icon: Icon(Icons.person_pin_rounded, size: 20), text: 'Drivers'),
                      Tab(icon: Icon(Icons.group_rounded, size: 20), text: 'Users'),
                      Tab(icon: Icon(Icons.notification_important_rounded, size: 20), text: 'Alerts'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.5,
              colors: [Color(0xFF0F172A), Color(0xFF02040A)],
            ),
          ),
          child: SafeArea(
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
    if (_buses.isEmpty) return _buildEmptyState('No fleet active', Icons.bus_alert_rounded);
    
    final int activeBuses = _buses.where((b) => b.status != 'Offline').length;
    final int onTimeBuses = _buses.where((b) => b.status == 'On-time').length;
    final int delayedBuses = _buses.where((b) => b.status == 'Delayed').length;

    return Column(
      children: [
        // Analytics Header
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              _buildAnalyticsCard('Active Fleet', '$activeBuses/${_buses.length}', Icons.directions_bus_rounded, Colors.blueAccent),
              const SizedBox(width: 12),
              _buildAnalyticsCard('On-Time', '$onTimeBuses', Icons.check_circle_outline, Colors.greenAccent),
              const SizedBox(width: 12),
              _buildAnalyticsCard('Delayed', '$delayedBuses', Icons.access_time_rounded, Colors.orangeAccent),
              const SizedBox(width: 12),
              _buildAnalyticsCard('Total Users', '${_users.length}', Icons.people_outline, Colors.purpleAccent),
              const SizedBox(width: 12),
              _buildAnalyticsCard('Total Drivers', '${_drivers.length}', Icons.badge_outlined, Colors.tealAccent),
            ],
          ).animate().slideX(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(),
        ),
        // Existing Fleet List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            backgroundColor: const Color(0xFF0F172A),
            color: const Color(0xFF1A4CFF),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: _buses.length,
              itemBuilder: (context, index) {
                final bus = _buses[index];
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
                              'Bus #${bus.id.substring(bus.id.length - 4).toUpperCase()}',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Route: ${bus.routeName}',
                              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
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
                      _buildActionButton(Icons.settings_outlined, () => _showBusActionDialog(bus)),
                    ],
                  ),
                ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.2);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
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
                  height: 50, width: 50,
                  decoration: BoxDecoration(
                    color: (isActive ? const Color(0xFF1A4CFF) : Colors.redAccent).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: (isActive ? const Color(0xFF1A4CFF) : Colors.redAccent).withValues(alpha: 0.2)),
                  ),
                  child: Icon(Icons.person_rounded, color: isActive ? const Color(0xFF1A4CFF) : Colors.redAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver['name'] ?? driver['username'],
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        'Bus: ${driver['assignedBus'] ?? 'Unassigned'}',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(isActive ? 'ACTIVE' : 'SUSPENDED', isActive),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  color: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  onSelected: (value) async {
                    final newStatus = value == 'Suspend' ? 'Suspended' : 'Active';
                    await _apiService.put('manager/drivers/${driver['_id']}', {'status': newStatus});
                    _loadData();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: isActive ? 'Suspend' : 'Activate',
                      child: Text(isActive ? 'Suspend' : 'Activate', style: const TextStyle(color: Colors.white)),
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
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: Colors.white70),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['name'] ?? user['username'] ?? 'Unknown', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('UID: ${user['userId'] ?? user['studentId'] ?? user['roll'] ?? 'N/A'}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      Text('📍 ${user['pickupPoint'] ?? 'Not set'}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
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
    final controller = TextEditingController();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Broadcast System Alert', style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Send real-time notifications to all users and drivers.', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  maxLines: 5,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type your message here...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    if (controller.text.isEmpty) return;
                    try {
                      await _apiService.post('manager/notifications', {'message': controller.text});
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.greenAccent,
                          behavior: SnackBarBehavior.floating,
                          content: Text('Broadcast Sent Successfully!', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      );
                      controller.clear();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                  },
                  child: Container(
                    height: 56,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1A4CFF), Color(0xFF6366F1)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF1A4CFF).withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5)),
                      ],
                    ),
                    child: Center(
                      child: Text('BROADCAST NOW', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildMapTab() {
    return BusMap(buses: _buses, selectedRoute: null);
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
            color: const Color(0xFF0F1528).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1A4CFF).withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF1A4CFF).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A4CFF).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF1A4CFF), size: 20),
              ).animate(onPlay: (controller) => controller.repeat()).shake(duration: 500.ms),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SYSTEM ALERT', style: GoogleFonts.outfit(color: const Color(0xFF1A4CFF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text(message, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14)),
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
      barrierColor: Colors.black87,
      transitionDuration: 400.ms,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1a0000),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.redAccent, width: 4),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withValues(alpha: 0.6), blurRadius: 40, spreadRadius: 10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 64),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2), duration: 500.ms),
                  const SizedBox(height: 24),
                  Text(
                    'SOS EMERGENCY',
                    style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Triggered by ${data['role']?.toString().toUpperCase() ?? 'USER'}',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    data['name'] ?? 'Unknown Individual',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        _buildProfileTile('LATITUDE', data['latitude']?.toString() ?? 'N/A', Icons.pin_drop),
                        _buildProfileTile('LONGITUDE', data['longitude']?.toString() ?? 'N/A', Icons.pin_drop),
                        _buildProfileTile('TIME', DateTime.tryParse(data['timestamp'] ?? '')?.toLocal().toString().split('.').first ?? 'Now', Icons.access_time),
                        if (data['busId'] != null || data['routeId'] != null)
                          _buildProfileTile('CONTEXT', data['routeName'] ?? data['busId'] ?? 'N/A', Icons.bus_alert),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('ACKNOWLEDGE & DISMISS', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.9, 0.9)),
        );
      },
    );
  }

  Widget _buildProfileTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Text('$label:', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // Helper Widgets
  Widget _buildGlassCard({required Widget child, required int index}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool isGood) {
    return Container(
      height: 40, width: 6,
      decoration: BoxDecoration(
        color: isGood ? Colors.greenAccent : Colors.orangeAccent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isGood ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: 0.5),
            blurRadius: 8,
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
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool active) {
    final color = active ? Colors.greenAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white38, size: 22),
      onPressed: onTap,
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          Text(msg, style: GoogleFonts.outfit(color: Colors.white24, fontSize: 18)),
        ],
      ),
    );
  }

  Color _getOccupancyColor(String occ) {
    switch (occ.toLowerCase()) {
      case 'low': return Colors.greenAccent;
      case 'medium': return Colors.orangeAccent;
      case 'high': return Colors.redAccent;
      default: return Colors.blueAccent;
    }
  }

  Color _getStatusColor(String status) {
    return status == 'On-time' ? Colors.greenAccent : Colors.orangeAccent;
  }

  // Dialogs
  void _showBusActionDialog(Bus bus) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 24),
                Text('SYSTEM CONTROL', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                Text('MANAGE BUS #${bus.id.substring(bus.id.length - 4).toUpperCase()}', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      _buildDialogOption('Mark On-time', Icons.check_circle_rounded, Colors.greenAccent, () => _updateBus(bus, status: 'On-time')),
                      _buildDialogOption('Mark Delayed', Icons.access_time_filled_rounded, Colors.orangeAccent, () => _updateBus(bus, status: 'Delayed')),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Divider(color: Colors.white10),
                      ),
                      Text('REASSIGN TO ROUTE', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                      const SizedBox(height: 16),
                      ..._routes.map((r) => _buildDialogOption(
                        r.name, 
                        Icons.route_rounded, 
                        Color(int.parse(r.color.replaceAll('#', '0xFF'))), 
                        () => _updateBus(bus, routeId: r.id, routeName: r.name, routeColor: r.color)
                      )).toList(),
                    ],
                  ),
                ),
              ],
            ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
          ),
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
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 24),
                Text('ROUTE ASSIGNMENT', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                Text('ASSIGNING FOR ${user['name']?.toUpperCase() ?? user['username']?.toUpperCase() ?? 'USER'}', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _routes.length,
                    itemBuilder: (context, index) {
                      final r = _routes[index];
                      final color = Color(int.parse(r.color.replaceAll('#', '0xFF')));
                      return _buildDialogOption(r.name, Icons.map_rounded, color, () async {
                        await _apiService.put('manager/users/${user['_id']}', {'routeId': r.id});
                        if (!mounted) return;
                        Navigator.pop(context);
                        _loadData();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
          ),
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
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
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

