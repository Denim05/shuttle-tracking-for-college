import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../constants/constants.dart';

class FleetMaintenanceScreen extends StatefulWidget {
  final bool nested;
  const FleetMaintenanceScreen({super.key, this.nested = false});

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

  void _sortFleetList(List<dynamic> list) {
    list.sort((a, b) {
      String getBusKey(dynamic bus) {
        if (bus is Map) {
          final String name = bus['name']?.toString() ?? '';
          final match = RegExp(r'Bus\s+([A-Za-z0-9\-]+)').firstMatch(name);
          if (match != null) return match.group(1)!;
          final busNum = bus['busNumber']?.toString() ?? '';
          if (busNum.isNotEmpty && busNum != 'N/A') return busNum;
        }
        return '';
      }

      final aKey = getBusKey(a);
      final bKey = getBusKey(b);

      final aIsNum = RegExp(r'^\d+$').hasMatch(aKey);
      final bIsNum = RegExp(r'^\d+$').hasMatch(bKey);

      if (aIsNum && bIsNum) {
        final aInt = int.tryParse(aKey) ?? 0;
        final bInt = int.tryParse(bKey) ?? 0;
        if (aInt != bInt) return aInt.compareTo(bInt);
      } else if (aIsNum) {
        return -1;
      } else if (bIsNum) {
        return 1;
      }

      final aIsT = RegExp(r'^T-\d+$', caseSensitive: false).hasMatch(aKey);
      final bIsT = RegExp(r'^T-\d+$', caseSensitive: false).hasMatch(bKey);
      if (aIsT && bIsT) {
        final aInt = int.tryParse(aKey.replaceAll(RegExp(r'\D'), '')) ?? 0;
        final bInt = int.tryParse(bKey.replaceAll(RegExp(r'\D'), '')) ?? 0;
        if (aInt != bInt) return aInt.compareTo(bInt);
      } else if (aIsT) {
        return -1;
      } else if (bIsT) {
        return 1;
      }

      return aKey.compareTo(bKey);
    });
  }

