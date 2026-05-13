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
          _fleet = [];
        });
      }
    }
  }

  Future<void> _deleteBus(String id) async {
    try {
      await _apiService.delete('manager/buses/$id');
      _fetchFleetStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bus removed from fleet', style: GoogleFonts.plusJakartaSans())),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove bus', style: GoogleFonts.plusJakartaSans())),
        );
      }
    }
  }

  void _showAddBusDialog() async {
    final busNumberController = TextEditingController();
    List<dynamic> routes = [];
    String? selectedRouteId;
    String? selectedRouteName;
    String? selectedRouteColor;

    // Fetch routes first
    try {
      final res = await _apiService.get('routes');
      routes = res is List ? res : [];
    } catch (e) {
      // fail silently
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Add New Bus', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: busNumberController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Bus Number (e.g. MP04 PA 1234)',
                  labelStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Assigned Route',
                  labelStyle: const TextStyle(color: Colors.white38),
                ),
                items: routes.map<DropdownMenuItem<String>>((r) {
                  return DropdownMenuItem<String>(
                    value: r['_id'],
                    child: Text(r['name'] ?? 'Route'),
                  );
                }).toList(),
                onChanged: (val) {
                  final route = routes.firstWhere((r) => r['_id'] == val);
                  setDialogState(() {
                    selectedRouteId = val;
                    selectedRouteName = route['name'];
                    selectedRouteColor = route['color'];
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                if (busNumberController.text.isNotEmpty && selectedRouteId != null) {
                  try {
                    await _apiService.post('manager/buses', {
                      'busNumber': busNumberController.text,
                      'name': 'Bus - ${busNumberController.text}',
                      'routeId': selectedRouteId,
                      'routeName': selectedRouteName,
                      'routeColor': selectedRouteColor,
                      'status': 'On-time',
                      'occupancy': 'Low',
                      'currentLat': 23.2333,
                      'currentLng': 77.4333,
                    });
                    if (mounted) {
                      Navigator.pop(context);
                      _fetchFleetStatus();
                    }
                  } catch (e) {
                    // error
                  }
                }
              },
              child: Text('Add Bus', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Fleet Maintenance', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_bus_rounded, color: Colors.blueAccent),
            onPressed: _showAddBusDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _fleet.length,
            itemBuilder: (context, index) {
              final bus = _fleet[index];
              final Color statusColor = _getStatusColor(bus['status'] ?? 'nominal');
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: statusColor.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
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
                            bus['busNumber'] ?? bus['id'] ?? 'N/A',
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
                        Row(
                          children: [
                            Text(
                              (bus['status'] ?? 'UNKNOWN').toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white12, size: 18),
                              onPressed: () => _deleteBus(bus['_id']),
                            ),
                          ],
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
                            widthFactor: (bus['health'] ?? 0.9).toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 4)],
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
      case 'nominal': 
      case 'on-time': return Colors.blueAccent;
      case 'warning': 
      case 'delayed': return Colors.orangeAccent;
      case 'issue':
      case 'critical': return Colors.redAccent;
      default: return Colors.white24;
    }
  }
}
