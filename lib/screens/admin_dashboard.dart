import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';

import 'admin_logs_screen.dart';
import 'fleet_maintenance_screen.dart';
import 'fleet_radar_screen.dart';
import 'admin_permissions_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final ApiService _apiService = ApiService();
  late SocketService _socketService;
  
  int _busCount = 0;
  int _routeCount = 0;
  int _userCount = 0;
  bool _isRefreshing = false;
  bool _isSocketConnected = false;
  bool _isApiHealthy = false;

  @override
  void initState() {
    super.initState();
    _socketService = Provider.of<SocketService>(context, listen: false);
    _loadStats();
    _checkApiHealth();
    _initRealtimeStats();
  }

  Future<void> _checkApiHealth() async {
    try {
      await _apiService.get('buses'); // Assumes a /health endpoint
      if (mounted) setState(() => _isApiHealthy = true);
    } catch (_) {
      if (mounted) setState(() => _isApiHealthy = false);
    }
  }

  void _initRealtimeStats() {
    // Sync socket connected status with the SocketService ValueNotifier
    _socketService.connectionStatus.addListener(_onConnectionChanged);
    _isSocketConnected = _socketService.isConnected;

    // Listen for live stat updates via the clean SocketService wrapper
    _socketService.listenToStatsUpdate((data) {
      if (mounted) {
        setState(() {
          _busCount   = data['busCount']   ?? _busCount;
          _routeCount = data['routeCount'] ?? _routeCount;
          _userCount  = data['userCount']  ?? _userCount;
        });
      }
    });
  }

  void _onConnectionChanged() {
    if (mounted) {
      setState(() => _isSocketConnected = _socketService.isConnected);
    }
  }

  @override
  void dispose() {
    _socketService.connectionStatus.removeListener(_onConnectionChanged);
    _socketService.off('statsUpdate');
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _isRefreshing = true);
    try {
      final buses = await _apiService.get('buses');
      final routes = await _apiService.get('routes');
      final users = await _apiService.get('users');
      
      if (!mounted) return;
      setState(() {
        _busCount = (buses as List).length;
        _routeCount = (routes as List).length;
        _userCount = (users as List).length;
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint('Admin stats error: $e');
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context);
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Admin Panel', 
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w900, 
            letterSpacing: 3, 
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isRefreshing ? Icons.sync : Icons.refresh_rounded, color: Colors.blueAccent),
            onPressed: _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent),
            onPressed: () => auth.logout(),
          ),
          const SizedBox(width: 8),
        ],
      ),
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
                    color: Colors.redAccent.withOpacity(0.8),
                    child: Center(
                      child: Text(
                        '📡 Connecting...',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
                ),
            ],
          );
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.5, -0.6),
              radius: 1.5,
              colors: [Color(0xFF0F172A), Color(0xFF121212)],
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(auth),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                      _buildStatGrid(),
                      const SizedBox(height: 32),
                      _buildSectionHeader('MANAGEMENT'),
                      _buildAdminActionTile('Fleet Radar', Icons.radar_rounded, Colors.blueAccent, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const FleetRadarScreen()));
                      }),
                      _buildAdminActionTile('Send Test Notification', Icons.notification_important_rounded, Colors.redAccent, () {
                        NotificationService().showNotification(
                          title: 'SYSTEM TEST',
                          body: 'Test notification sent successfully.',
                        );
                      }),
                      _buildAdminActionTile('Fleet Maintenance', Icons.directions_bus_filled_rounded, Colors.blueAccent, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const FleetMaintenanceScreen()));
                      }),
                      _buildAdminActionTile('User Permissions', Icons.admin_panel_settings_rounded, Colors.purpleAccent, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPermissionsScreen()));
                      }),
                      _buildAdminActionTile('System Logs', Icons.terminal_rounded, Colors.orangeAccent, () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminLogsScreen()));
                      }),
                      const SizedBox(height: 32),
                      _buildSectionHeader('SERVICE HEALTH'),
                      _buildHealthCard('Main API Node', _isApiHealthy),
                      _buildHealthCard('Database Cluster', _isApiHealthy),
                      _buildHealthCard('Real-time Socket', _isSocketConnected),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AuthService auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
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
                  Text('SYSTEM ACTIVE', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.deepPurpleAccent.withOpacity(0.1), Colors.blueAccent.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
            ),
            child: const Icon(Icons.terminal_rounded, color: Colors.blueAccent, size: 20),
          ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildStatGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.5,
          children: [
            _buildStatCard('FLEET COUNT', _busCount.toString(), Icons.sensors_rounded, Colors.deepPurpleAccent),
            _buildStatCard('ROUTES', _routeCount.toString(), Icons.hub_rounded, Colors.blueAccent),
            _buildStatCard('Total Users', _userCount.toString(), Icons.query_stats_rounded, Colors.white),
            _buildStatCard('UPTIME', '99.9%', Icons.bolt_rounded, Colors.redAccent),
          ],
        );
      }
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Color(0xFF1E1E1E),
        border: Border.all(color: color.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.02), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                Container(
                  width: 4, height: 4,
                  decoration: BoxDecoration(color: color.withOpacity(0.5), shape: BoxShape.circle),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value, 
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24, 
                      color: Colors.white, 
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1
                    ),
                  ),
                ),
                Text(
                  label, 
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white38, 
                    fontSize: 7.5, 
                    fontWeight: FontWeight.w900, 
                    letterSpacing: 1.8
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
    );
  }

  Widget _buildAdminActionTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(title.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 16),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1);
  }

  Widget _buildHealthCard(String service, bool isHealthy) {
    final color = isHealthy ? Colors.blueAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E).withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                  ).animate(onPlay: (controller) => controller.repeat())
                   .scale(duration: 1.5.seconds, begin: const Offset(1, 1), end: const Offset(3, 3))
                   .fadeOut(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color, 
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)]
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Text(
                service.toUpperCase(), 
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70, 
                  fontWeight: FontWeight.w900, 
                  fontSize: 13,
                  letterSpacing: 1
                )
              ),
            ],
          ),
          Text(
            isHealthy ? 'OK' : 'ISSUE', 
            style: GoogleFonts.plusJakartaSans(
              color: color,
              fontSize: 10, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 2
            ),
          )
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideX(begin: 0.1);
  }
}



