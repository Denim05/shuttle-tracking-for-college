import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

class FleetMaintenanceScreen extends StatefulWidget {
  const FleetMaintenanceScreen({super.key});

  @override
  State<FleetMaintenanceScreen> createState() => _FleetMaintenanceScreenState();
}

class _FleetMaintenanceScreenState extends State<FleetMaintenanceScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _fleet = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFleetStatus();
  }

  Future<void> _fetchFleetStatus() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.get('buses');
      if (mounted) {
        setState(() {
          _fleet = response is List ? response : [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _fleet = [
            {'id': 'B-101', 'routeName': 'Main Loop', 'status': 'Normal', 'health': 0.98},
            {'id': 'B-102', 'routeName': 'Express A', 'status': 'Warning', 'health': 0.72},
            {'id': 'B-103', 'routeName': 'Express B', 'status': 'Issue', 'health': 0.15},
            {'id': 'B-104', 'routeName': 'South Loop', 'status': 'Offline', 'health': 0.0},
          ];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Fleet Maintenance', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _fleet.length,
            itemBuilder: (context, index) {
              final bus = _fleet[index];
              final Color statusColor = _getStatusColor(bus['status']);
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: statusColor.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.directions_bus_filled_rounded, color: statusColor, size: 28),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bus['id'] ?? 'N/A',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                          ),
                          Text(
                            bus['routeName'] ?? 'Unknown Route',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          bus['status'].toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 80,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (bus['health'] ?? 0.0).toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.5), blurRadius: 4)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
            },
          ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'nominal': return Colors.blueAccent;
      case 'warning': return Colors.orangeAccent;
      case 'critical': return Colors.redAccent;
      default: return Colors.white24;
    }
  }
}

