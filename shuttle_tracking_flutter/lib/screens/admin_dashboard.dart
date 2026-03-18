import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final ApiService _apiService = ApiService();
  int _busCount = 0;
  int _routeCount = 0;
  int _userCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final buses = await _apiService.get('buses');
      final routes = await _apiService.get('routes');
      final users = await _apiService.get('users');
      
      setState(() {
        _busCount = (buses as List).length;
        _routeCount = (routes as List).length;
        _userCount = (users as List).length;
      });
    } catch (e) {
      debugPrint('Admin stats error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117), // Premium dark background
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        elevation: 0,
        title: Text('Admin Console', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => auth.logout(),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.5, -0.6),
            radius: 1.5,
            colors: [Color(0xFF1A2634), Color(0xFF0D1117), Colors.black], // Premium Admin Gradient
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SYSTEM ADMIN', style: GoogleFonts.outfit(color: const Color(0xFF38ef7d), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    Text(auth.currentUser?.username ?? 'Admin', 
                         style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  children: [
                    _buildStatGrid(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('CORE MANAGEMENT'),
                    _buildAdminActionTile('User Management', Icons.person_search, () {}),
                    _buildAdminActionTile('Route Configuration', Icons.alt_route, () {}),
                    _buildAdminActionTile('Global Notifications', Icons.campaign, () {}),
                    const SizedBox(height: 32),
                    _buildSectionHeader('SYSTEM HEALTH'),
                    _buildHealthCard('API Server', true),
                    _buildHealthCard('Database Cluster', true),
                    _buildHealthCard('Socket Gateway', true),
                    const SizedBox(height: 48), // Bottom padding
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('Buses', _busCount.toString(), Icons.directions_bus),
        _buildStatCard('Routes', _routeCount.toString(), Icons.map),
        _buildStatCard('Users', _userCount.toString(), Icons.people),
        _buildStatCard('Active', 'LIVE', Icons.bolt, color: const Color(0xFF38ef7d)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, {Color? color}) {
    final cardColor = color ?? const Color(0xFF38ef7d);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.05),
            blurRadius: 20,
            spreadRadius: -5,
          )
        ]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: cardColor, size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: GoogleFonts.outfit(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(title, style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }

  Widget _buildAdminActionTile(String title, IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            onTap: onTap,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF38ef7d).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF38ef7d).withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: const Color(0xFF38ef7d), size: 22),
            ),
            title: Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHealthCard(String service, bool isHealthy) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(isHealthy ? Icons.check_circle_outline : Icons.error_outline, 
                         color: isHealthy ? const Color(0xFF38ef7d) : Colors.redAccent, size: 20),
                    const SizedBox(width: 12),
                    Text(service, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHealthy ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isHealthy ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6, 
                        height: 6, 
                        decoration: BoxDecoration(
                          color: isHealthy ? const Color(0xFF38ef7d) : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: (isHealthy ? const Color(0xFF38ef7d) : Colors.redAccent).withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)
                          ]
                        )
                      ),
                      const SizedBox(width: 6),
                      Text(isHealthy ? 'ONLINE' : 'OFFLINE', 
                           style: TextStyle(color: isHealthy ? const Color(0xFF38ef7d) : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
