import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  
  int _busCount = 0;
  int _routeCount = 0;
  int _userCount = 0;
  bool _isRefreshing = false;
  bool _isSocketConnected = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _initRealtimeStats();
  }

  void _initRealtimeStats() {
    _socketService.initSocket();
    
    // Listen for connection status using standard .on() syntax
    _socketService.socket?.on('connect', (_) {
      if (mounted) setState(() => _isSocketConnected = true);
    });
    
    _socketService.socket?.on('disconnect', (_) {
      if (mounted) setState(() => _isSocketConnected = false);
    });

    // Listen for live stat updates
    _socketService.socket?.on('statsUpdate', (data) {
      if (mounted) {
        setState(() {
          _busCount = data['busCount'] ?? _busCount;
          _routeCount = data['routeCount'] ?? _routeCount;
          _userCount = data['userCount'] ?? _userCount;
        });
      }
    });
  }

  @override
  void dispose() {
    _socketService.dispose();
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
    return Scaffold(
      backgroundColor: const Color(0xFF02040A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ADMIN CONSOLE', 
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w900, 
            letterSpacing: 2, 
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isRefreshing ? Icons.sync : Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () => auth.logout(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.5, -0.6),
            radius: 1.5,
            colors: [Color(0xFF0F172A), Color(0xFF02040A)],
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
                    _buildSectionHeader('CORE MANAGEMENT'),
                    _buildAdminActionTile('Fleet Maintenance', Icons.directions_bus_filled_rounded, Colors.blueAccent, () {}),
                    _buildAdminActionTile('User Permissions', Icons.admin_panel_settings_rounded, Colors.purpleAccent, () {}),
                    _buildAdminActionTile('System Logs', Icons.terminal_rounded, Colors.orangeAccent, () {}),
                    const SizedBox(height: 32),
                    _buildSectionHeader('SERVICE HEALTH'),
                    _buildHealthCard('Main API Node', true),
                    _buildHealthCard('MongoDB Cluster', true),
                    _buildHealthCard('Real-time Socket', _isSocketConnected),
                    const SizedBox(height: 40),
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
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF38ef7d).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF38ef7d).withValues(alpha: 0.2)),
            ),
            child: Text('ROOT ACCESS', style: GoogleFonts.outfit(color: const Color(0xFF38ef7d), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
          const SizedBox(height: 12),
          Text(
            auth.currentUser?.username.toUpperCase() ?? 'ADMINISTRATOR', 
            style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
          ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  Widget _buildStatGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 16) / 2;
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.2, // Improved aspect ratio to prevent overflow
          children: [
            _buildStatCard('FLEET', _busCount.toString(), Icons.directions_bus_rounded, const Color(0xFF3B82F6)),
            _buildStatCard('ROUTES', _routeCount.toString(), Icons.map_rounded, const Color(0xFF10B981)),
            _buildStatCard('USERS', _userCount.toString(), Icons.people_alt_rounded, const Color(0xFF8B5CF6)),
            _buildStatCard('UPTIME', '99.9%', Icons.bolt_rounded, const Color(0xFFF59E0B)),
          ],
        );
      }
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value, 
                        style: GoogleFonts.outfit(
                          fontSize: 28, 
                          color: Colors.white, 
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1
                        ),
                      ),
                    ),
                    Text(
                      label, 
                      style: GoogleFonts.outfit(
                        color: Colors.white38, 
                        fontSize: 10, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 1.5
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(title, style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }

  Widget _buildAdminActionTile(String title, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
      ),
    ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1);
  }

  Widget _buildHealthCard(String service, bool isHealthy) {
    final color = isHealthy ? const Color(0xFF10B981) : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
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
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                  ).animate(onPlay: (controller) => controller.repeat())
                   .scale(duration: 1.seconds, begin: const Offset(1, 1), end: const Offset(2.5, 2.5))
                   .fadeOut(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Text(
                service, 
                style: GoogleFonts.outfit(
                  color: Colors.white70, 
                  fontWeight: FontWeight.w600, 
                  fontSize: 16
                )
              ),
            ],
          ),
          Text(
            isHealthy ? 'STABLE' : 'ERROR', 
            style: GoogleFonts.outfit(
              color: color.withValues(alpha: 0.8), 
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

