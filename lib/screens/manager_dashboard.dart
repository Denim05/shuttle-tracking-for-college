import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/bus_model.dart';
import '../models/route_model.dart';
import '../services/socket_service.dart';
import '../services/bus_store.dart';
import '../components/bus_map.dart';
import 'registration_manager_screen.dart';
import 'complaint_manager_screen.dart';
import 'route_management_screen.dart';
import 'fleet_maintenance_screen.dart';
import 'profile_settings_screen.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import '../constants/constants.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  // _buses removed — fleet data now comes from BusStore (Consumer<BusStore>)
  List<RouteModel> _routes = [];
  List<dynamic> _users = [];
  List<dynamic> _drivers = [];
  List<dynamic> _rawBuses = [];
  late SocketService _socketService;
  late BusStore _busStore;
  final TextEditingController _notifController = TextEditingController();
  final TextEditingController _bulkSemesterController = TextEditingController();
  String _selectedUserSemesterFilter = 'All';
  bool _isSending = false;
  String _selectedTargetAudience = 'All';
  List<Map<String, String>> _bulkParsedSubmissions = [];
  bool _isBulkSaving = false;

  @override
  void initState() {
    super.initState();
    _socketService = Provider.of<SocketService>(context, listen: false);
    _busStore = Provider.of<BusStore>(context, listen: false);
    _loadData();
    _initSocket();
    _loadNotificationHistory();
  }

  void _initSocket() {
    // ⚠️ Do NOT call listenToBusUpdates here — that would overwrite BusStore's
    // listener and break real-time updates across all dashboards.
    // The fleet tab reads from BusStore via Consumer<BusStore> instead.

    _socketService.listenToSystemAlerts((data) {
      if (mounted && data != null && data['message'] != null) {
        _showSystemAlertSnackBar(data['message']);
      }
    });

    _socketService.listenToSOSAlerts((data) {
      if (mounted && data != null) {
        _showEmergencySOSOverlay(data);
      }
    });
  }

  Future<void> _loadNotificationHistory() async {
    try {
      final data = await _apiService.get('notifications');
      _busStore.seedNotifications(data as List);
    } catch (e) {
      debugPrint('Notification history load failed: $e');
    }
  }

  Future<void> _downloadReport({String? busId}) async {
    DateTime selectedDate = DateTime.now();
    String selectedShift = 'all'; // 'all', 'morning', 'evening'
    bool isSyncing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final dateStr = selectedDate.toIso8601String().split('T')[0];
          final formattedDisplayDate = '${selectedDate.day.toString().padLeft(2, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.year}';
          final isToday = selectedDate.year == DateTime.now().year &&
              selectedDate.month == DateTime.now().month &&
              selectedDate.day == DateTime.now().day;

          return AlertDialog(
            backgroundColor: const Color(0xFF161B26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Day-Wise Bus Report',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        '2-Trip Schedule (Morning & Evening)',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  
                  // 1. DATE SELECTION
                  Text(
                    'OPERATIONAL DATE',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: Color(0xFF818CF8), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isToday ? 'Today ($formattedDisplayDate)' : formattedDisplayDate,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2025, 1, 1),
                              lastDate: DateTime.now().add(const Duration(days: 7)),
                              builder: (context, child) {
                                return Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Color(0xFF4F46E5),
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E293B),
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setModalState(() => selectedDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'Change',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFF818CF8),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. SHIFT SELECTION
                  Text(
                    'SCHEDULE SHIFT',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildShiftFilterChip(
                        label: 'All 54',
                        value: 'all',
                        selectedValue: selectedShift,
                        onSelected: (val) => setModalState(() => selectedShift = val),
                      ),
                      _buildShiftFilterChip(
                        label: '🌅 Morning',
                        value: 'morning',
                        selectedValue: selectedShift,
                        onSelected: (val) => setModalState(() => selectedShift = val),
                      ),
                      _buildShiftFilterChip(
                        label: '🌆 Evening',
                        value: 'evening',
                        selectedValue: selectedShift,
                        onSelected: (val) => setModalState(() => selectedShift = val),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. ACTION OPTIONS
                  Text(
                    'EXPORT OR SYNC FORMAT',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Option A: Live Google Sheets Sync
                  InkWell(
                    onTap: isSyncing ? null : () async {
                      setModalState(() => isSyncing = true);
                      try {
                        final res = await _apiService.post('manager/reports/sync-google-sheets', {
                          'date': dateStr,
                        });
                        setModalState(() => isSyncing = false);
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Synced ${res['syncedMorning'] ?? 27} Morning + ${res['syncedEvening'] ?? 27} Evening Trips & ${res['syncedStops'] ?? 658} Stop Logs to Google Sheets!'),
                              backgroundColor: const Color(0xFF059669),
                              behavior: SnackBarBehavior.floating,
                              action: SnackBarAction(
                                label: 'OPEN SHEET',
                                textColor: Colors.white,
                                onPressed: () {
                                  final sheetUrl = res['spreadsheetUrl'] ?? 'https://docs.google.com/spreadsheets/d/16V1Og-UYtzN8gM1x3Bj4wZLjdw5-fyvWFMWucwby8EE/edit';
                                  launchUrl(Uri.parse(sheetUrl), mode: LaunchMode.externalApplication);
                                },
                              ),
                            ),
                          );
                          final sheetUrl = res['spreadsheetUrl'] ?? 'https://docs.google.com/spreadsheets/d/16V1Og-UYtzN8gM1x3Bj4wZLjdw5-fyvWFMWucwby8EE/edit';
                          launchUrl(Uri.parse(sheetUrl), mode: LaunchMode.externalApplication);
                        }
                      } catch (e) {
                        setModalState(() => isSyncing = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Google Sheets Sync Failed: $e'),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF059669).withValues(alpha: 0.18),
                            const Color(0xFF10B981).withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: isSyncing 
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                )
                              : const Icon(Icons.table_chart_rounded, color: Color(0xFF10B981), size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sync to Google Sheets',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Appends real-time Morning & Evening runs for all 27 buses',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF10B981), size: 14),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Option B: Executive HTML & PDF Print
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchReportUrl(busId, isHtml: true, date: dateStr, shift: selectedShift);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.print_rounded, color: Color(0xFF818CF8), size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Executive Print / PDF',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Printable layout with SISTec branding & KPI cards',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.open_in_new_rounded, color: Colors.white24, size: 14),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Option C: CSV Spreadsheet Download
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchReportUrl(busId, isHtml: false, date: dateStr, shift: selectedShift);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.file_download_rounded, color: Colors.amberAccent, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Download CSV (Excel)',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Raw data format for Microsoft Excel / LibreOffice',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_downward_rounded, color: Colors.white24, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildShiftFilterChip({
    required String label,
    required String value,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    final isSelected = selectedValue == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelected(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF818CF8) : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchReportUrl(String? busId, {required bool isHtml, String? date, String? shift}) async {
    final reportPath = isHtml ? 'bus-trip-report/html' : 'bus-trip-report';
    final targetDate = date ?? DateTime.now().toIso8601String().split('T')[0];
    final targetShift = shift ?? 'all';
    
    final uri = busId != null 
        ? '${AppConstants.apiUrl}/manager/reports/$reportPath?busId=$busId&date=$targetDate&shift=$targetShift'
        : '${AppConstants.apiUrl}/manager/reports/$reportPath?date=$targetDate&shift=$targetShift';
        
    final url = Uri.parse(uri);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isHtml ? 'Opening Day-Wise Executive Report...' : 'Downloading CSV Fleet Report...'),
          backgroundColor: const Color(0xFF4F46E5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
    try {
      final success = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!success) {
        await launchUrl(url);
      }
    } catch (e) {
      debugPrint('Error launching report URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open report: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }


  @override
  void dispose() {
    _notifController.dispose();
    _bulkSemesterController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Fetch all data sources concurrently in parallel
      final results = await Future.wait([
        _apiService.get('buses'),
        _apiService.get('routes', useCache: true),
        _apiService.get('manager/users').catchError((e) {
          debugPrint('Optional users failed to load: $e');
          return <dynamic>[];
        }),
        _apiService.get('manager/drivers').catchError((e) {
          debugPrint('Optional drivers failed to load: $e');
          return <dynamic>[];
        }),
      ]);

      if (!mounted) return;

      final busData = results[0] is List ? results[0] : <dynamic>[];
      final routeData = results[1] is List ? results[1] : <dynamic>[];
      final userData = results[2] is List ? results[2] : <dynamic>[];
      final driverData = results[3] is List ? results[3] : <dynamic>[];

      setState(() {
        _routes = (routeData as List).map((r) => RouteModel.fromJson(r)).toList();
        _users = userData as List;
        _drivers = driverData as List;
        _rawBuses = busData as List;
        _isLoading = false;
      });
      // Seed BusStore with initial bus data (real-time updates come via socket)
      final busStore = Provider.of<BusStore>(context, listen: false);
      busStore.seedBuses(busData as List);
    } catch (e) {
      debugPrint('Error loading manager data: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      // If routes are empty, show a hint
      if (e.toString().contains('404') || e.toString().contains('empty')) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database is empty. Please add routes first.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (e.toString().contains('401')) {
        // Auto-logout on session expiration
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Session expired. Getting fresh token...'), backgroundColor: Colors.orange)
           );
           Provider.of<AuthService>(context, listen: false).logout();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _seedDatabase() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.post('manager/seed', {});
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database seeded successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('401')) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Session expired. Logging out...'), backgroundColor: Colors.orange)
           );
           Provider.of<AuthService>(context, listen: false).logout();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Seed failed: ${e.toString().replaceAll('Exception:', '').trim()}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final socketService = Provider.of<SocketService>(context);
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: ValueListenableBuilder<bool>(
          valueListenable: socketService.connectionStatus,
          builder: (context, isConnected, child) {
            return Stack(
              children: [
                // Background Gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.5,
                      colors: [Color(0xFF0F172A), Color(0xFF121212)],
                    ),
                  ),
                ),

                if (!isConnected)
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
                    left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'CONNECTING TO FLEET SERVER...',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2),
                            ),
                          ],
                        ),
                      ),
                    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
                  ),

                // Header Content
                Column(
                  children: [
                    Container(
                      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + (isConnected ? 10 : 30), 20, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
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
                                    Text('Manager Panel', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              _buildAppBarAction(Icons.person_outline_rounded, () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()));
                              }),
                              _buildAppBarAction(Icons.download_rounded, _downloadReport),
                              _buildAppBarAction(Icons.logout_rounded, () {
                                 Provider.of<AuthService>(context, listen: false).logout();
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Custom Tab Bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.1)),
                      ),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicator: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.deepPurpleAccent.withValues(alpha: 0.2),
                              Colors.blueAccent.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                        ),
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.blueAccent,
                        unselectedLabelColor: Colors.white24,
                        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 10),
                        tabs: [
                          const Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: 'Fleet'),
                          const Tab(icon: Icon(Icons.map_rounded, size: 20), text: 'Map'),
                          const Tab(icon: Icon(Icons.badge_rounded, size: 20), text: 'Drivers'),
                          const Tab(icon: Icon(Icons.people_alt_rounded, size: 20), text: 'Users'),
                          const Tab(icon: Icon(Icons.route_rounded, size: 20), text: 'Routes'),
                          Tab(
                            icon: Consumer<BusStore>(
                              builder: (_, store, __) => Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 20),
                                  if (store.unreadCount > 0)
                                    Positioned(
                                      top: -4, right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${store.unreadCount > 9 ? '9+' : store.unreadCount}',
                                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            text: 'Alerts',
                          ),
                          const Tab(icon: Icon(Icons.report_problem_rounded, size: 20), text: 'Complaints'),
                        ],
                      ),
                    ),

                    Expanded(
                      child: _isLoading 
                        ? _buildLoadingState()
                        : TabBarView(
                            children: [
                              const FleetMaintenanceScreen(nested: true),
                              _buildMapTab(),
                              _buildDriverTab(),
                              _buildUserTab(),
                              const RouteManagementScreen(nested: true),
                              _buildAlertTab(),
                              const ComplaintManagerScreen(nested: true),
                            ],
                          ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBarAction(IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: IconButton(
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        icon: Icon(icon, color: Colors.white, size: 18),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  Widget _buildFleetTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        final buses = busStore.allBuses;
        if (buses.isEmpty) return _buildEmptyState('No fleet active', Icons.bus_alert_rounded);

        final int activeBuses  = buses.where((b) => b.status != 'Offline').length;
        final int onTimeBuses  = buses.where((b) => b.status == 'On-time').length;
        final int delayedBuses = buses.where((b) => b.status == 'Delayed').length;

        return Column(
          children: [
            // Analytics Header
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  _buildAnalyticsCard('FLEET CAPACITY', '$activeBuses/${buses.length}', Icons.sensors_rounded, Colors.deepPurpleAccent),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('OPTIMIZED', '$onTimeBuses', Icons.bolt_rounded, Colors.blueAccent),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('ANOMALIES', '$delayedBuses', Icons.error_outline_rounded, Colors.redAccent),
                  const SizedBox(width: 12),
                  _buildAnalyticsCard('Total Users', '${_users.length}', Icons.query_stats_rounded, Colors.white),
                ],
              ).animate().slideX(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.easeOutCubic).fadeIn(),
            ),
            // Fleet List
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                backgroundColor: const Color(0xFF0D0B14),
                color: Colors.deepPurpleAccent,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: buses.length,
                  itemBuilder: (context, index) {
                    final bus = buses[index];
                    return _buildGlassCard(
                      index: index,
                      child: Row(
                        children: [
                          _buildStatusIndicator(bus.status == 'On-time'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'UNIT_${bus.id.substring(bus.id.length - 4).toUpperCase()}',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Route: ${bus.routeName.toUpperCase()}',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    // ── Live speed badge ───────────────────────────
                                    if (bus.status != 'Offline')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          '${bus.speed.toStringAsFixed(1)} KM/H',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.blueAccent,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _buildBadge(bus.occupancy, _getOccupancyColor(bus.occupancy)),
                                    _buildBadge(bus.status, _getStatusColor(bus.status)),
                                    // ── Prominent Report & Download Button on Every Bus Card ──
                                    GestureDetector(
                                      onTap: () => _showBusReportSheet(bus),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.picture_as_pdf_rounded, color: Colors.blueAccent, size: 12),
                                            const SizedBox(width: 4),
                                            Text(
                                              'REPORT',
                                              style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildActionButton(Icons.bar_chart_rounded, () => _showBusReportSheet(bus)),
                              const SizedBox(height: 8),
                              _buildActionButton(Icons.tune_rounded, () => _showBusActionDialog(bus)),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: (math.min(index, 6) * 30).ms).slideY(begin: 0.1);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2
          )
        ]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverTab() {
    return Column(
      children: [
        // Action Header Card
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL DRIVERS: ${_drivers.length}',
                      style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    Text(
                      'Manage profiles, licenses & documents',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showAddDriverDialog,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: Text('Add Driver', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                  foregroundColor: Colors.blueAccent,
                  side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ),

        // List View
        Expanded(
          child: _drivers.isEmpty
              ? _buildEmptyState('No drivers available', Icons.person_off_rounded)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: _drivers.length,
                    itemBuilder: (context, index) {
                      final driver = _drivers[index];
                      final bool isActive = driver['status'] != 'Suspended';
                      final String license = driver['licenseNumber']?.toString().isNotEmpty == true
                          ? driver['licenseNumber'].toString()
                          : 'No License';
                      final String phone = driver['contactNumber']?.toString().isNotEmpty == true
                          ? driver['contactNumber'].toString()
                          : '';

                      final assignedBusId = driver['assignedBus'];
                      final bus = _rawBuses.firstWhere(
                        (b) => b['_id'] == assignedBusId, 
                        orElse: () => null
                      );
                      final String assignedBusText = bus != null 
                          ? (() {
                              final String busName = bus['name']?.toString() ?? '';
                              final String busLabel = busName.contains(' - ') 
                                  ? busName.split(' - ').first 
                                  : 'Bus';
                              final String busNum = bus['busNumber']?.toString() ?? 'N/A';
                              final String cleanPlate = (busNum.isNotEmpty && busNum != 'N/A') 
                                  ? ' ($busNum)' 
                                  : '';
                              return '$busLabel$cleanPlate';
                            })().toUpperCase()
                          : 'UNASSIGNED';

                      return _buildGlassCard(
                        index: index,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Row: Avatar + Driver Name & Info + Status + Menu
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  height: 44, width: 44,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        (isActive ? Colors.blueAccent : Colors.redAccent).withValues(alpha: 0.2),
                                        (isActive ? Colors.deepPurpleAccent : Colors.redAccent).withValues(alpha: 0.08),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: (isActive ? Colors.blueAccent : Colors.redAccent).withValues(alpha: 0.3)),
                                  ),
                                  child: Icon(Icons.shield_rounded, color: isActive ? Colors.blueAccent : Colors.redAccent, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (driver['name'] ?? driver['username']).toString().toUpperCase(),
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          letterSpacing: 0.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        phone.isNotEmpty ? '@${driver['username']}  •  $phone' : '@${driver['username']}',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildStatusChip(isActive ? 'OPERATIONAL' : 'SUSPENDED', isActive),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white38),
                                  color: const Color(0xFF1E1E1E),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    side: const BorderSide(color: Colors.white10),
                                  ),
                                  onSelected: (value) async {
                                    if (value == 'Profile') {
                                      _showDriverProfileSheet(driver);
                                    } else if (value == 'AssignBus') {
                                      _showAssignBusDialog(driver);
                                    } else if (value == 'Delete') {
                                      _deleteDriver(driver['_id']);
                                    } else {
                                      final newStatus = value == 'Suspend' ? 'Suspended' : 'Active';
                                      await _apiService.put('manager/drivers/${driver['_id']}', {'status': newStatus});
                                      _loadData();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'Profile',
                                      child: Text('Profile & Documents', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                    PopupMenuItem(
                                      value: isActive ? 'Suspend' : 'Activate',
                                      child: Text(isActive ? 'Suspend Driver' : 'Activate Driver', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                    PopupMenuItem(
                                      value: 'AssignBus',
                                      child: Text('Assign Bus', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                    PopupMenuItem(
                                      value: 'Delete',
                                      child: Text('Delete Driver', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Middle Info Badges Row (Assigned Bus & License Number)
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 80),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.directions_bus_rounded, color: Colors.blueAccent, size: 13),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'BUS: $assignedBusText',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.blueAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 80),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.card_membership_rounded, color: Colors.deepPurpleAccent, size: 13),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'LICENSE: $license',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.deepPurpleAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Bottom Action Button: Profile & Documents
                            InkWell(
                              onTap: () => _showDriverProfileSheet(driver),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.deepPurpleAccent.withValues(alpha: 0.18),
                                      Colors.blueAccent.withValues(alpha: 0.08),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.folder_shared_rounded, color: Colors.blueAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Profile & Important Documents',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 11),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: (math.min(index, 6) * 30).ms).slideY(begin: 0.1);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _showAddDriverDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final licenseCtrl = TextEditingController();
    final emergencyCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.blueAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Add New Driver',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStyledDialogTextField(nameCtrl, 'Driver Full Name *', Icons.person_outline_rounded),
                const SizedBox(height: 12),
                _buildStyledDialogTextField(usernameCtrl, 'Username * (e.g. driver31)', Icons.badge_outlined),
                const SizedBox(height: 12),
                _buildStyledDialogTextField(passwordCtrl, 'Initial Password *', Icons.lock_outline_rounded, isPassword: true),
                const SizedBox(height: 12),
                _buildStyledDialogTextField(phoneCtrl, 'Contact Phone Number', Icons.phone_android_rounded, keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                _buildStyledDialogTextField(licenseCtrl, 'Driving License Number', Icons.card_membership_rounded),
                const SizedBox(height: 12),
                _buildStyledDialogTextField(emergencyCtrl, 'Emergency Contact Phone', Icons.contact_phone_rounded, keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                _buildStyledDialogTextField(addressCtrl, 'Address / Notes', Icons.home_work_rounded),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty || usernameCtrl.text.trim().isEmpty || passwordCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill in Name, Username, and Password'), backgroundColor: Colors.orange),
                        );
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      try {
                        await _apiService.post('manager/drivers', {
                          'name': nameCtrl.text.trim(),
                          'username': usernameCtrl.text.trim(),
                          'password': passwordCtrl.text.trim(),
                          'contactNumber': phoneCtrl.text.trim(),
                          'licenseNumber': licenseCtrl.text.trim(),
                          'emergencyContact': emergencyCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                          'notes': notesCtrl.text.trim(),
                        });
                        if (mounted && context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Driver created successfully!'), backgroundColor: Colors.green),
                          );
                          _loadData();
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: ${e.toString().replaceAll('ApiException(409):', '').replaceAll('Exception:', '').trim()}'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Create Driver', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyledDialogTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 18),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.blueAccent),
        ),
      ),
    );
  }

  void _showDriverProfileSheet(Map<String, dynamic> initialDriver) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final driver = _drivers.firstWhere(
            (d) => d['_id'] == initialDriver['_id'],
            orElse: () => initialDriver,
          );

          final bool isActive = driver['status'] != 'Suspended';
          final assignedBusId = driver['assignedBus'];
          final bus = _rawBuses.firstWhere(
            (b) => b['_id'] == assignedBusId, 
            orElse: () => null
          );
          final String assignedBusText = bus != null 
              ? '${bus['name'] ?? 'Bus'} (${bus['busNumber'] ?? ''})'
              : 'UNASSIGNED';

          final List<dynamic> documents = driver['documents'] is List ? driver['documents'] : [];

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFF18181B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Container(
                        height: 56, width: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blueAccent.withValues(alpha: 0.25),
                              Colors.deepPurpleAccent.withValues(alpha: 0.1),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.blueAccent, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (driver['name'] ?? driver['username']).toString().toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Username: @${driver['username']}',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusChip(isActive ? 'OPERATIONAL' : 'SUSPENDED', isActive),
                    ],
                  ),
                ),

                const Divider(color: Colors.white10, height: 1),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'DRIVER DETAILS & CONTACT',
                        style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 12),
                      _buildDriverDetailTile(Icons.phone_android_rounded, 'PHONE NUMBER', driver['contactNumber']?.toString().isNotEmpty == true ? driver['contactNumber'].toString() : 'Not Provided'),
                      const SizedBox(height: 8),
                      _buildDriverDetailTile(Icons.card_membership_rounded, 'LICENSE NUMBER', driver['licenseNumber']?.toString().isNotEmpty == true ? driver['licenseNumber'].toString() : 'Not Provided'),
                      const SizedBox(height: 8),
                      _buildDriverDetailTile(Icons.contact_phone_rounded, 'EMERGENCY CONTACT', driver['emergencyContact']?.toString().isNotEmpty == true ? driver['emergencyContact'].toString() : 'Not Provided'),
                      const SizedBox(height: 8),
                      _buildDriverDetailTile(Icons.directions_bus_rounded, 'ASSIGNED VEHICLE', assignedBusText),
                      const SizedBox(height: 8),
                      _buildDriverDetailTile(Icons.home_work_rounded, 'ADDRESS / NOTES', driver['address']?.toString().isNotEmpty == true ? driver['address'].toString() : (driver['notes']?.toString() ?? 'None')),

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'IMPORTANT DOCUMENTS (${documents.length})',
                                  style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'License copy, ID proof, medical certs',
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                              foregroundColor: Colors.blueAccent,
                              side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () => _uploadDriverDocument(driver, setSheetState),
                            icon: const Icon(Icons.upload_file_rounded, size: 16),
                            label: Text('Upload Doc', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (documents.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.folder_open_rounded, color: Colors.white24, size: 36),
                              const SizedBox(height: 8),
                              Text('No documents uploaded yet', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text('Click "Upload Doc" to attach license copies or certificates', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10), textAlign: TextAlign.center),
                            ],
                          ),
                        )
                      else
                        ...documents.map((doc) {
                          final String docName = doc['name']?.toString() ?? 'Document';
                          final String docType = doc['fileType']?.toString() ?? 'File';
                          final String url = doc['url']?.toString() ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    docType.toLowerCase().contains('pdf') ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                                    color: Colors.deepPurpleAccent, size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        docName,
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        docType.toUpperCase(),
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.visibility_rounded, color: Colors.blueAccent, size: 20),
                                  onPressed: () => _viewDriverDocument(docName, url),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                  onPressed: () => _deleteDriverDocument(driver['_id'].toString(), doc['_id'].toString(), setSheetState),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDriverDetailTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadDriverDocument(Map<String, dynamic> driver, StateSetter setSheetState) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file data'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      final ext = file.extension?.toLowerCase() ?? 'file';
      final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
      final base64Str = base64Encode(file.bytes!);
      final dataUri = 'data:$mime;base64,$base64Str';

      final titleCtrl = TextEditingController(text: file.name);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Document Title', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          content: TextField(
            controller: titleCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Document Name (e.g. Driving License)',
              labelStyle: TextStyle(color: Colors.white38, fontSize: 11),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                final docTitle = titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : file.name;
                Navigator.pop(ctx);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Uploading document...'), backgroundColor: Colors.blueAccent),
                );

                try {
                  await _apiService.post('manager/drivers/${driver['_id']}/documents', {
                    'name': docTitle,
                    'url': dataUri,
                    'fileType': ext.toUpperCase(),
                  });
                  await _loadData();
                  setSheetState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Document uploaded successfully!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              },
              child: Text('Save & Upload', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  void _viewDriverDocument(String title, String url) async {
    if (url.startsWith('data:')) {
      if (url.contains('image')) {
        final base64Content = url.split(',').last;
        final bytes = base64Decode(base64Content);
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: const Color(0xFF1E1E1E),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                Image.memory(bytes, fit: BoxFit.contain),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              ],
            ),
          ),
        );
        return;
      }
    }

    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Document saved ($title). Unable to open external viewer.'), backgroundColor: Colors.blueAccent),
        );
      }
    }
  }

  Future<void> _deleteDriverDocument(String driverId, String docId, StateSetter setSheetState) async {
    try {
      await _apiService.delete('manager/drivers/$driverId/documents/$docId');
      await _loadData();
      setSheetState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document removed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete document: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteDriver(String driverId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Delete Driver', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to permanently delete this driver account?', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _apiService.delete('manager/drivers/$driverId');
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Driver deleted successfully'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTab() {
    return Column(
      children: [
        // Action header card
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RegistrationManagerScreen(routes: _routes),
                      ),
                    );
                  },
                  icon: const Icon(Icons.app_registration_rounded, size: 18),
                  label: Text('Approvals', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.12),
                    foregroundColor: Colors.blueAccent,
                    side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.25)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _bulkParsedSubmissions = [];
                    });
                    _showBulkImportBottomSheet();
                  },
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text('Bulk Import', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                    foregroundColor: Colors.deepPurpleAccent,
                    side: BorderSide(color: Colors.deepPurpleAccent.withValues(alpha: 0.25)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Semester Filter Chips
        () {
          final semesters = _users
              .map((u) => u['courseName']?.toString().trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          semesters.sort();
          if (semesters.isEmpty) return const SizedBox.shrink();
          
          return Container(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                GestureDetector(
                  onTap: () => setState(() => _selectedUserSemesterFilter = 'All'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedUserSemesterFilter == 'All' 
                          ? Colors.blueAccent.withValues(alpha: 0.15) 
                          : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectedUserSemesterFilter == 'All' 
                            ? Colors.blueAccent.withValues(alpha: 0.4) 
                            : Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'ALL',
                        style: GoogleFonts.plusJakartaSans(
                          color: _selectedUserSemesterFilter == 'All' ? Colors.blueAccent : Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                ...semesters.map((sem) {
                  final isSelected = _selectedUserSemesterFilter == sem;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedUserSemesterFilter = sem),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? Colors.blueAccent.withValues(alpha: 0.15) 
                            : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected 
                              ? Colors.blueAccent.withValues(alpha: 0.4) 
                              : Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          sem.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            color: isSelected ? Colors.blueAccent : Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }(),

        Expanded(
          child: _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_outlined, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'No registered users',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              : () {
                  final filteredUsers = _selectedUserSemesterFilter == 'All'
                      ? _users
                      : _users.where((u) => u['courseName']?.toString().trim() == _selectedUserSemesterFilter).toList();
                  
                  if (filteredUsers.isEmpty) {
                    return Center(
                      child: Text(
                        'No users in $_selectedUserSemesterFilter',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    );
                  }
                  
                  return RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        final userSemester = user['courseName']?.toString().trim() ?? '';
                        final status = user['status']?.toString() ?? 'Active';
                        final routeId = user['routeId'];
                        
                        RouteModel? matchedRoute;
                        if (routeId != null) {
                          try {
                            matchedRoute = _routes.firstWhere((r) => r.id == routeId);
                          } catch (_) {}
                        }

                        return _buildUserGlassCard(
                          status: status,
                          onTap: () => _showUserDetailsBottomSheet(user),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: status.toLowerCase() == 'active' 
                                      ? Colors.blueAccent.withValues(alpha: 0.1) 
                                      : Colors.orangeAccent.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: status.toLowerCase() == 'active' 
                                        ? Colors.blueAccent.withValues(alpha: 0.2) 
                                        : Colors.orangeAccent.withValues(alpha: 0.2)
                                  ),
                                ),
                                child: Icon(
                                  Icons.person_rounded, 
                                  color: status.toLowerCase() == 'active' ? Colors.blueAccent : Colors.orangeAccent, 
                                  size: 20
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            user['name'] ?? user['username'] ?? 'Unknown',
                                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (userSemester.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blueAccent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.25)),
                                            ),
                                            child: Text(
                                              userSemester.toUpperCase(),
                                              style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 8, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text('UID: ${user['userId'] ?? user['username'] ?? 'N/A'}', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        // Route Badge
                                        if (matchedRoute != null)
                                          Flexible(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.3)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.route_rounded, size: 8, color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF')))),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      matchedRoute.name.toUpperCase(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: GoogleFonts.plusJakartaSans(
                                                        color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF'))),
                                                        fontSize: 7,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.route_outlined, size: 8, color: Colors.white38),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'NO ROUTE',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    color: Colors.white38,
                                                    fontSize: 7,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        const SizedBox(width: 8),
                                        // Pickup Stop
                                        Expanded(
                                          child: Text(
                                            user['pickupPoint'] ?? 'NOT CONFIGURED', 
                                            style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                }(),
        ),
      ],
    );
  }

  List<Map<String, String>> _parseBulkInput(String text) {
    final List<Map<String, String>> parsed = [];
    
    // Check if content is HTML-like (contains <table or <tr)
    final isHtml = text.contains('<tr') || text.contains('<table');
    
    List<List<String>> rows = [];
    
    if (isHtml) {
      // Parse HTML table rows using Regex
      final rowRegExp = RegExp(r'<tr[^>]*>([\s\S]*?)<\/tr>', caseSensitive: true);
      final cellRegExp = RegExp(r'<t[dh][^>]*>([\s\S]*?)<\/t[dh]>', caseSensitive: true);
      final tagRegExp = RegExp(r'<[^>]*>'); // To strip any nested HTML tags
      
      final rowMatches = rowRegExp.allMatches(text);
      for (var rowMatch in rowMatches) {
        final rowContent = rowMatch.group(1) ?? '';
        final cellMatches = cellRegExp.allMatches(rowContent);
        final List<String> rowCells = [];
        for (var cellMatch in cellMatches) {
          var cellText = cellMatch.group(1) ?? '';
          // Clean cell text: strip tags and decode basic HTML entities
          cellText = cellText.replaceAll(tagRegExp, '').trim();
          cellText = cellText
              .replaceAll('&amp;', '&')
              .replaceAll('&quot;', '"')
              .replaceAll('&#39;', "'")
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>');
          rowCells.add(cellText);
        }
        if (rowCells.isNotEmpty) {
          rows.add(rowCells);
        }
      }
    } else {
      // Parse normal CSV/TSV/plain text
      final lines = text.split('\n');
      for (var line in lines) {
        if (line.trim().isEmpty) continue;
        final delimiter = line.contains('\t') ? '\t' : ',';
        final parts = line.split(delimiter).map((p) => p.trim()).toList();
        rows.add(parts);
      }
    }

    if (rows.isEmpty) return parsed;

    // Identify header row dynamically by matching keywords
    int headerRowIndex = -1;
    Map<String, int> columnMapping = {
      'name': -1,
      'studentId': -1,
      'phone': -1,
      'email': -1,
      'gender': -1,
      'fatherName': -1,
      'courseName': -1,
      'fatherPhone': -1,
      'pickupStop': -1,
      'routeName': -1,
    };

    // Search first few rows for header keywords
    for (int i = 0; i < rows.length && i < 3; i++) {
      final row = rows[i];
      bool hasKeywords = false;
      for (int j = 0; j < row.length; j++) {
        final val = row[j].toLowerCase();
        if (val.contains('enrollment') || val.contains('student id') || val.contains('studentid') || (val == 'id') || val.contains('enrollment no')) {
          columnMapping['studentId'] = j;
          hasKeywords = true;
        } else if (val.contains('father mobile') || val.contains('father phone') || val.contains('father mobile number') || val.contains('parent mobile') || val.contains('parent phone')) {
          columnMapping['fatherPhone'] = j;
          hasKeywords = true;
        } else if (val.contains('father name') || val.contains('father') || val.contains('guardian')) {
          columnMapping['fatherName'] = j;
          hasKeywords = true;
        } else if (val.contains('course name') || val.contains('course') || val.contains('branch') || val.contains('class')) {
          columnMapping['courseName'] = j;
          hasKeywords = true;
        } else if ((val.contains('student name') || val.contains('name') || val == 'student') && !val.contains('father') && !val.contains('course')) {
          columnMapping['name'] = j;
          hasKeywords = true;
        } else if (val.contains('mobile') || val.contains('phone') || val.contains('contact')) {
          columnMapping['phone'] = j;
          hasKeywords = true;
        } else if (val.contains('email')) {
          columnMapping['email'] = j;
          hasKeywords = true;
        } else if (val.contains('gender') || val == 'sex') {
          columnMapping['gender'] = j;
          hasKeywords = true;
        } else if (val.contains('address') || val.contains('stop') || val.contains('pickup')) {
          columnMapping['pickupStop'] = j;
          hasKeywords = true;
        } else if (val.contains('route')) {
          columnMapping['routeName'] = j;
          hasKeywords = true;
        }
      }
      if (hasKeywords && columnMapping['studentId'] != -1 && columnMapping['name'] != -1) {
        headerRowIndex = i;
        break;
      }
    }

    // Parse data rows
    final startRowIndex = headerRowIndex + 1;
    for (int i = startRowIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 3) continue;

      String name = '';
      String studentId = '';
      String phone = '';
      String email = '';
      String gender = '';
      String fatherName = '';
      String courseName = '';
      String fatherPhone = '';
      String pickupStop = '';
      String routeName = '';

      if (headerRowIndex != -1) {
        // Map columns dynamically based on detected headers
        if (columnMapping['name']! < row.length && columnMapping['name']! != -1) {
          name = row[columnMapping['name']!];
        }
        if (columnMapping['studentId']! < row.length && columnMapping['studentId']! != -1) {
          studentId = row[columnMapping['studentId']!];
        }
        if (columnMapping['phone']! < row.length && columnMapping['phone']! != -1) {
          phone = row[columnMapping['phone']!];
        }
        if (columnMapping['email']! < row.length && columnMapping['email']! != -1) {
          email = row[columnMapping['email']!];
        }
        if (columnMapping['gender']! < row.length && columnMapping['gender']! != -1) {
          gender = row[columnMapping['gender']!];
        }
        if (columnMapping['fatherName']! < row.length && columnMapping['fatherName']! != -1) {
          fatherName = row[columnMapping['fatherName']!];
        }
        if (columnMapping['courseName']! < row.length && columnMapping['courseName']! != -1) {
          courseName = row[columnMapping['courseName']!];
        }
        if (columnMapping['fatherPhone']! < row.length && columnMapping['fatherPhone']! != -1) {
          fatherPhone = row[columnMapping['fatherPhone']!];
        }
        if (columnMapping['pickupStop']! < row.length && columnMapping['pickupStop']! != -1) {
          pickupStop = row[columnMapping['pickupStop']!];
        }
        if (columnMapping['routeName']! < row.length && columnMapping['routeName']! != -1) {
          routeName = row[columnMapping['routeName']!];
        }
      } else {
        // Fallback: hardcoded index mapping
        name = row[0];
        gender = row.length > 1 ? row[1] : '';
        fatherName = row.length > 2 ? row[2] : '';
        courseName = row.length > 3 ? row[3] : '';
        phone = row.length > 4 ? row[4] : '';
        email = row.length > 5 ? row[5] : '';
        studentId = row.length > 6 ? row[6] : '';
        fatherPhone = row.length > 7 ? row[7] : '';
        pickupStop = row.length > 8 ? row[8] : '';
      }

      if (name.isNotEmpty && studentId.isNotEmpty && phone.isNotEmpty) {
        // Ignore header duplication in data if any
        if (studentId.toLowerCase().contains('id') || name.toLowerCase() == 'name' || studentId.toLowerCase().contains('enrollment')) {
          continue;
        }
        parsed.add({
          'name': name,
          'studentId': studentId,
          'phone': phone,
          'email': email,
          'gender': gender,
          'fatherName': fatherName,
          'courseName': courseName,
          'fatherPhone': fatherPhone,
          'pickupStop': pickupStop,
          'routeName': routeName,
        });
      }
    }
    return parsed;
  }

  Future<void> _pickAndParseFile(StateSetter setSheetState) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'tsv', 'txt', 'xls', 'xlsx'],
      );
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;
        final file = File(filePath);
        final content = await file.readAsString();
        
        // Auto-detect semester/batch from file name (e.g. "CSE_E 6th Sem.xls" -> "CSE_E 6th Sem")
        String detectedSem = '';
        final semReg = RegExp(r'(\d+(st|nd|rd|th)\s*(sem|semester|year|yr))', caseSensitive: false);
        final match = semReg.firstMatch(fileName);
        if (match != null) {
          detectedSem = match.group(0)!;
          // Try to prepend anything before it (e.g., "CSE_E")
          final prefixIndex = fileName.indexOf(detectedSem);
          if (prefixIndex > 0) {
            final prefix = fileName.substring(0, prefixIndex).trim();
            if (prefix.isNotEmpty) {
              detectedSem = "$prefix $detectedSem";
            }
          }
        } else {
          // Fallback: take file name without extension
          detectedSem = fileName.split('.').first;
        }

        // Clean up formatting
        detectedSem = detectedSem.replaceAll('_', ' ').replaceAll('-', ' ').trim();
        
        final parsed = _parseBulkInput(content);
        
        // Assign detected semester to courseName if courseName is empty
        for (var s in parsed) {
          if (s['courseName'] == null || s['courseName']!.isEmpty) {
            s['courseName'] = detectedSem;
          }
        }
        
        _bulkSemesterController.text = detectedSem;
        
        setSheetState(() {
          _bulkParsedSubmissions = parsed;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully loaded ${parsed.length} records from file!',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF38EF7D),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading file: ${e.toString().replaceAll('Exception:', '')}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool> _submitBulkImport() async {
    if (_bulkParsedSubmissions.isEmpty) return false;
    try {
      final response = await _apiService.post('manager/registrations/bulk', {
        'submissions': _bulkParsedSubmissions,
      });
      if (response != null && response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Successfully imported ${response['importedCount'] ?? _bulkParsedSubmissions.length} student records!',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF38EF7D),
            behavior: SnackBarBehavior.floating,
          ));
        }
        setState(() {
          _bulkParsedSubmissions = [];
        });
        return true;
      } else {
        throw Exception('Server returned failure status.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Bulk import failed: ${e.toString().replaceAll('Exception:', '')}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return false;
    }
  }

  void _showBulkImportBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF0F1528),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  // Header handle
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_upload_rounded, color: Colors.blueAccent, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Bulk Import Students',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Paste CSV/TSV data below (e.g., copied from Excel/Google Sheets)',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Text Area & Preview split
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Semester/Batch input field
                          Text(
                            'SEMESTER / BATCH / CLASS TAG',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: TextField(
                              controller: _bulkSemesterController,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g., CSE_E 6th Sem, ME 4th Sem',
                                hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white12, fontSize: 13),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              onChanged: (val) {
                                // Dynamically update semester for all parsed rows
                                setSheetState(() {
                                  for (var s in _bulkParsedSubmissions) {
                                    s['courseName'] = val.trim();
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 20),

                          // File picker button
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blueAccent.withValues(alpha: 0.15),
                                  Colors.deepPurpleAccent.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.25)),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _pickAndParseFile(setSheetState),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.file_present_rounded, color: Colors.blueAccent, size: 36),
                                      const SizedBox(height: 8),
                                      Text(
                                        'CHOOSE CSV / XLS FILE',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Select a student sheet directly from your device',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white38,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // OR divider
                          Row(
                            children: [
                              const Expanded(child: Divider(color: Colors.white10)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'OR PASTE TEXT',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white24,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              const Expanded(child: Divider(color: Colors.white10)),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Text Area Container
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: TextField(
                              maxLines: 6,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Example:\nName,StudentID,Phone,Email,RouteName,PickupStop\nJohn Doe,SISTEC001,9876543210,john@example.com,Gandhinagar,St. John Stop',
                                hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white12, fontSize: 12),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                              onChanged: (text) {
                                setSheetState(() {
                                  _bulkParsedSubmissions = _parseBulkInput(text);
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Previews header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'DETECTED STUDENTS',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white24,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${_bulkParsedSubmissions.length} found',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.blueAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          // Preview List
                          if (_bulkParsedSubmissions.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    const Icon(Icons.table_rows_rounded, color: Colors.white12, size: 40),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Waiting for data input...',
                                      style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _bulkParsedSubmissions.length > 5 ? 5 : _bulkParsedSubmissions.length,
                              itemBuilder: (context, idx) {
                                final s = _bulkParsedSubmissions[idx];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E1E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s['name'] ?? '',
                                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            s['studentId'] ?? '',
                                            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      
                                      // Render parsed information (Gender, Course)
                                      if ((s['courseName']?.isNotEmpty ?? false) || (s['gender']?.isNotEmpty ?? false))
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Text(
                                            '${s['courseName'] ?? ''}${s['courseName'] != null && s['courseName']!.isNotEmpty && s['gender'] != null && s['gender']!.isNotEmpty ? "  •  " : ""}${s['gender'] ?? ''}',
                                            style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      if ((s['fatherName']?.isNotEmpty ?? false) || (s['fatherPhone']?.isNotEmpty ?? false))
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: Text(
                                            'Father: ${s['fatherName'] ?? 'N/A'} ${s['fatherPhone'] != null && s['fatherPhone']!.isNotEmpty ? "(${s['fatherPhone']})" : ""}',
                                            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11),
                                          ),
                                        ),
                                      
                                      Row(
                                        children: [
                                          const Icon(Icons.phone_rounded, color: Colors.blueAccent, size: 12),
                                          const SizedBox(width: 6),
                                          Text(s['phone'] ?? '', style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 12)),
                                          const SizedBox(width: 16),
                                          const Icon(Icons.email_rounded, color: Colors.blueAccent, size: 12),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(s['email'] ?? 'No email', 
                                              style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      if (s['pickupStop'] != null && s['pickupStop']!.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.home_rounded, color: Colors.white24, size: 12),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text('Address: ${s['pickupStop']}', 
                                                style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],

                                      const SizedBox(height: 12),
                                      const Divider(color: Colors.white10),
                                      const SizedBox(height: 6),
                                      Text(
                                        'ASSIGN PICKUP LOCATION',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          // Route selection dropdown
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: _routes.any((r) => r.name == s['routeName']) 
                                                      ? s['routeName'] 
                                                      : null,
                                                  hint: Text('Select Route', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11)),
                                                  dropdownColor: const Color(0xFF1E1E1E),
                                                  isExpanded: true,
                                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent, size: 18),
                                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                  items: _routes.map((r) {
                                                    return DropdownMenuItem<String>(
                                                      value: r.name,
                                                      child: Text(r.name),
                                                    );
                                                  }).toList(),
                                                  onChanged: (val) {
                                                    setSheetState(() {
                                                      s['routeName'] = val ?? '';
                                                      s['pickupStop'] = ''; // reset stop
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Stop selection dropdown
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: (s['routeName'] != null && 
                                                          s['routeName']!.isNotEmpty && 
                                                          _routes.any((r) => r.name == s['routeName'] && r.stops.any((st) => st['name'] == s['pickupStop'])))
                                                      ? s['pickupStop']
                                                      : null,
                                                  hint: Text('Select Stop', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11)),
                                                  dropdownColor: const Color(0xFF1E1E1E),
                                                  isExpanded: true,
                                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent, size: 18),
                                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                  items: () {
                                                    if (s['routeName'] == null || s['routeName']!.isEmpty) return <DropdownMenuItem<String>>[];
                                                    final route = _routes.firstWhere((r) => r.name == s['routeName'], orElse: () => _routes.first);
                                                    return route.stops.map<DropdownMenuItem<String>>((st) {
                                                      final stopName = st['name']?.toString() ?? '';
                                                      return DropdownMenuItem<String>(
                                                        value: stopName,
                                                        child: Text(stopName),
                                                      );
                                                    }).toList();
                                                  }(),
                                                  onChanged: (s['routeName'] == null || s['routeName']!.isEmpty) ? null : (val) {
                                                    setSheetState(() {
                                                      s['pickupStop'] = val ?? '';
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            if (_bulkParsedSubmissions.length > 5) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2D5BFF).withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF2D5BFF).withValues(alpha: 0.15)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'And ${_bulkParsedSubmissions.length - 5} more students will be imported automatically. (You can view and manage their assignments on the registrations list page.)',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                  
                  // Action Footer
                  Container(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
                    decoration: const BoxDecoration(
                      color: Color(0xFF131A30),
                      border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _bulkParsedSubmissions.isEmpty || _isBulkSaving
                            ? null
                            : () async {
                                setSheetState(() => _isBulkSaving = true);
                                final success = await _submitBulkImport();
                                if (sheetContext.mounted) {
                                  setSheetState(() => _isBulkSaving = false);
                                }
                                if (success && sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                  // Open registration manager screen
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RegistrationManagerScreen(routes: _routes),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D5BFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isBulkSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                'SAVE & IMPORT ${_bulkParsedSubmissions.length} RECORDS',
                                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 1),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAudienceChip(String value, String label, IconData icon, Color accentColor) {
    final bool isSelected = _selectedTargetAudience == value;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 14,
        color: isSelected ? accentColor : Colors.white60,
      ),
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: accentColor.withValues(alpha: 0.2),
      backgroundColor: const Color(0xFF1E2638),
      side: BorderSide(
        color: isSelected ? accentColor : Colors.white.withValues(alpha: 0.08),
        width: isSelected ? 1.5 : 1.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedTargetAudience = value;
          });
        }
      },
    );
  }

  Color _getAudienceColor(String? audience) {
    final aud = (audience ?? 'All').toLowerCase();
    switch (aud) {
      case 'users':
        return Colors.cyanAccent;
      case 'drivers':
        return Colors.amberAccent;
      case 'admins':
        return Colors.purpleAccent;
      default:
        return Colors.blueAccent;
    }
  }

  Widget _buildAlertTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) {
        // Mark all read when this tab is viewed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (busStore.unreadCount > 0) busStore.markAllRead();
        });

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            // ── Broadcast Composer ─────────────────────────────────────
            Text('Broadcast Message', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text('Send notifications to targeted app user groups.', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.05), blurRadius: 20),
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Audience Selector Chips
                  Text(
                    'SELECT TARGET AUDIENCE',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildAudienceChip('All', 'Everyone', Icons.public_rounded, Colors.blueAccent),
                        const SizedBox(width: 8),
                        _buildAudienceChip('Users', 'Students', Icons.school_rounded, Colors.cyanAccent),
                        const SizedBox(width: 8),
                        _buildAudienceChip('Drivers', 'Drivers', Icons.directions_bus_rounded, Colors.amberAccent),
                        const SizedBox(width: 8),
                        _buildAudienceChip('Admins', 'Admins', Icons.admin_panel_settings_rounded, Colors.purpleAccent),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notifController,
                    maxLines: 4,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Enter directive message for ${_selectedTargetAudience == 'All' ? 'everyone' : _selectedTargetAudience.toLowerCase()}...',
                      hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _isSending ? null : () async {
                      final msg = _notifController.text.trim();
                      if (msg.isEmpty) return;
                      setState(() => _isSending = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await _apiService.post('manager/notifications', {
                          'message': msg,
                          'targetAudience': _selectedTargetAudience,
                        });
                        if (!mounted) return;
                        _notifController.clear();
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.blueAccent,
                            behavior: SnackBarBehavior.floating,
                            content: Text('Broadcast sent to ${_selectedTargetAudience.toUpperCase()}', style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                      } finally {
                        if (mounted) setState(() => _isSending = false);
                      }
                    },
                    child: AnimatedContainer(
                      duration: 300.ms,
                      height: 64,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isSending
                            ? [Colors.deepPurpleAccent.withValues(alpha: 0.4), Colors.blueAccent.withValues(alpha: 0.4)]
                            : [Colors.deepPurpleAccent, Colors.blueAccent],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: _isSending
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Send Notification', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Live Notification Feed ──────────────────────────────────
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Recent Notifications',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                      ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.seconds),
                      const SizedBox(width: 6),
                      Text('REAL-TIME', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (busStore.notifications.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 40),
                      const SizedBox(height: 12),
                      Text('NO BROADCASTS YET', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    ],
                  ),
                ),
              )
            else
              ...busStore.notifications.asMap().entries.map((entry) {
                final i = entry.key;
                final n = entry.value;
                final isInfo = n.type == 'info';
                final accent = isInfo ? Colors.deepPurpleAccent : Colors.redAccent;
                final String targetAudienceText = (n.targetAudience.isEmpty ? 'All' : n.targetAudience);
                final audienceColor = _getAudienceColor(targetAudienceText);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(isInfo ? Icons.bolt_rounded : Icons.warning_rounded, color: accent, size: 16),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('DIRECTIVE', style: GoogleFonts.plusJakartaSans(color: accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: audienceColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: audienceColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    'TO: ${targetAudienceText.toUpperCase()}',
                                    style: GoogleFonts.plusJakartaSans(color: audienceColor, fontSize: 8, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(n.message, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 6),
                            Text(_formatTime(n.timestamp), style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                        tooltip: 'Delete Notification',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: Text('Delete Notification', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                              content: Text('Are you sure you want to delete this notification broadcast?', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            try {
                              await _apiService.delete('manager/notifications/${n.id}');
                            } catch (_) {
                              try {
                                await _apiService.delete('notifications/${n.id}');
                              } catch (_) {}
                            }
                            busStore.removeNotification(n.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Notification deleted', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: (i * 60).ms).slideX(begin: 0.1);
              }),
            const SizedBox(height: 20),
          ],
        );
      },
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'JUST NOW';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes} MINS AGO';
    if (diff.inHours < 24) return '${diff.inHours} HOURS AGO';
    return '${diff.inDays} DAYS AGO';
  }

  Widget _buildMapTab() {
    return Consumer<BusStore>(
      builder: (context, busStore, _) => BusMap(
        buses: busStore.allBuses,
        selectedRoute: null,
      ),
    );
  }

  void _showSystemAlertSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 50, left: 20, right: 20),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.blueAccent, size: 20),
              ).animate(onPlay: (controller) => controller.repeat()).shake(duration: 500.ms),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CORE DIRECTIVE', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 2),
                    Text(message, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showEmergencySOSOverlay(dynamic data) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xF2000000),
      transitionDuration: 400.ms,
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0B14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.redAccent, width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 5),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 72),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.15,1.15), duration: 600.ms),
                  const SizedBox(height: 32),
                  Text(
                    'Emergency Alert',
                    style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check on the driver.',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        _buildProfileTile('SOURCE', (data['role']?.toString().toUpperCase() ?? 'USER'), Icons.person_pin_rounded),
                        _buildProfileTile('ID', data['name'] ?? 'UNKNOWN', Icons.badge_rounded),
                        _buildProfileTile('LAT', data['latitude']?.toString() ?? 'N/A', Icons.location_on_rounded),
                        _buildProfileTile('LNG', data['longitude']?.toString() ?? 'N/A', Icons.location_on_rounded),
                        _buildProfileTile('TIMESTAMP', DateTime.tryParse(data['timestamp'] ?? '')?.toLocal().toString().split('.').first ?? 'NOW', Icons.timer_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Dismiss Alert', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
        );
      },
    );
  }

  Widget _buildProfileTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurpleAccent, size: 16),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const Spacer(),
          Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // Helper Widgets
  Widget _buildGlassCard({required Widget child, required int index}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool isGood) {
    return Container(
      height: 44, width: 4,
      decoration: BoxDecoration(
        color: isGood ? Colors.blueAccent : Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isGood ? Colors.blueAccent : Colors.redAccent).withValues(alpha: 0.4),
            blurRadius: 10,
          )
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool active) {
    final color = active ? Colors.blueAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.deepPurpleAccent, size: 22),
      onPressed: onTap,
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
          ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 24),
          Text(
            msg.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            'No activity detected.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Color _getOccupancyColor(String occ) {
    switch (occ.toLowerCase()) {
      case 'low': return Colors.blueAccent;
      case 'medium': return Colors.orangeAccent;
      case 'high': return Colors.redAccent;
      default: return Colors.deepPurpleAccent;
    }
  }

  Color _getStatusColor(String status) {
    return status == 'On-time' ? Colors.blueAccent : Colors.orangeAccent;
  }

  // Dialogs
  void _showBusActionDialog(Bus bus) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('SYSTEM CONTROL', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('UNIT_${bus.id.substring(bus.id.length - 4).toUpperCase()}', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 32),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _buildDialogOption('Reassign Driver', Icons.badge_rounded, Colors.deepPurpleAccent, () {
                      Navigator.pop(context);
                      _showBusDriverAssignmentDialog(bus);
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: Colors.white10),
                    ),
                    _buildDialogOption('Mark Operational', Icons.check_circle_rounded, Colors.blueAccent, () => _updateBus(bus, status: 'On-time')),
                    _buildDialogOption('Signal Delay', Icons.bolt_rounded, Colors.orangeAccent, () => _updateBus(bus, status: 'Delayed')),
                    Text('SECTOR REASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 16),
                    ..._routes.map((r) => _buildDialogOption(
                      r.name.toUpperCase(), 
                      Icons.radar_rounded, 
                      Color(int.parse(r.color.replaceAll('#', '0xFF'))), 
                      () => _updateBus(bus, routeId: r.id, routeName: r.name, routeColor: r.color)
                    )),
                  ],
                ),
              ),
            ],
          ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  void _showUserRouteDialog(dynamic user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('SECTOR ASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('USER: ${user['name']?.toUpperCase() ?? user['username']?.toUpperCase() ?? 'IDENTIFIED'}', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 32),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final r = _routes[index];
                    final color = Color(int.parse(r.color.replaceAll('#', '0xFF')));
                    return _buildDialogOption(r.name.toUpperCase(), Icons.hub_rounded, color, () async {
                      try {
                        await _apiService.put('manager/users/${user['_id']}', {'routeId': r.id});
                        if (!mounted) return;
                        _loadData();
                      } catch (e) {
                        debugPrint('Error assigning route: $e');
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  void _showUserDetailsBottomSheet(dynamic user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _UserDetailsBottomSheet(
          user: Map<String, dynamic>.from(user),
          routes: _routes,
          apiService: _apiService,
          onDataChanged: _loadData,
          onRouteSelect: (updatedUser) {
            _showUserRouteDialog(updatedUser);
          },
          onDeleteUser: (userId) async {
            setState(() => _isLoading = true);
            try {
              await _apiService.delete('manager/users/$userId');
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User account deleted successfully.'), backgroundColor: Colors.green),
                );
              }
            } catch (e) {
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: Colors.redAccent),
                );
              }
            }
          },
        );
      },
    );
  }

  Widget _buildUserGlassCard({required Widget child, required String status, required VoidCallback onTap}) {
    final isActive = status.toLowerCase() == 'active';
    final statusColor = isActive ? const Color(0xFF38EF7D) : Colors.orangeAccent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: statusColor, width: 4),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 20, 20, 20),
            child: child,
          ),
        ),
      ),
    );
  }

  void _showAssignBusDialog(dynamic driver) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('FLEET ASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 4),
              Text('DRIVER: ${(driver['name'] ?? driver['username']).toUpperCase()}', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 24),
              
              // Unassign Option
              _buildDialogOption('UNASSIGNED / NO BUS', Icons.close_rounded, Colors.redAccent, () async {
                try {
                  await _apiService.put('manager/drivers/${driver['_id']}', {'assignedBus': ''});
                  _loadData();
                } catch (e) {
                  debugPrint('Error unassigning bus: $e');
                }
              }),
              const Divider(color: Colors.white10, height: 16),
              
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _rawBuses.length,
                  itemBuilder: (context, index) {
                    final b = _rawBuses[index];
                    final String busName = b['name']?.toString() ?? '';
                    final String busLabel = busName.contains(' - ') 
                        ? busName.split(' - ').first 
                        : 'Bus';
                    final String busNum = b['busNumber']?.toString() ?? 'N/A';
                    final String cleanPlate = (busNum.isNotEmpty && busNum != 'N/A') 
                        ? ' ($busNum)' 
                        : '';
                    
                    final String displayName = '$busLabel$cleanPlate';
                    final String routeInfo = b['routeName'] ?? 'Unknown Route';
                    final Color routeColor = b['routeColor'] != null
                        ? Color(int.parse(b['routeColor'].replaceAll('#', '0xFF')))
                        : Colors.blueAccent;
                    
                    final bool isCurrent = driver['assignedBus'] == b['_id'];
                    
                    return ListTile(
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await _apiService.put('manager/drivers/${driver['_id']}', {'assignedBus': b['_id']});
                          _loadData();
                        } catch (e) {
                          debugPrint('Error assigning bus: $e');
                        }
                      },
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isCurrent ? Colors.green : routeColor).withValues(alpha: 0.1), 
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: (isCurrent ? Colors.green : routeColor).withValues(alpha: 0.2))
                        ),
                        child: Icon(Icons.directions_bus_filled_rounded, color: isCurrent ? Colors.green : routeColor, size: 20),
                      ),
                      title: Text(
                        displayName.toUpperCase(), 
                        style: GoogleFonts.plusJakartaSans(
                          color: isCurrent ? Colors.green : Colors.white, 
                          fontWeight: FontWeight.w900, 
                          fontSize: 14, 
                          letterSpacing: 1
                        )
                      ),
                      subtitle: Text(
                        routeInfo, 
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38, 
                          fontSize: 10, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                      trailing: isCurrent 
                          ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20)
                          : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 16),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
      ),
    );
  }

  void _showBusDriverAssignmentDialog(Bus bus) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('DRIVER REASSIGNMENT', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 4),
              Text('UNIT: UNIT_${bus.id.substring(bus.id.length - 4).toUpperCase()} (${bus.routeName.toUpperCase()})', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 24),
              
              // Unassign current driver Option
              _buildDialogOption('NO DRIVER / UNASSIGNED', Icons.person_off_rounded, Colors.redAccent, () async {
                try {
                  // Find driver currently assigned to this bus and clear their assignment
                  final currentDriver = _drivers.firstWhere(
                    (d) => d['assignedBus'] == bus.id,
                    orElse: () => null
                  );
                  if (currentDriver != null) {
                    await _apiService.put('manager/drivers/${currentDriver['_id']}', {'assignedBus': ''});
                  }
                  _loadData();
                } catch (e) {
                  debugPrint('Error clearing driver assignment: $e');
                }
              }),
              const Divider(color: Colors.white10, height: 16),
              
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _drivers.length,
                  itemBuilder: (context, index) {
                    final d = _drivers[index];
                    final String name = (d['name'] ?? d['username'] ?? 'Unknown').toString().toUpperCase();
                    final String contact = d['contactNumber'] ?? 'NO CONTACT';
                    final bool isActive = d['status'] != 'Suspended';
                    final bool isCurrent = d['assignedBus'] == bus.id;
                    
                    return ListTile(
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await _apiService.put('manager/drivers/${d['_id']}', {'assignedBus': bus.id});
                          _loadData();
                        } catch (e) {
                          debugPrint('Error assigning driver: $e');
                        }
                      },
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isCurrent ? Colors.green : (isActive ? Colors.blueAccent : Colors.redAccent)).withValues(alpha: 0.1), 
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: (isCurrent ? Colors.green : (isActive ? Colors.blueAccent : Colors.redAccent)).withValues(alpha: 0.2))
                        ),
                        child: Icon(Icons.shield_rounded, color: isCurrent ? Colors.green : (isActive ? Colors.blueAccent : Colors.redAccent), size: 20),
                      ),
                      title: Text(
                        name, 
                        style: GoogleFonts.plusJakartaSans(
                          color: isCurrent ? Colors.green : Colors.white, 
                          fontWeight: FontWeight.w900, 
                          fontSize: 14, 
                          letterSpacing: 1
                        )
                      ),
                      subtitle: Text(
                        'CONTACT: $contact', 
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38, 
                          fontSize: 10, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                      trailing: isCurrent 
                          ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20)
                          : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 16),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
      ),
    );
  }

  Widget _buildDialogOption(String title, IconData icon, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2))
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white10, size: 16),
    );
  }

  Future<void> _updateBus(Bus bus, {String? status, String? routeId, String? routeName, String? routeColor}) async {
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

  // ─────────────────────────────────────────────────────────────────────────
  // ROUTES TAB
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRoutesTab() {
    if (_routes.isEmpty) return _buildEmptyState('No routes configured', Icons.route_rounded);
    return RefreshIndicator(
      onRefresh: _loadData,
      backgroundColor: const Color(0xFF0D0B14),
      color: Colors.deepPurpleAccent,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: _routes.length,
        itemBuilder: (context, index) {
          final route = _routes[index];
          Color routeColor;
          try {
            routeColor = Color(int.parse(route.color.replaceAll('#', '0xFF')));
          } catch (_) {
            routeColor = Colors.deepPurpleAccent;
          }
          return _buildGlassCard(
            index: index,
            child: Row(
              children: [
                Container(
                  height: 48, width: 6,
                  decoration: BoxDecoration(
                    color: routeColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: routeColor.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.name,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${route.stops.length} stops',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _buildActionButton(Icons.edit_rounded, () => _showRouteEditSheet(route)),
              ],
            ),
          ).animate().fadeIn(delay: (math.min(index, 6) * 30).ms).slideY(begin: 0.1);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ROUTE EDIT BOTTOM SHEET
  // ─────────────────────────────────────────────────────────────────────────
  void _showRouteEditSheet(RouteModel route) {
    final nameCtrl = TextEditingController(text: route.name);
    // Mutable stops list – copies the current stops
    final stops = route.stops
        .map((s) => {'name': s['name'] as String, 'lat': s['lat'].toString(), 'lng': s['lng'].toString()})
        .toList();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: const BoxDecoration(
              color: Color(0xFF0D0B14),
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('EDIT ROUTE', style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                        ),
                        child: Text('${stops.length} STOPS',
                            style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      // Route Name Field
                      Text('ROUTE NAME', style: GoogleFonts.plusJakartaSans(
                          color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                        ),
                        child: TextField(
                          controller: nameCtrl,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            hintText: 'e.g. Gandinagar Route',
                            hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Stops Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('STOPS', style: GoogleFonts.plusJakartaSans(
                              color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                          GestureDetector(
                            onTap: () {
                              setSheetState(() => stops.add({'name': '', 'lat': '0', 'lng': '0'}));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.add_rounded, color: Colors.blueAccent, size: 14),
                                const SizedBox(width: 4),
                                Text('ADD STOP', style: GoogleFonts.plusJakartaSans(
                                    color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...stops.asMap().entries.map((entry) {
                        final i = entry.key;
                        final stop = entry.value;
                        final ctrl = TextEditingController(text: stop['name']);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                                ),
                                child: Center(
                                  child: Text('${i + 1}', style: GoogleFonts.plusJakartaSans(
                                      color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w900)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: ctrl,
                                  onChanged: (v) => stops[i]['name'] = v,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Stop name…',
                                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setSheetState(() => stops.removeAt(i)),
                                child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                // Save Button
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 16),
                  child: GestureDetector(
                    onTap: isSaving ? null : () async {
                      setSheetState(() => isSaving = true);
                      try {
                        await _apiService.put(
                          'manager/routes/${route.id}',
                          {
                            'name': nameCtrl.text.trim(),
                            'stops': stops
                                .where((s) => s['name']!.isNotEmpty)
                                .map((s) => {
                                      'name': s['name'],
                                      'lat': double.tryParse(s['lat']!) ?? 0.0,
                                      'lng': double.tryParse(s['lng']!) ?? 0.0,
                                    })
                                .toList(),
                          },
                        );
                        if (!mounted || !ctx.mounted || !context.mounted) return;
                        Navigator.pop(ctx);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Route updated!',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900)),
                          backgroundColor: Colors.blueAccent,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ));
                      } catch (e) {
                        setSheetState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Save failed: $e'),
                            backgroundColor: Colors.redAccent,
                          ));
                        }
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 60,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSaving
                              ? [Colors.deepPurpleAccent.withValues(alpha: 0.4), Colors.blueAccent.withValues(alpha: 0.4)]
                              : [Colors.deepPurpleAccent, Colors.blueAccent],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.deepPurpleAccent.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: Center(
                        child: isSaving
                            ? const SizedBox(width: 24, height: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('SAVE CHANGES', style: GoogleFonts.plusJakartaSans(
                                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // IN-APP BUS REPORT BOTTOM SHEET
  // ─────────────────────────────────────────────────────────────────────────
  void _showBusReportSheet(Bus bus) async {
    // Show loading sheet immediately
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BusReportSheet(bus: bus, apiService: _apiService, onDownload: () => _downloadReport(busId: bus.id)),
    );
  }
}


// ---------------------------------------------------------------------------
// SEPARATE STATEFUL WIDGET: In-App Bus Daily Report Sheet
// ---------------------------------------------------------------------------
class _BusReportSheet extends StatefulWidget {
  final Bus bus;
  final ApiService apiService;
  final VoidCallback onDownload;

  const _BusReportSheet({required this.bus, required this.apiService, required this.onDownload});

  @override
  State<_BusReportSheet> createState() => _BusReportSheetState();
}

class _BusReportSheetState extends State<_BusReportSheet> {
  bool _loading = true;
  Map<String, dynamic>? _report;
  String? _error;
  final Set<int> _expandedDays = {};
  String _filterTripType = 'all'; // 'all', 'pickup', 'dropoff'

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      final data = await widget.apiService.get('manager/reports/bus/${widget.bus.id}/summary');
      if (mounted) setState(() { _report = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0B14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('BUS OPERATIONS LOG',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    Text(widget.bus.routeName,
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                  ]),
                ),
                GestureDetector(
                  onTap: () { Navigator.pop(context); widget.onDownload(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.download_rounded, color: Colors.blueAccent, size: 16),
                      const SizedBox(width: 6),
                      Text('EXPORT REPORT',
                          style: GoogleFonts.plusJakartaSans(
                              color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2))
                  : _error != null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 12),
                            Text('Failed to load report',
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
                          ]),
                        )
                      : _buildReportContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent() {
    final busInfo      = _report!['bus']           as Map<String, dynamic>;
    final routeInfo    = _report!['route']         as Map<String, dynamic>?;
    final summary      = _report!['summary']       as Map<String, dynamic>;
    final dailyRecords = (_report!['dailyRecords'] as List<dynamic>?) ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        // Bus Identity Card
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
          ),
          child: Column(children: [
            _infoRow(Icons.directions_bus_rounded, 'Bus Number',
                busInfo['busNumber']?.toString() ?? 'N/A', Colors.blueAccent),
            const Divider(color: Colors.white10, height: 20),
            _infoRow(Icons.person_rounded, 'Driver',
                busInfo['driverName']?.toString() ?? 'N/A', Colors.deepPurpleAccent),
            const Divider(color: Colors.white10, height: 20),
            _infoRow(Icons.alt_route_rounded, 'Route',
                busInfo['routeName']?.toString() ?? 'N/A', Colors.orangeAccent),
            if (routeInfo != null) ...[
              const Divider(color: Colors.white10, height: 20),
              _infoRow(Icons.trip_origin_rounded, 'Origin Stop',
                  routeInfo['originStop']?.toString() ?? 'N/A', Colors.greenAccent),
              const Divider(color: Colors.white10, height: 20),
              _infoRow(Icons.school_rounded, 'Campus Stop',
                  routeInfo['campusStop']?.toString() ?? 'Campus', Colors.cyanAccent),
              const Divider(color: Colors.white10, height: 20),
              _infoRow(Icons.place_rounded, 'Total Stops',
                  '${routeInfo['totalStops']} stops', Colors.white54),
            ],
          ]),
        ),

        // KPI Grid
        Text('30-DAY SUMMARY',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.32,
          children: [
            _kpiCard('OPERATING\nDAYS',
                '${summary['totalOperatingDays']}', Icons.calendar_month_rounded, Colors.blueAccent),
            _kpiCard('ON-TIME\nPERCENT',
                '${summary['onTimePercent']}%', Icons.check_circle_rounded, Colors.greenAccent),
            _kpiCard('AVG SPEED',
                '${summary['avgSpeedKmh']} KM/H', Icons.speed_rounded, Colors.orangeAccent),
            _kpiCard('AVG STUDENTS\n/DAY',
                '${summary['avgStudentsPerDay']}', Icons.people_rounded, Colors.deepPurpleAccent),
            _kpiCard('TOTAL STUDENTS\nSERVED',
                '${summary['totalStudentsServed']}', Icons.school_rounded, Colors.cyanAccent),
            _kpiCard('DELAYED\nDAYS',
                '${summary['delayedDays']}', Icons.warning_rounded, Colors.redAccent),
          ],
        ),
        const SizedBox(height: 28),

        // Trip Type Filter Segmented Bar
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('DAILY OPERATIONS LOG',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
          Text('${dailyRecords.length} DAYS LOGGED',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF161421),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              _buildFilterBtn('all', 'ALL TRIPS', icon: Icons.clear_all_rounded),
              _buildFilterBtn('pickup', 'PICKUP', icon: Icons.wb_sunny_rounded),
              _buildFilterBtn('dropoff', 'DROP-OFF', icon: Icons.nights_stay_rounded),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Daily Records
        ...dailyRecords.asMap().entries.map((entry) {
          final idx      = entry.key;
          final record   = entry.value as Map<String, dynamic>;
          final pickup   = record['pickupTrip'] as Map<String, dynamic>?;
          final dropoff  = record['dropoffTrip'] as Map<String, dynamic>?;
          final expanded = _expandedDays.contains(idx);

          final showPickup  = _filterTripType == 'all' || _filterTripType == 'pickup';
          final showDropoff = _filterTripType == 'all' || _filterTripType == 'dropoff';

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              // Date Header Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          record['dayName']?.toString().toUpperCase() ?? 'DAY',
                          style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        record['date']?.toString() ?? '',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ]),
                    GestureDetector(
                      onTap: () => setState(() {
                        if (expanded) {
                          _expandedDays.remove(idx);
                        } else {
                          _expandedDays.add(idx);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
                        child: Icon(
                          expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Trip 1: Morning Pickup Card
              if (showPickup && pickup != null)
                _buildTripDetailCard(
                  trip: pickup,
                  color: Colors.blueAccent,
                  icon: Icons.wb_sunny_rounded,
                  expanded: expanded,
                ),

              if (showPickup && showDropoff && pickup != null && dropoff != null)
                const Divider(color: Colors.white10, height: 1),

              // Trip 2: Evening Dropoff Card
              if (showDropoff && dropoff != null)
                _buildTripDetailCard(
                  trip: dropoff,
                  color: Colors.orangeAccent,
                  icon: Icons.nights_stay_rounded,
                  expanded: expanded,
                ),
            ]),
          );
        }),
      ],
    );
  }

  Widget _buildFilterBtn(String key, String label, {IconData? icon}) {
    final isSelected = _filterTripType == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterTripType = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.deepPurpleAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: isSelected ? Colors.white : Colors.white38),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: isSelected ? Colors.white : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripDetailCard({
    required Map<String, dynamic> trip,
    required Color color,
    required IconData icon,
    required bool expanded,
  }) {
    final isOnTime = trip['status'] == 'On-time';
    final timeline = (trip['stopTimeline'] as List<dynamic>?) ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip['label']?.toString().toUpperCase() ?? 'TRIP LOG',
                  style: GoogleFonts.plusJakartaSans(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isOnTime ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (isOnTime ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: 0.3)),
                ),
                child: Text(
                  isOnTime ? 'ON-TIME' : 'DELAYED',
                  style: GoogleFonts.plusJakartaSans(
                    color: isOnTime ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${trip['departureTime']} ➔ ${trip['arrivalTime']}',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${trip['tripDurationMins']} MINS',
                style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${trip['originStop']} ➔ ${trip['destinationStop']}',
            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _statChip(Icons.people_rounded, '${trip['studentCount']} commuters'),
              _statChip(Icons.speed_rounded, '${trip['avgSpeedKmh']} km/h avg'),
              _statChip(Icons.place_rounded, '${timeline.length} stops'),
            ],
          ),
          if (expanded && timeline.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 10),
            Text(
              'STOP-BY-STOP TIMELINE (${trip['type'] == 'dropoff' ? 'REVERSE DROP-OFF' : 'PICKUP'})',
              style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            ...timeline.asMap().entries.map((stopEntry) {
              final stop = stopEntry.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              stop['stopName']?.toString() ?? '',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stop['time']?.toString() ?? '',
                      style: GoogleFonts.plusJakartaSans(color: color, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: Colors.white24),
      const SizedBox(width: 3),
      Text(text, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9.5)),
    ]);
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 15),
      ),
      const SizedBox(width: 12),
      Text(label,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700)),
      const Spacer(),
      Flexible(
        child: Text(value,
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double pad = constraints.maxHeight < 90 ? 10.0 : 12.0;
        final double iconSize = constraints.maxHeight < 90 ? 14.0 : 16.0;
        final double valFontSize = constraints.maxHeight < 90 ? 16.0 : 20.0;
        return Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: valFontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white38,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }
    );
  }
}

class _UserDetailsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<RouteModel> routes;
  final ApiService apiService;
  final VoidCallback onDataChanged;
  final Function(Map<String, dynamic>) onRouteSelect;
  final Function(String) onDeleteUser;

  const _UserDetailsBottomSheet({
    required this.user,
    required this.routes,
    required this.apiService,
    required this.onDataChanged,
    required this.onRouteSelect,
    required this.onDeleteUser,
  });

  @override
  State<_UserDetailsBottomSheet> createState() => _UserDetailsBottomSheetState();
}

class _UserDetailsBottomSheetState extends State<_UserDetailsBottomSheet> {
  late bool isEditing;
  late bool isUpdating;
  late Map<String, dynamic> user;

  late TextEditingController nameCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController courseCtrl;
  late TextEditingController pickupCtrl;
  late TextEditingController fatherNameCtrl;
  late TextEditingController fatherPhoneCtrl;
  late TextEditingController genderCtrl;

  @override
  void initState() {
    super.initState();
    isEditing = false;
    isUpdating = false;
    user = Map<String, dynamic>.from(widget.user);

    nameCtrl = TextEditingController(text: user['name'] ?? user['username'] ?? '');
    emailCtrl = TextEditingController(text: user['email'] ?? '');
    phoneCtrl = TextEditingController(text: user['phone'] ?? '');
    courseCtrl = TextEditingController(text: user['courseName'] ?? '');
    pickupCtrl = TextEditingController(text: user['pickupPoint'] ?? '');
    fatherNameCtrl = TextEditingController(text: user['fatherName'] ?? '');
    fatherPhoneCtrl = TextEditingController(text: user['fatherPhone'] ?? '');
    genderCtrl = TextEditingController(text: user['gender'] ?? '');
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    courseCtrl.dispose();
    pickupCtrl.dispose();
    fatherNameCtrl.dispose();
    fatherPhoneCtrl.dispose();
    genderCtrl.dispose();
    super.dispose();
  }

  Widget buildInfoRow(String label, String value, IconData icon, {Widget? editField}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 2),
                isEditing && editField != null
                    ? editField
                    : Text(value.isEmpty ? 'N/A' : value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEditableTextField(TextEditingController ctrl, String hint) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: ctrl,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = user['status'] ?? 'Active';
    final isActive = status.toLowerCase() == 'active';
    final statusColor = isActive ? const Color(0xFF38EF7D) : Colors.orangeAccent;
    
    final routeId = user['routeId'];
    RouteModel? matchedRoute;
    if (routeId != null) {
      try {
        matchedRoute = widget.routes.firstWhere((r) => r.id == routeId);
      } catch (_) {}
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0B14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.2)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: Column(
              children: [
                // Drag Handle
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                
                // Header info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: statusColor.withValues(alpha: 0.1),
                        child: Icon(Icons.person_rounded, color: statusColor, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            isEditing
                                ? buildEditableTextField(nameCtrl, 'Full Name')
                                : Text(
                                    user['name'] ?? user['username'] ?? 'Unknown',
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                            const SizedBox(height: 4),
                            Text(
                              'UID: ${user['userId'] ?? user['username'] ?? 'N/A'}',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(color: Colors.white10, height: 1),
                
                // Main info scrollable area
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    children: [
                      // Personal Info Section
                      Text('ACADEMIC & PERSONAL', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      buildInfoRow('Course / Semester', user['courseName'] ?? '', Icons.school_outlined, editField: buildEditableTextField(courseCtrl, 'Course name')),
                      buildInfoRow('Gender', user['gender'] ?? '', Icons.wc_outlined, editField: buildEditableTextField(genderCtrl, 'Gender')),
                      const SizedBox(height: 24),

                      // Contact Section
                      Text('CONTACT INFORMATION', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      buildInfoRow('Email Address', user['email'] ?? '', Icons.alternate_email_rounded, editField: buildEditableTextField(emailCtrl, 'Email Address')),
                      buildInfoRow('Phone Number', user['phone'] ?? '', Icons.phone_android_rounded, editField: buildEditableTextField(phoneCtrl, 'Phone Number')),
                      const SizedBox(height: 24),

                      // Family Info
                      Text('FAMILY CONTACTS', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      buildInfoRow('Father\'s Name', user['fatherName'] ?? '', Icons.person_outline_rounded, editField: buildEditableTextField(fatherNameCtrl, 'Father\'s Name')),
                      buildInfoRow('Father\'s Phone', user['fatherPhone'] ?? '', Icons.phone_callback_rounded, editField: buildEditableTextField(fatherPhoneCtrl, 'Father\'s Phone')),
                      const SizedBox(height: 24),

                      // Transit Section
                      Text('TRANSPORT STATUS', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      buildInfoRow('Pickup Point', user['pickupPoint'] ?? '', Icons.location_on_outlined, editField: buildEditableTextField(pickupCtrl, 'Pickup Point')),
                      
                      // Route Info Row (Custom since it has button)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.route_outlined, color: Colors.white38, size: 16),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Assigned Route'.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                  const SizedBox(height: 4),
                                  if (matchedRoute != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF'))).withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        matchedRoute.name.toUpperCase(),
                                        style: GoogleFonts.plusJakartaSans(color: Color(int.parse(matchedRoute.color.replaceAll('#', '0xFF'))), fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  else
                                    Text('No Route Assigned', style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 12)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context); // Close details sheet first
                                widget.onRouteSelect(user); // Open route dialog
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                                foregroundColor: Colors.blueAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              child: Text('CHANGE', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Divider(color: Colors.white10, height: 1),
                
                // Actions bar at the bottom
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        // Suspend/Activate Toggle Button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isUpdating ? null : () async {
                              setState(() => isUpdating = true);
                              try {
                                final newStatus = isActive ? 'Suspended' : 'Active';
                                await widget.apiService.put('manager/users/${user['_id']}', {'status': newStatus});
                                if (mounted) {
                                  setState(() {
                                    user['status'] = newStatus;
                                    isUpdating = false;
                                  });
                                  widget.onDataChanged();
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => isUpdating = false);
                                }
                                debugPrint('Status update failed: $e');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isActive ? Colors.orangeAccent.withValues(alpha: 0.1) : const Color(0xFF38EF7D).withValues(alpha: 0.1),
                              foregroundColor: isActive ? Colors.orangeAccent : const Color(0xFF38EF7D),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: isUpdating 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(
                                    isActive ? 'SUSPEND ACCOUNT' : 'ACTIVATE ACCOUNT',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        
                        // Edit/Save Button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isUpdating ? null : () async {
                              if (isEditing) {
                                // Save mode
                                setState(() => isUpdating = true);
                                try {
                                  final body = {
                                    'name': nameCtrl.text.trim(),
                                    'email': emailCtrl.text.trim(),
                                    'phone': phoneCtrl.text.trim(),
                                    'courseName': courseCtrl.text.trim(),
                                    'pickupPoint': pickupCtrl.text.trim(),
                                    'fatherName': fatherNameCtrl.text.trim(),
                                    'fatherPhone': fatherPhoneCtrl.text.trim(),
                                    'gender': genderCtrl.text.trim(),
                                  };
                                  await widget.apiService.put('manager/users/${user['_id']}', body);
                                  if (mounted) {
                                    setState(() {
                                      user['name'] = body['name'];
                                      user['email'] = body['email'];
                                      user['phone'] = body['phone'];
                                      user['courseName'] = body['courseName'];
                                      user['pickupPoint'] = body['pickupPoint'];
                                      user['fatherName'] = body['fatherName'];
                                      user['fatherPhone'] = body['fatherPhone'];
                                      user['gender'] = body['gender'];
                                      isEditing = false;
                                      isUpdating = false;
                                    });
                                    widget.onDataChanged();
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => isUpdating = false);
                                  }
                                  debugPrint('User details update failed: $e');
                                }
                              } else {
                                // Toggle Edit
                                setState(() {
                                  isEditing = true;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isEditing ? const Color(0xFF38EF7D) : Colors.white.withValues(alpha: 0.05),
                              foregroundColor: isEditing ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: isUpdating 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(
                                    isEditing ? 'SAVE DETAILS' : 'EDIT DETAILS',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        
                        // Delete Account Button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E1E1E),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  title: Text('Delete Account?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                  content: Text('Are you sure you want to permanently delete this user account? Their associated registration submission will revert to pending status.', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx); // Close dialog
                                        widget.onDeleteUser(user['_id']);
                                      },
                                      child: Text('DELETE', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                            },
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
      },
    );
  }
}
