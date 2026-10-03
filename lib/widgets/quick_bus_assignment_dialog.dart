import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/timetable_resolver.dart';

/// Modal dialog allowing college management to immediately assign or swap
/// any bus number to any route in real-time under any operational situation
/// (e.g. Breakdown, Driver Swap, Morning rush, Delay relief).
class QuickBusAssignmentDialog extends StatefulWidget {
  final Map<String, dynamic>? initialRoute;
  final String? initialBusNumber;
  final VoidCallback? onAssigned;

  const QuickBusAssignmentDialog({
    super.key,
    this.initialRoute,
    this.initialBusNumber,
    this.onAssigned,
  });

  /// Static helper to display the sheet from anywhere in the app
  static Future<bool?> show(
    BuildContext context, {
    Map<String, dynamic>? initialRoute,
    String? initialBusNumber,
    VoidCallback? onAssigned,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => QuickBusAssignmentDialog(
        initialRoute: initialRoute,
        initialBusNumber: initialBusNumber,
        onAssigned: onAssigned,
      ),
    );
  }

  @override
  State<QuickBusAssignmentDialog> createState() => _QuickBusAssignmentDialogState();
}

class _QuickBusAssignmentDialogState extends State<QuickBusAssignmentDialog> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customBusController = TextEditingController();

  List<dynamic> _routes = [];
  List<dynamic> _dbBuses = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  Map<String, dynamic>? _selectedRoute;
  Map<String, dynamic>? _selectedBus;
  String _selectedReason = 'Emergency Breakdown';
  bool _notifyUsers = true;
  String _searchQuery = '';

  final List<String> _commonReasons = [
    'Emergency Breakdown',
    'Driver Shift Swap',
    'Delay Relief',
    'Morning Rush',
    'Evening Shift Adjustment',
    'Vehicle Maintenance',
    'Regular Assignment',
  ];

  @override
  void initState() {
    super.initState();
    _selectedRoute = widget.initialRoute;
    if (widget.initialBusNumber != null) {
      _customBusController.text = widget.initialBusNumber!;
    }
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customBusController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final responses = await Future.wait([
        _apiService.get('routes', useCache: false).catchError((_) => []),
        _apiService.get('buses', useCache: false).catchError((_) => []),
      ]);

      if (mounted) {
        setState(() {
          _routes = responses[0] is List ? List<dynamic>.from(responses[0] as List) : [];
          _dbBuses = responses[1] is List ? List<dynamic>.from(responses[1] as List) : [];
          _isLoading = false;

          // If initial route id was passed, ensure full object is selected
          if (_selectedRoute != null) {
            final targetId = _selectedRoute!['_id']?.toString();
            final match = _routes.firstWhere(
              (r) => r is Map && r['_id']?.toString() == targetId,
              orElse: () => _selectedRoute!,
            );
            if (match is Map) _selectedRoute = Map<String, dynamic>.from(match);
          } else if (_routes.isNotEmpty) {
            _selectedRoute = Map<String, dynamic>.from(_routes.first as Map);
          }

          // If initial bus number was provided, find match
          if (widget.initialBusNumber != null && widget.initialBusNumber!.isNotEmpty) {
            final cleanInit = widget.initialBusNumber!.toUpperCase().replaceAll(RegExp(r'\D'), '');
            for (final b in _combinedFleet) {
              final busNum = (b['busNumber'] ?? '').toString().toUpperCase().replaceAll(RegExp(r'\D'), '');
              if (busNum == cleanInit) {
                _selectedBus = b;
                break;
              }
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Merges live database buses with official 37 institutional roster
  /// so that EVERY bus (even if currently not broadcasting in DB) is immediately assignable!
  List<Map<String, dynamic>> get _combinedFleet {
    final Map<String, Map<String, dynamic>> map = {};

    // 1. Seed from official master fleet (Bus 01 to Bus 37)
    for (final entry in TimetableResolver.masterFleet) {
      final key = entry.busNumber.toUpperCase().trim();
      map[key] = {
        'busNumber': entry.busNumber,
        'officialPlate': entry.vehicleNo,
        'driverName': entry.driverName,
        'driverPhone': entry.driverPhone,
        'defaultRoute': entry.routeName,
        'currentRoute': 'Default: ${entry.routeName}',
        'status': 'Standby',
        'isOfficial': true,
      };
    }

    // 2. Overlay live MongoDB bus documents
    for (final b in _dbBuses) {
      if (b is! Map) continue;
      final rawNum = (b['busNumber'] ?? b['name'] ?? '').toString().trim();
      if (rawNum.isEmpty) continue;

      final cleanKey = rawNum.toUpperCase().replaceAll(RegExp(r'BUS\s*', caseSensitive: false), 'BUS ');
      final existing = map[cleanKey] ?? <String, dynamic>{};

      existing['_id'] = b['_id'];
      existing['busNumber'] = b['busNumber'] ?? existing['busNumber'] ?? rawNum;
      existing['status'] = b['status'] ?? existing['status'] ?? 'Offline';
      if (b['routeName'] != null && b['routeName'].toString().isNotEmpty) {
        existing['currentRoute'] = b['routeName'].toString();
      }
      existing['driverId'] = b['driverId'];
      map[cleanKey] = existing;
    }

    final list = map.values.toList();

    // Sort numerically (Bus 01, Bus 02 ... Bus 37, Bus T-4...)
    list.sort((a, b) {
      final aNum = (a['busNumber'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final bNum = (b['busNumber'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final aInt = int.tryParse(aNum) ?? 999;
      final bInt = int.tryParse(bNum) ?? 999;
      return aInt.compareTo(bInt);
    });

    return list;
  }

  List<Map<String, dynamic>> get _filteredFleet {
    final all = _combinedFleet;
    if (_searchQuery.trim().isEmpty) return all;
    final q = _searchQuery.toLowerCase().trim();

    return all.where((b) {
      final busNo = (b['busNumber'] ?? '').toString().toLowerCase();
      final plate = (b['officialPlate'] ?? '').toString().toLowerCase();
      final driver = (b['driverName'] ?? '').toString().toLowerCase();
      final route = (b['currentRoute'] ?? '').toString().toLowerCase();
      return busNo.contains(q) || plate.contains(q) || driver.contains(q) || route.contains(q);
    }).toList();
  }

  Future<void> _handleConfirmAssign() async {
    final busNum = _selectedBus != null
        ? (_selectedBus!['busNumber'] ?? '').toString().trim()
        : _customBusController.text.trim();

    if (busNum.isEmpty) {
      _showToast('Please select a bus or enter a bus number', isError: true);
      return;
    }

    if (_selectedRoute == null) {
      _showToast('Please select a target route', isError: true);
      return;
    }

    final routeId = (_selectedRoute!['_id'] ?? '').toString();
    final routeName = (_selectedRoute!['name'] ?? 'Route').toString();
    final routeColor = (_selectedRoute!['color'] ?? '#2563EB').toString();
    final busId = _selectedBus?['_id']?.toString();

    setState(() => _isSubmitting = true);

    bool success = false;
    String statusMessage = '';

    // 1. Try dedicated quick-assign endpoint
    try {
      final res = await _apiService.post('manager/buses/quick-assign', {
        'busNumber': busNum,
        'busId': busId,
        'routeId': routeId,
        'routeName': routeName,
        'routeColor': routeColor,
        'reason': _selectedReason,
        'notifyUsers': _notifyUsers,
      });
      success = true;
      statusMessage = res is Map ? (res['message'] ?? 'Assigned successfully') : 'Assigned successfully';
    } catch (e) {
      debugPrint('Primary quick-assign endpoint failed: $e. Falling back to resilient direct update...');
    }

    // 2. Fallback: try PATCH /manager/buses/:id or PUT /buses/:id/status if busId exists
    if (!success && busId != null && busId.isNotEmpty && busId.length >= 12) {
      try {
        await _apiService.patch('manager/buses/$busId', {
          'busNumber': busNum,
          'routeId': routeId,
          'routeName': routeName,
          'routeColor': routeColor,
          'name': '$busNum - $routeName',
        });
        success = true;
        statusMessage = 'Bus $busNum successfully reassigned to $routeName';
      } catch (err) {
        try {
          await _apiService.put('buses/$busId/status', {
            'status': 'On-time',
            'routeId': routeId,
            'routeName': routeName,
            'routeColor': routeColor,
          });
          success = true;
          statusMessage = 'Bus $busNum updated to $routeName';
        } catch (_) {}
      }
    }

    // 3. Fallback: create/register new bus assignment in DB
    if (!success) {
      try {
        await _apiService.post('manager/buses', {
          'busNumber': busNum,
          'name': '$busNum - $routeName',
          'routeId': routeId,
          'routeName': routeName,
          'routeColor': routeColor,
          'status': 'On-time',
        });
        success = true;
        statusMessage = 'Bus $busNum newly registered and assigned to $routeName';
      } catch (err) {
        debugPrint('Creation fallback failed: $err');
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      _showToast(statusMessage.isNotEmpty ? statusMessage : 'Bus $busNum assigned to $routeName live!');
      widget.onAssigned?.call();
      Navigator.pop(context, true);
    } else {
      _showToast('Failed to assign bus. Please check network.', isError: true);
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? AppColors.danger : AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF141923),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── Drag Handle ──
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 14),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Quick Bus Assignment',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'REAL-TIME',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFFBBF24),
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Instantly reassign any bus to a route in seconds',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),

          // ── Main Body ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Step 1: Target Route Selection ──
                        _buildSectionHeader('1', 'TARGET ROUTE', 'Where will this bus operate?'),
                        const SizedBox(height: 8),
                        _buildRouteSelector(),

                        const SizedBox(height: 20),

                        // ── Step 2: Bus Selection ──
                        _buildSectionHeader('2', 'SELECT BUS', 'Pick from official fleet or type bus number'),
                        const SizedBox(height: 8),
                        _buildBusSearchAndFleet(),

                        const SizedBox(height: 20),

                        // ── Step 3: Operational Situation / Reason ──
                        _buildSectionHeader('3', 'SITUATION / REASON', 'Help drivers & students understand why'),
                        const SizedBox(height: 8),
                        _buildReasonChips(),

                        const SizedBox(height: 14),

                        // ── Notify Switch ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: const Icon(Icons.notifications_active_rounded, color: AppColors.primaryLight, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Broadcast Alert to Students',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'Notifies riders tracking this route of the bus swap',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppColors.textMuted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _notifyUsers,
                                activeTrackColor: AppColors.primary,
                                onChanged: (v) => setState(() => _notifyUsers = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          // ── Bottom Action Footer ──
          _buildActionFooter(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String number, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFFBBF24),
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteSelector() {
    if (_routes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text('No routes available', style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
      );
    }

    final selectedColor = _selectedRoute != null ? _parseColor(_selectedRoute!['color']) : AppColors.primary;
    final routeName = _selectedRoute != null ? (_selectedRoute!['name'] ?? 'Select Route').toString() : 'Select Route';
    final stopsCount = (_selectedRoute?['stops'] as List?)?.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selectedColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: PopupMenuButton<Map<String, dynamic>>(
        color: const Color(0xFF1E2430),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        offset: const Offset(0, 56),
        initialValue: _selectedRoute,
        onSelected: (route) {
          setState(() => _selectedRoute = route);
        },
        itemBuilder: (context) {
          return _routes.map((r) {
            final map = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
            final c = _parseColor(map['color']);
            final name = (map['name'] ?? 'Transit Route').toString();
            final sCount = (map['stops'] as List?)?.length ?? 0;

            return PopupMenuItem<Map<String, dynamic>>(
              value: map,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$sCount stops',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            );
          }).toList();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: selectedColor.withValues(alpha: 0.5), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$stopsCount Stops  •  09:00 AM Institutional Shift',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusSearchAndFleet() {
    final filtered = _filteredFleet;
    final selectedBusNum = (_selectedBus?['busNumber'] ?? '').toString();

    return Column(
      children: [
        // Search & Manual Entry Row
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search bus no. (e.g. 04, 18) or plate...',
                    hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppColors.textMuted, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Quick Selected Summary Pill if any bus selected
        if (_selectedBus != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFFFBBF24), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white),
                      children: [
                        const TextSpan(text: 'Selected: '),
                        TextSpan(
                          text: selectedBusNum,
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFBBF24)),
                        ),
                        if (_selectedBus!['officialPlate'] != null)
                          TextSpan(
                            text: ' (${_selectedBus!['officialPlate']})',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        if (_selectedBus!['driverName'] != null)
                          TextSpan(
                            text: ' • Driver: ${_selectedBus!['driverName']}',
                            style: const TextStyle(color: Colors.white54),
                          ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedBus = null),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text('Change', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 11)),
                ),
              ],
            ),
          ),

        // Fleet List (Scrollable Horizontal Cards or Grid)
        Container(
          constraints: const BoxConstraints(maxHeight: 190),
          decoration: BoxDecoration(
            color: const Color(0xFF0F131C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No matching buses found.\nType any custom bus number above.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final busNum = (item['busNumber'] ?? '').toString();
                    final plate = (item['officialPlate'] ?? 'MP04 PA ----').toString();
                    final driver = (item['driverName'] ?? 'Assigned Driver').toString();
                    final currentRoute = (item['currentRoute'] ?? 'Standby').toString();
                    final isSelected = selectedBusNum == busNum;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFF59E0B)
                              : Colors.white.withValues(alpha: 0.06),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _selectedBus = item;
                            _customBusController.text = busNum;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              // Bus Number Pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFF59E0B)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  busNum,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: isSelected ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          plate,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '•  $driver',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppColors.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Current: $currentRoute',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isSelected ? const Color(0xFFFBBF24) : Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Radio / Check Indicator
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? const Color(0xFFFBBF24) : Colors.white24,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReasonChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _commonReasons.map((reason) {
        final isSelected = _selectedReason == reason;
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _selectedReason = reason),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(Icons.check_rounded, color: AppColors.primaryLight, size: 13),
                  const SizedBox(width: 4),
                ],
                Text(
                  reason,
                  style: GoogleFonts.plusJakartaSans(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionFooter() {
    final busNum = _selectedBus != null
        ? (_selectedBus!['busNumber'] ?? '').toString()
        : _customBusController.text.trim();
    final canAssign = busNum.isNotEmpty && _selectedRoute != null && !_isSubmitting;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF10141D),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white60,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: canAssign ? _handleConfirmAssign : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  disabledBackgroundColor: Colors.white12,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 18, color: Colors.black),
                          const SizedBox(width: 6),
                          Text(
                            busNum.isNotEmpty
                                ? 'Assign $busNum Now'
                                : 'Assign Bus Now',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null) return AppColors.primary;
    try {
      final clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) return Color(int.parse('0xFF$clean'));
      if (clean.length == 8) return Color(int.parse('0x$clean'));
    } catch (_) {}
    return AppColors.primary;
  }
}
