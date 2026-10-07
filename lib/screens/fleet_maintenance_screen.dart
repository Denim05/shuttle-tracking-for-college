import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/report_download_service.dart';
import '../utils/timetable_resolver.dart';
import '../widgets/quick_bus_assignment_dialog.dart';

enum FleetFilter { all, active, delayed, uncovered }

class FleetReadinessReport {
  final int totalRoutes;
  final List<dynamic> activeBuses;
  final List<dynamic> delayedBuses;
  final List<TimetableRouteEntry> uncoveredRoutes;

  const FleetReadinessReport({
    required this.totalRoutes,
    required this.activeBuses,
    required this.delayedBuses,
    required this.uncoveredRoutes,
  });
}

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
  FleetFilter _selectedFilter = FleetFilter.all;

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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            Text(
                              routeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                              initialValue: ['On-time', 'Delayed', 'Offline', 'Maintenance'].contains(selectedStatus) ? selectedStatus : 'On-time',
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
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to update bus details', style: GoogleFonts.plusJakartaSans())),
                                      );
                                    }
                                  }
                                },
                                child: Text('Save Changes', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFBBF24),
                                side: const BorderSide(color: Color(0xFFF59E0B)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                              label: Text('⚡ Reassign to Different Route', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13.5)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                QuickBusAssignmentDialog.show(
                                  context,
                                  initialBusNumber: numController.text.trim().isNotEmpty ? numController.text.trim() : initialName,
                                  onAssigned: _fetchFleetStatus,
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // --- TAB 2: LIVE BUS TRIP & DAY REPORTS ---
                      _BusTripReportTab(
                        busId: busId,
                        busName: initialName,
                        busNumber: initialNum,
                        apiService: _apiService,
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
        : _buildFleetBody(),
    );
  }

  Widget _buildFleetBody() {
    final report = _computeReadinessReport();

    final List<dynamic> displayList;
    if (_selectedFilter == FleetFilter.active) {
      displayList = report.activeBuses;
    } else if (_selectedFilter == FleetFilter.delayed) {
      displayList = report.delayedBuses;
    } else if (_selectedFilter == FleetFilter.uncovered) {
      displayList = report.uncoveredRoutes;
    } else {
      displayList = _fleet;
    }

    final bool isEmptyList = displayList.isEmpty;
    final int totalCount = 1 + (isEmptyList ? 1 : displayList.length);

    return ListView.builder(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 96),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildDispatchReadinessBoard(report);
        }

        if (isEmptyList) {
          return _buildEmptyFilterState();
        }

        final itemIndex = index - 1;
        final item = displayList[itemIndex];

        if (_selectedFilter == FleetFilter.uncovered && item is TimetableRouteEntry) {
          return _buildUncoveredRouteCard(item, itemIndex);
        }

        if (item is Map) {
          return _buildFleetBusCard(Map<String, dynamic>.from(item), itemIndex);
        }

        return const SizedBox.shrink();
      },
    );
  }

  bool _isBusBroadcasting(Map<String, dynamic> bus) {
    final status = (bus['status']?.toString() ?? '').toLowerCase().trim();
    if (status == 'offline' || status == 'in depot' || status == 'standby' || status.isEmpty) {
      return false;
    }

    final lastUpdatedVal = bus['lastUpdated'];
    if (lastUpdatedVal == null) return false;

    DateTime? lastUp;
    if (lastUpdatedVal is DateTime) {
      lastUp = lastUpdatedVal;
    } else {
      lastUp = DateTime.tryParse(lastUpdatedVal.toString());
    }

    if (lastUp == null) return false;

    // A bus is ONLY actively broadcasting live if telemetry arrived within last 45 seconds AND has positive speed or active trip marker
    final diff = DateTime.now().difference(lastUp).inSeconds;
    final speed = (bus['speed'] is num)
        ? (bus['speed'] as num).toDouble()
        : (double.tryParse(bus['speed']?.toString() ?? '0') ?? 0.0);

    return diff >= 0 && diff <= 45 && (speed > 0 || status == 'active');
  }

  Future<void> _restoreDefaults() async {
    setState(() => _isLoading = true);
    try {
      bool backendRestored = false;
      try {
        await _apiService.post('manager/buses/restore-defaults', {});
        backendRestored = true;
      } catch (endpointErr) {
        debugPrint('Direct restore endpoint not available on server, applying per-bus fallback: $endpointErr');
      }

      if (!backendRestored) {
        // Resilient fallback: reset all buses via PUT /buses/:id/status
        final futures = <Future>[];
        for (final bus in _fleet) {
          if (bus is! Map) continue;
          final id = (bus['_id'] ?? '').toString();
          if (id.isNotEmpty && id.length >= 12) {
            futures.add(_apiService.put('buses/$id/status', {
              'status': 'Offline',
            }).catchError((_) => null));
          }
        }
        if (futures.isNotEmpty) {
          await Future.wait(futures);
        }
      }

      await _fetchFleetStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All buses restored to default In-Depot standby status.',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore fleet defaults: $e', style: GoogleFonts.plusJakartaSans()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _confirmRestoreDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2335),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.restart_alt_rounded, color: Color(0xFFFBBF24), size: 24),
            const SizedBox(width: 10),
            Text(
              'Restore Default Fleet?',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'This will reset all buses to their default institutional In-Depot standby status and restore original timetable route assignments.',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: Text('Restore Defaults', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
            onPressed: () {
              Navigator.pop(ctx);
              _restoreDefaults();
            },
          ),
        ],
      ),
    );
  }

  FleetReadinessReport _computeReadinessReport() {
    final active = <dynamic>[];
    final delayed = <dynamic>[];

    for (final bus in _fleet) {
      if (bus is! Map) continue;
      final busMap = Map<String, dynamic>.from(bus);
      final isBroadcasting = _isBusBroadcasting(busMap);

      // Only count buses as active/delayed if they are actively streaming telemetry right now
      if (!isBroadcasting) continue;

      final status = (bus['status']?.toString() ?? '').toLowerCase();
      final isDelayed = status == 'delayed' || status == 'warning';

      if (isDelayed) {
        delayed.add(bus);
      } else {
        active.add(bus);
      }
    }

    final uncovered = <TimetableRouteEntry>[];
    for (final entry in TimetableResolver.masterFleet) {
      final eRoute = entry.routeName.toLowerCase();
      final eBus = entry.busNumber.toLowerCase();
      final eCleanBus = 'bus ${entry.busNumber}'.toLowerCase();
      final ePlate = entry.vehicleNo.toLowerCase();

      bool isCovered = false;
      for (final bus in _fleet) {
        if (bus is! Map) continue;
        final busMap = Map<String, dynamic>.from(bus);
        if (!_isBusBroadcasting(busMap)) continue; // Must be actively broadcasting to cover route!

        final bRoute = (bus['routeName']?.toString() ?? '').toLowerCase();
        final bNum = (bus['busNumber']?.toString() ?? '').toLowerCase();
        final bName = (bus['name']?.toString() ?? '').toLowerCase();

        if (bRoute.contains(eRoute) || eRoute.contains(bRoute) ||
            bNum == eBus || bNum == eCleanBus || bNum == ePlate ||
            bName.contains(eCleanBus)) {
          isCovered = true;
          break;
        }
      }

      if (!isCovered) {
        uncovered.add(entry);
      }
    }

    return FleetReadinessReport(
      totalRoutes: TimetableResolver.masterFleet.length,
      activeBuses: active,
      delayedBuses: delayed,
      uncoveredRoutes: uncovered,
    );
  }

  Widget _buildDispatchReadinessBoard(FleetReadinessReport report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B2335),
            Color(0xFF131722),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.speed_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MORNING 8:00 AM FLEET DISPATCH',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF60A5FA),
                              fontSize: 9.0,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Fleet Readiness Matrix',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Restore Official Defaults',
                    child: InkWell(
                      onTap: _confirmRestoreDefaults,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.restart_alt_rounded, size: 12, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 3),
                            Text(
                              'Restore',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFFBBF24),
                                fontSize: 9.0,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3.5),
                        Text(
                          '${report.totalRoutes}R',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF10B981),
                            fontSize: 9.0,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Three Metric Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  count: report.activeBuses.length,
                  label: 'Active',
                  statusSub: 'Broadcasting live',
                  color: const Color(0xFF10B981),
                  isSelected: _selectedFilter == FleetFilter.active,
                  onTap: () => setState(() {
                    _selectedFilter = _selectedFilter == FleetFilter.active ? FleetFilter.all : FleetFilter.active;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  count: report.delayedBuses.length,
                  label: 'Delayed',
                  statusSub: 'Behind schedule',
                  color: const Color(0xFFFBBF24),
                  isSelected: _selectedFilter == FleetFilter.delayed,
                  onTap: () => setState(() {
                    _selectedFilter = _selectedFilter == FleetFilter.delayed ? FleetFilter.all : FleetFilter.delayed;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  count: report.uncoveredRoutes.length,
                  label: 'Uncovered',
                  statusSub: 'Needs bus now',
                  color: const Color(0xFFEF4444),
                  isSelected: _selectedFilter == FleetFilter.uncovered,
                  onTap: () => setState(() {
                    _selectedFilter = _selectedFilter == FleetFilter.uncovered ? FleetFilter.all : FleetFilter.uncovered;
                  }),
                ),
              ),
            ],
          ),

          // High-Priority Alert Banner if Uncovered Routes exist
          if (report.uncoveredRoutes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2C1315),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${report.uncoveredRoutes.length} Routes Uncovered',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Next: Bus ${report.uncoveredRoutes.first.busNumber} • ${report.uncoveredRoutes.first.routeName}',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.flash_on_rounded, size: 14, color: Colors.black),
                    label: const Text('Assign Bus', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFBBF24),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => QuickBusAssignmentDialog.show(
                      context,
                      initialRoute: {'name': report.uncoveredRoutes.first.routeName, 'routeName': report.uncoveredRoutes.first.routeName},
                      initialBusNumber: 'Bus ${report.uncoveredRoutes.first.busNumber}',
                      onAssigned: _fetchFleetStatus,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Filter Pills Bar
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill(
                  label: 'All Fleet (${_fleet.length})',
                  isSelected: _selectedFilter == FleetFilter.all,
                  onTap: () => setState(() => _selectedFilter = FleetFilter.all),
                ),
                const SizedBox(width: 6),
                _buildFilterPill(
                  label: '🟢 Active (${report.activeBuses.length})',
                  isSelected: _selectedFilter == FleetFilter.active,
                  onTap: () => setState(() => _selectedFilter = FleetFilter.active),
                ),
                const SizedBox(width: 6),
                _buildFilterPill(
                  label: '🟡 Delayed (${report.delayedBuses.length})',
                  isSelected: _selectedFilter == FleetFilter.delayed,
                  onTap: () => setState(() => _selectedFilter = FleetFilter.delayed),
                ),
                const SizedBox(width: 6),
                _buildFilterPill(
                  label: '🔴 Uncovered (${report.uncoveredRoutes.length})',
                  isSelected: _selectedFilter == FleetFilter.uncovered,
                  onTap: () => setState(() => _selectedFilter = FleetFilter.uncovered),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required int count,
    required String label,
    required String statusSub,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? color : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.0,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              statusSub,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? color.withValues(alpha: 0.9) : Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildUncoveredRouteCard(TimetableRouteEntry entry, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1416),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'UNCOVERED ROUTE',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.redAccent,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${entry.morningDeparture} Departure',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Bus ${entry.busNumber} • ${entry.routeName}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nominal Vehicle: ${entry.vehicleNo}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Driver: ${entry.driverName} (${entry.driverPhone})',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                icon: const Icon(Icons.phone_rounded, color: Colors.greenAccent, size: 18),
                onPressed: () async {
                  final uri = Uri.parse('tel:${entry.driverPhone.trim()}');
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.flash_on_rounded, color: Colors.black, size: 16),
              label: Text(
                '⚡ 1-Tap Assign Bus Now',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBF24),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => QuickBusAssignmentDialog.show(
                context,
                initialRoute: {'name': entry.routeName, 'routeName': entry.routeName},
                initialBusNumber: 'Bus ${entry.busNumber}',
                onAssigned: _fetchFleetStatus,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (index * 30).ms).slideY(begin: 0.05);
  }

  Widget _buildFleetBusCard(Map<String, dynamic> bus, int index) {
    final bool isBroadcasting = _isBusBroadcasting(bus);
    final String rawStatus = bus['status']?.toString() ?? 'Offline';
    final String displayStatus = isBroadcasting
        ? (rawStatus.toLowerCase() == 'delayed' ? 'DELAYED' : 'ON-TIME')
        : 'IN DEPOT';
    final Color statusColor = isBroadcasting
        ? _getStatusColor(rawStatus)
        : const Color(0xFF64748B);
    
    final String routeName = bus['routeName']?.toString() ?? '';
    final String assignedBusLabel = TimetableResolver.resolveAssignedBusNumber(
      explicitBusNumber: bus['busNumber'],
      busName: bus['name'],
      routeName: routeName,
    );
    final busDetails = TimetableResolver.resolveBusDetails(
      routeName: routeName,
      busNo: bus['busNumber']?.toString() ?? bus['name']?.toString(),
    );
    final String cleanPlate = busDetails?.vehicleNo ?? (bus['busNumber']?.toString() ?? 'N/A');

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
                        assignedBusLabel,
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
                          routeName.isNotEmpty ? routeName : 'Unassigned Route',
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
                  if (busDetails != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 11, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${busDetails.driverName} • ${busDetails.morningDeparture} Shift',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                        displayStatus,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      tooltip: 'Quick Reassign Route',
                      icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFFFBBF24), size: 19),
                      onPressed: () => QuickBusAssignmentDialog.show(
                        context,
                        initialBusNumber: assignedBusLabel,
                        onAssigned: _fetchFleetStatus,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white24, size: 18),
                      onPressed: () => _confirmDeleteBus(bus['_id'], assignedBusLabel),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (index * 40).ms).slideY(begin: 0.06);
  }

  Widget _buildEmptyFilterState() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF181C28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 40),
            const SizedBox(height: 12),
            Text(
              'No items in this category',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All corresponding routes are in order.',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
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

class _BusTripReportTab extends StatefulWidget {
  final String busId;
  final String busName;
  final String busNumber;
  final ApiService apiService;

  const _BusTripReportTab({
    required this.busId,
    required this.busName,
    required this.busNumber,
    required this.apiService,
  });

  @override
  State<_BusTripReportTab> createState() => _BusTripReportTabState();
}

class _BusTripReportTabState extends State<_BusTripReportTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _report;
  String _selectedShift = 'morning'; // 'morning', 'evening', 'all'

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.apiService.get('manager/reports/bus-trip-report?busId=${widget.busId}&days=1&format=json');
      if (mounted) {
        setState(() {
          _report = res is Map<String, dynamic> ? res : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openReport({String format = 'excel', bool? isHtml}) async {
    final resolvedFormat = isHtml != null ? (isHtml ? 'html' : 'csv') : format;
    await ReportDownloadService().downloadAndOpenReport(
      context,
      format: resolvedFormat,
      busId: widget.busId,
      shift: _selectedShift,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    if (_error != null || _report == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 36),
              const SizedBox(height: 10),
              Text(
                'Could not load telemetry report',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? 'No records available',
                style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _fetchReport,
              ),
            ],
          ),
        ),
      );
    }

    final morningTrips = (_report!['morningTrips'] as List?) ?? [];
    final eveningTrips = (_report!['eveningTrips'] as List?) ?? [];
    final allTrips = (_report!['allTrips'] as List?) ?? [];

    List<dynamic> displayedTrips = [];
    if (_selectedShift == 'morning') {
      displayedTrips = morningTrips;
    } else if (_selectedShift == 'evening') {
      displayedTrips = eveningTrips;
    } else {
      displayedTrips = allTrips;
    }

    final dateStr = _report!['date'] ?? 'Today';
    final dayStr = _report!['day'] ?? '';
    final punctualityRate = _report!['punctualityRate'] ?? '100.0';
    final totalDistance = _report!['totalDistance'] ?? '0.0';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Day Summary Dossier ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E2640), Color(0xFF151A2C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            widget.busName,
                            style: GoogleFonts.jetBrainsMono(
                              color: const Color(0xFF818CF8),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.busNumber,
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'Day Report',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '$dayStr, $dateStr',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildKpiMini('Punctuality', '$punctualityRate%', Colors.greenAccent),
                    const SizedBox(width: 10),
                    _buildKpiMini('Commute', '$totalDistance km', const Color(0xFF818CF8)),
                    const SizedBox(width: 10),
                    _buildKpiMini('Trips', '${morningTrips.length + eveningTrips.length}', Colors.amberAccent),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Segmented Trip Filter Switcher ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF161B26),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildShiftTab('🌅 Morning (${morningTrips.length})', 'morning'),
                ),
                Expanded(
                  child: _buildShiftTab('🌆 Afternoon (${eveningTrips.length})', 'evening'),
                ),
                Expanded(
                  child: _buildShiftTab('All (${allTrips.length})', 'all'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Trip Cards & Stop-by-Stop Progress ──
          if (displayedTrips.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No trips found for this selection.',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
                ),
              ),
            )
          else
            ...displayedTrips.map((t) => _buildTripDetailTile(t)),

          const SizedBox(height: 20),

          // ── Export Actions ──
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.table_view_rounded, color: Colors.white, size: 16),
                  label: Text('Excel (.xlsx)', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: () => _openReport(format: 'excel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.download_rounded, color: Colors.cyanAccent, size: 16),
                  label: Text('CSV', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: () => _openReport(format: 'csv'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 16),
                  label: Text('Print PDF', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: () => _openReport(format: 'pdf'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMini(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.plusJakartaSans(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftTab(String label, String key) {
    final isSelected = _selectedShift == key;
    return InkWell(
      onTap: () => setState(() => _selectedShift = key),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildTripDetailTile(dynamic t) {
    final shift = t['shift'] ?? 'Commute Trip';
    final origin = t['originStop'] ?? 'Origin';
    final destination = t['destinationStop'] ?? 'Destination';
    final departure = t['departureTime'] ?? 'N/A';
    final arrival = t['arrivalTime'] ?? 'N/A';
    final schedDepart = t['scheduledDeparture'] ?? '';
    final schedArrive = t['scheduledArrival'] ?? '';
    final duration = t['duration'] ?? 'N/A';
    final distance = t['distanceKm'] ?? '0';
    final punctuality = t['punctuality'] ?? 'On-Time';
    final status = t['status'] ?? 'Scheduled';
    final stops = (t['stops'] as List?) ?? [];
    final isOnTime = punctuality.toString().contains('On-Time');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2433),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$origin ➔ $destination',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isOnTime ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isOnTime ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.amberAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    punctuality,
                    style: GoogleFonts.plusJakartaSans(
                      color: isOnTime ? Colors.greenAccent : Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Timings Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.black.withValues(alpha: 0.2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DEPARTURE', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(departure, style: GoogleFonts.jetBrainsMono(color: const Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.bold)),
                      if (schedDepart.isNotEmpty)
                        Text('Sched: $schedDepart', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ARRIVAL', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(arrival, style: GoogleFonts.jetBrainsMono(color: const Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.bold)),
                      if (schedArrive.isNotEmpty)
                        Text('Sched: $schedArrive', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DURATION / DIST', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('$duration • ${distance}km', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(status, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Stop Stepper Expansion
          if (stops.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(
                'Stop Timetable (${stops.length} Stops)',
                style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stops.length,
              itemBuilder: (ctx, sIdx) {
                final st = stops[sIdx];
                final stName = st['name'] ?? 'Stop ${sIdx + 1}';
                final stSched = st['scheduledTime'] ?? 'N/A';
                final stAct = st['actualTime'] ?? 'Pending';
                final isReached = st['status']?.toString().contains('Reached') == true;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isReached ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: isReached ? Colors.greenAccent : Colors.white24,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${sIdx + 1}. $stName',
                          style: GoogleFonts.plusJakartaSans(color: isReached ? Colors.white : Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'Sched: $stSched  •  ',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10),
                      ),
                      Text(
                        stAct,
                        style: GoogleFonts.jetBrainsMono(
                          color: isReached ? Colors.greenAccent : Colors.white54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