  Future<void> _fetchFleetStatus() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.get('buses');
      if (mounted) {
        final list = response is List ? List<dynamic>.from(response) : <dynamic>[];
        final Map<String, dynamic> uniqueBuses = {};
        for (final item in list) {
          if (item is Map) {
            final String key = (item['_id'] ?? item['busNumber'] ?? item['name'] ?? '').toString();
            if (key.isNotEmpty && !uniqueBuses.containsKey(key)) {
              uniqueBuses[key] = item;
            }
          }
        }
        final deduplicatedList = uniqueBuses.values.toList();
        _sortFleetList(deduplicatedList);
        setState(() {
          _fleet = deduplicatedList;
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

  void _confirmDeleteBus(String id, String busName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Bus?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove $busName from the fleet list?', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteBus(id);
            },
            child: Text('Remove', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBusDetailSheet(BuildContext context, Map<String, dynamic> bus) {
    final String busId = bus['_id']?.toString() ?? '';
    final String initialName = bus['name']?.toString() ?? '';
    final String initialNum = bus['busNumber']?.toString() ?? '';
    final String initialStatus = bus['status']?.toString() ?? 'On-time';
    final String routeName = bus['routeName']?.toString() ?? 'Assigned Route';

    final nameController = TextEditingController(text: initialName);
    final numController = TextEditingController(text: initialNum);
    String selectedStatus = initialStatus;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DefaultTabController(
          length: 2,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.directions_bus_rounded, color: Colors.blueAccent, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              initialName.isNotEmpty ? initialName : 'Bus Management',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            Text(
                              routeName,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TabBar(
                  indicatorColor: Colors.blueAccent,
                  labelColor: Colors.blueAccent,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(icon: Icon(Icons.edit_note_rounded), text: "Edit Details"),
                    Tab(icon: Icon(Icons.analytics_rounded), text: "Trip Reports"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // --- TAB 1: EDIT DETAILS ---
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Bus Information', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 16),
                            TextField(
                              controller: nameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Bus Display Name',
                                labelStyle: const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF242424),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: numController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'License Plate / Vehicle Number',
                                labelStyle: const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF242424),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: ['On-time', 'Delayed', 'Offline', 'Maintenance'].contains(selectedStatus) ? selectedStatus : 'On-time',
                              dropdownColor: const Color(0xFF242424),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Operational Status',
                                labelStyle: const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF242424),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                              ),
                              items: ['On-time', 'Delayed', 'Offline', 'Maintenance'].map((st) {
                                return DropdownMenuItem(value: st, child: Text(st));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setSheetState(() => selectedStatus = val);
                              },
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: () async {
                                  try {
                                    await _apiService.put('manager/buses/$busId', {
                                      'name': nameController.text.trim(),
                                      'busNumber': numController.text.trim(),
                                      'status': selectedStatus,
                                    });
                                    if (mounted && context.mounted) {
                                      Navigator.pop(ctx);
                                      _fetchFleetStatus();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Bus details updated successfully', style: GoogleFonts.plusJakartaSans())),
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('Failed to update bus details', style: GoogleFonts.plusJakartaSans())),
                                    );
                                  }
                                },
                                child: Text('Save Changes', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // --- TAB 2: TRIP REPORTS & LOGS ---
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Daily Trip Logs (Today)', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 14),
                            
                            // Morning Pickup Card
                            _buildTripCard(
                              title: 'Morning Pickup Trip',
                              timeRange: '06:00 AM – 09:30 AM',
                              direction: 'Stops → SISTec Campus',
                              status: 'Completed',
                              statusColor: Colors.greenAccent,
                              avgDuration: '45 mins',
                              passengers: '42 Students',
                            ),
                            const SizedBox(height: 14),

                            // Afternoon Return Card
                            _buildTripCard(
                              title: 'Afternoon Return Trip',
                              timeRange: '04:30 PM – 06:30 PM',
                              direction: 'SISTec Campus → Stops',
                              status: 'Scheduled',
                              statusColor: Colors.orangeAccent,
                              avgDuration: '50 mins',
                              passengers: '38 Students',
                            ),
                            const SizedBox(height: 24),

                            Text('Export Operational Reports', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.blueAccent),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    icon: const Icon(Icons.download_rounded, color: Colors.blueAccent, size: 20),
                                    label: Text('Download CSV', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                    onPressed: () async {
                                      final url = Uri.parse('${AppConstants.apiUrl}/manager/reports/bus-trip-report?busId=$busId&days=7');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    icon: const Icon(Icons.print_rounded, color: Colors.white, size: 20),
                                    label: Text('Print Report', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                    onPressed: () async {
                                      final url = Uri.parse('${AppConstants.apiUrl}/manager/reports/bus-trip-report/html?busId=$busId&days=7');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildTripCard({
    required String title,
    required String timeRange,
    required String direction,
    required String status,
    required Color statusColor,
    required String avgDuration,
    required String passengers,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(status, style: GoogleFonts.plusJakartaSans(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(direction, style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.access_time_rounded, color: Colors.blueAccent, size: 16),
              const SizedBox(width: 6),
              Text(timeRange, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11)),
              const Spacer(),
              Icon(Icons.people_outline_rounded, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 6),
              Text(passengers, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: busNumberController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Bus Number (e.g. MP04 PA 1234)',
                    labelStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Assigned Route',
                    labelStyle: TextStyle(color: Colors.white38),
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
                    if (mounted && context.mounted) {
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
      backgroundColor: widget.nested ? Colors.transparent : const Color(0xFF121212),
      appBar: widget.nested
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text('Fleet Maintenance', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_rounded, color: Colors.blueAccent),
                  onPressed: _showAddBusDialog,
                ),
                const SizedBox(width: 8),
              ],
            ),
      floatingActionButton: widget.nested
          ? FloatingActionButton.extended(
              onPressed: _showAddBusDialog,
              backgroundColor: Colors.blueAccent,
              elevation: 6,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Add Bus', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : ListView.builder(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 96),
            itemCount: _fleet.length,
            itemBuilder: (context, index) {
              final bus = _fleet[index];
              final String rawStatus = bus['status']?.toString() ?? 'Offline';
              final Color statusColor = _getStatusColor(rawStatus);
              
              final String busName = bus['name']?.toString() ?? '';
              final String busLabel = busName.contains(' - ') 
                  ? busName.split(' - ').first 
                  : (busName.isNotEmpty ? busName : 'Bus');
              final String busNum = bus['busNumber']?.toString() ?? 'N/A';
              final String cleanPlate = (busNum.isNotEmpty && busNum != 'N/A') 
                  ? busNum 
                  : 'N/A';

              return GestureDetector(
                onTap: () => _showBusDetailSheet(context, bus),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181C28),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Bus Icon Badge
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [statusColor.withValues(alpha: 0.22), statusColor.withValues(alpha: 0.06)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Icon(Icons.directions_bus_rounded, color: statusColor, size: 24),
                      ),
                      const SizedBox(width: 14),
                      
                      // Bus Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title & Plate Row
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Text(
                                  busLabel,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                if (cleanPlate != 'N/A' && cleanPlate.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                    ),
                                    child: Text(
                                      cleanPlate,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            
                            // Route Name
                            Row(
                              children: [
                                const Icon(Icons.route_rounded, size: 12, color: Colors.blueAccent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    bus['routeName'] ?? 'Unassigned Route',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: Colors.white54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Status & Action Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: statusColor.withValues(alpha: 0.6),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  rawStatus == 'Offline' ? 'IN DEPOT' : rawStatus.toUpperCase(),
                                  style: GoogleFonts.plusJakartaSans(
                                    color: statusColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 18),
                            onPressed: () => _confirmDeleteBus(bus['_id'], busLabel),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.06);
            },
          ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'nominal': 
      case 'on-time': 
      case 'active': return const Color(0xFF10B981);
      case 'warning': 
      case 'delayed': return Colors.amberAccent;
      case 'issue':
      case 'critical': return Colors.redAccent;
      case 'offline':
      case 'in depot': return const Color(0xFF94A3B8);
      default: return const Color(0xFF64748B);
    }
  }
}
