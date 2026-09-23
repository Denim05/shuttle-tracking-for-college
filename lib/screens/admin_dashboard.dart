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
import 'profile_settings_screen.dart';
import '../theme/app_theme.dart';

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
    _initRealtimeStats();
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
      final results = await Future.wait([
        _apiService.get('buses'),
        _apiService.get('routes', useCache: true),
        _apiService.get('users'),
      ]);

      if (!mounted) return;
      final buses = results[0] is List ? results[0] : <dynamic>[];
      final routes = results[1] is List ? results[1] : <dynamic>[];
      final users = results[2] is List ? results[2] : <dynamic>[];

      setState(() {
        _busCount = (buses as List).length;
        _routeCount = (routes as List).length;
        _userCount = (users as List).length;
        _isApiHealthy = true;
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint('Admin stats error: $e');
      if (mounted) {
        setState(() {
          _isApiHealthy = false;
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final socketService = Provider.of<SocketService>(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'ADMIN CONSOLE', 
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800, 
            letterSpacing: 2, 
            color: Colors.white,
            fontSize: 15,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: AppColors.primaryLight, size: 20),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));
            },
          ),
          IconButton(
            icon: Icon(_isRefreshing ? Icons.sync_rounded : Icons.refresh_rounded, color: AppColors.accent, size: 20),
            onPressed: _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
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
                  top: 0,
                  left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    color: AppColors.danger.withValues(alpha: 0.9),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'CONNECTING TO FLEET NETWORK...',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(auth),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    _buildStatGrid(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('FLEET OPERATIONS'),
                    _buildAdminActionTile('Fleet Radar', Icons.radar_rounded, AppColors.primary, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const FleetRadarScreen()));
                    }),
                    _buildAdminActionTile('Fleet Maintenance', Icons.directions_bus_filled_rounded, AppColors.accent, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const FleetMaintenanceScreen()));
                    }),
                    _buildAdminActionTile('User Permissions & Roles', Icons.admin_panel_settings_rounded, AppColors.accentPurple, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPermissionsScreen()));
                    }),
                    _buildAdminActionTile('System Audit Logs', Icons.terminal_rounded, AppColors.warning, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminLogsScreen()));
                    }),
                    _buildAdminActionTile('Send Test Notification', Icons.notification_important_rounded, AppColors.danger, () {
                      NotificationService().showNotification(
                        title: 'SYSTEM TEST',
                        body: 'Test notification delivered successfully.',
                      );
                    }),
                    const SizedBox(height: 24),
                    _buildSectionHeader('INFRASTRUCTURE HEALTH'),
                    _buildHealthCard('Main API Node', _isApiHealthy),
                    _buildHealthCard('Database Cluster', _isApiHealthy),
                    _buildHealthCard('Real-time Socket', _isSocketConnected),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AuthService auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SISTEC CAMPUS RADAR',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(color: AppColors.accentGreen, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SYSTEM OPERATIONAL', 
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, 
                            fontSize: 12, 
                            fontWeight: FontWeight.w800, 
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.shield_outlined, color: AppColors.primaryLight, size: 18),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildStatGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _buildStatCard('ACTIVE BUSES', _busCount.toString(), Icons.directions_bus_rounded, AppColors.primary),
        _buildStatCard('CAMPUS ROUTES', _routeCount.toString(), Icons.hub_rounded, AppColors.accent),
        _buildStatCard('REGISTERED USERS', _userCount.toString(), Icons.people_alt_outlined, AppColors.accentPurple),
        _buildStatCard('SYSTEM UPTIME', '99.9%', Icons.bolt_rounded, AppColors.accentGreen),
      ],
    ).animate().fadeIn(delay: 150.ms);
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.7), shape: BoxShape.circle),
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
                    fontSize: 22, 
                    color: Colors.white, 
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label, 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted, 
                  fontSize: 8.5, 
                  fontWeight: FontWeight.w800, 
                  letterSpacing: 1.0,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title, 
        style: GoogleFonts.plusJakartaSans(
          color: AppColors.textMuted, 
          fontSize: 10, 
          fontWeight: FontWeight.w800, 
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _buildAdminActionTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title, 
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white, 
                      fontWeight: FontWeight.w700, 
                      fontSize: 13.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHealthCard(String service, bool isHealthy) {
    final color = isHealthy ? AppColors.accentGreen : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color, 
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    service, 
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white, 
                      fontWeight: FontWeight.w700, 
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isHealthy ? 'HEALTHY' : 'UNREACHABLE', 
              style: GoogleFonts.plusJakartaSans(
                color: color,
                fontSize: 9, 
                fontWeight: FontWeight.w800, 
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
