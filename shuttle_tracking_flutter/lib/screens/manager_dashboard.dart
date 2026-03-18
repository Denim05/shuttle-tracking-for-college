import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';

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
  List<dynamic> _students = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final busData = await _apiService.get('buses');
      final routeData = await _apiService.get('routes');
      final studentData = await _apiService.get('manager/students');
      
      setState(() {
        _buses = (busData as List).map((b) => Bus.fromJson(b)).toList();
        _routes = (routeData as List).map((r) => RouteModel.fromJson(r)).toList();
        _students = studentData as List;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading manager data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0f2027),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Transport Authority', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadData,
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => auth.logout(),
            )
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF38ef7d),
            labelColor: Color(0xFF38ef7d),
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.directions_bus), text: 'Bus'),
              Tab(icon: Icon(Icons.people), text: 'Students'),
              Tab(icon: Icon(Icons.notification_important), text: 'Alerts'),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0f2027), Color(0xFF203a43)],
            ),
          ),
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF38ef7d)))
            : TabBarView(
                children: [
                  _buildFleetTab(),
                  _buildStudentTab(),
                  _buildAlertTab(),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildFleetTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _buses.length,
      itemBuilder: (context, index) {
        final bus = _buses[index];
        return Card(
          color: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: bus.status == 'On-time' ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
              child: Icon(Icons.bus_alert, color: bus.status == 'On-time' ? Colors.green : Colors.orange),
            ),
            title: Text('Bus ID: ${bus.id.substring(bus.id.length - 4)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Route: ${bus.routeName}', style: const TextStyle(color: Colors.white70)),
                Text('Status: ${bus.status}', style: TextStyle(color: bus.status == 'On-time' ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12)),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54),
              onPressed: () => _showBusActionDialog(bus),
            ),
          ),
        );
      },
    );
  }

  void _showBusActionDialog(Bus bus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c1e),
        title: const Text('Update Bus Status', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Mark On-time', style: TextStyle(color: Colors.white)),
              onTap: () => _updateBus(bus, status: 'On-time'),
            ),
            ListTile(
              title: const Text('Mark Delayed', style: TextStyle(color: Colors.white)),
              onTap: () => _updateBus(bus, status: 'Delayed'),
            ),
            const Divider(color: Colors.white24),
            const Text('Assign New Route', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ..._routes.map((r) => ListTile(
              title: Text(r.name, style: const TextStyle(color: Colors.white)),
              onTap: () => _updateBus(bus, routeId: r.id, routeName: r.name, routeColor: r.color),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _updateBus(Bus bus, {String? status, String? routeId, String? routeName, String? routeColor}) async {
    Navigator.pop(context);
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

  Widget _buildStudentTab() {
    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white12)),
              child: const Icon(Icons.school_outlined, size: 64, color: Colors.white38),
            ),
            const SizedBox(height: 24),
            Text('No students active', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 40),
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
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
                leading: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Center(child: Text('👨‍🎓', style: TextStyle(fontSize: 24))),
                ),
                title: Text(student['name'] ?? 'Unknown', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.numbers, size: 14, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(student['roll'] ?? student['studentId'] ?? 'N/A', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(student['route'] ?? student['pickupPoint'] ?? 'Unassigned', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing: Container(
                  decoration: BoxDecoration(color: const Color(0xFF38ef7d).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.phone, color: Color(0xFF38ef7d), size: 20),
                    onPressed: () {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calling student...')));
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertTab() {
    final controller = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Send Public Alert', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter important notification message...',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38ef7d),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () async {
                if (controller.text.isEmpty) return;
                try {
                  await _apiService.post('manager/notifications', {'message': controller.text});
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alert Broadcasted!')));
                  controller.clear();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
              child: const Text('BROADCAST TO ALL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          )
        ],
      ),
    );
  }
}
