import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';
import '../utils/timetable_resolver.dart';
import '../components/stop_feedback_sheet.dart';

class ScheduleScreen extends StatefulWidget {
  final RouteModel? route;
  const ScheduleScreen({super.key, this.route});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final ApiService _api = ApiService();
  late RouteModel _activeRoute;
  List<Map<String, dynamic>> _schedules = [];
  bool _isLoading = true;
  String? _error;

  // Default schedule times if none from server — real SGI bus departure times
  static const List<String> _defaultTimes = [
    '07:00', '08:00', '09:00', '13:00', '17:00', '18:00',
  ];

  @override
  void initState() {
    super.initState();
    _activeRoute = widget.route ?? _getDefaultRoute();
    _fetchSchedule();
  }

  RouteModel _getDefaultRoute() {
    final firstEntry = TimetableResolver.masterFleet.first;
    return RouteModel(
      id: '01',
      name: 'Bus 01 - ${firstEntry.routeName}',
      color: '#2563EB',
      coordinates: const [],
      stops: firstEntry.scheduledStops.map((s) => {
        'name': s.stopName,
        'time': s.time,
        'lat': 23.180302,
        'lng': 77.302695,
      }).toList(),
    );
  }

  Future<void> _fetchSchedule() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await _api.get('schedule?routeId=${_activeRoute.id}', useCache: true);
      if (mounted) {
        setState(() {
          _schedules = List<Map<String, dynamic>>.from(data as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  void _switchRoute(TimetableRouteEntry entry) {
    setState(() {
      _activeRoute = RouteModel(
        id: entry.busNumber,
        name: 'Bus ${entry.busNumber} - ${entry.routeName}',
        color: '#2563EB',
        coordinates: const [],
        stops: entry.scheduledStops.map((s) => {
          'name': s.stopName,
          'time': s.time,
          'lat': 23.180302,
          'lng': 77.302695,
        }).toList(),
      );
    });
    _fetchSchedule();
  }

  List<Map<String, dynamic>> _getStopsList() {
    if (_activeRoute.stops.isNotEmpty) {
      return _activeRoute.stops;
    }
    final scheduled = TimetableResolver.getScheduledStopsForRoute(_activeRoute.name);
    if (scheduled.isNotEmpty) {
      return scheduled.map((s) => {
        'name': s.stopName,
        'time': s.time,
        'lat': 23.180302,
        'lng': 77.302695,
      }).toList();
    }
    return const [];
  }

  List<String> _timesForStop(String stopName) {
    final entry = _schedules.where(
      (s) => s['stopName'].toString().toLowerCase() == stopName.toLowerCase(),
    ).toList();
    if (entry.isNotEmpty) {
      final times = entry.first['times'];
      if (times != null && (times as List).isNotEmpty) {
        return List<String>.from(times);
      }
    }

    final scheduled = TimetableResolver.getScheduledTimeForStop(_activeRoute.name, stopName);
    if (scheduled != null && scheduled.isNotEmpty) {
      return [scheduled, '04:30 PM'];
    }

    return _defaultTimes;
  }

  Future<void> _makePhoneCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dialing $phone', style: GoogleFonts.plusJakartaSans()),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver Hotline: $phone', style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  int _parseHour(String t) {
    final clean = t.replaceAll(RegExp(r'[^0-9:]'), '');
    int h = int.tryParse(clean.split(':').first) ?? 12;
    if (t.toUpperCase().contains('PM') && h < 12) h += 12;
    if (t.toUpperCase().contains('AM') && h == 12) h = 0;
    return h;
  }

  Color _timeColor(String t) {
    final h = _parseHour(t);
    if (h < 12) return AppColors.warning;
    if (h < 17) return AppColors.primaryLight;
    return AppColors.accentPurple;
  }

  String _period(String t) {
    final h = _parseHour(t);
    if (h < 12) return 'Morning Roster (9:00 AM Shift)';
    if (h < 17) return 'Afternoon Return';
    return 'Evening Return';
  }

  IconData _periodIcon(String t) {
    final h = _parseHour(t);
    if (h < 12) return Icons.wb_sunny_rounded;
    if (h < 17) return Icons.light_mode_rounded;
    return Icons.nightlight_round;
  }

  @override
  Widget build(BuildContext context) {
    final stops = _getStopsList();
    final bool isOfflineFallback = _error != null || _schedules.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 124,
            backgroundColor: AppColors.bgSecondary,
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.alt_route_rounded, color: Colors.cyanAccent),
                tooltip: 'Select Route',
                onPressed: () => _showRoutePickerSheet(context),
              ),
              IconButton(
                icon: const Icon(Icons.contact_phone_rounded, color: AppColors.primaryLight),
                tooltip: 'Emergency Driver Directory',
                onPressed: () => _showEmergencyDriverDirectory(context),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'SHUTTLE TIMETABLE',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.primaryLight,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isOfflineFallback)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OFFLINE ROSTER',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.cyanAccent,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _activeRoute.name,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i == 0) {
                      return _buildScheduleHeader(isOfflineFallback);
                    }

                    final stopIdx = i - 1;
                    if (stopIdx < 0 || stopIdx >= stops.length) return const SizedBox.shrink();
                    final stop = stops[stopIdx];
                    final stopName = stop['name'] as String? ?? 'Stop ${stopIdx + 1}';
                    final times = _timesForStop(stopName);
                    return _buildStopCard(stopName, times, stopIdx, stops.length)
                        .animate()
                        .fadeIn(delay: (stopIdx * 20).ms)
                        .slideY(begin: 0.04, duration: 220.ms);
                  },
                  childCount: stops.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScheduleHeader(bool isOfflineFallback) {
    final shifts = TimetableResolver.getShiftsForRoute(_activeRoute.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Offline status notice
        if (isOfflineFallback)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F2338),
                  Color(0xFF0D1826),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.offline_bolt_rounded, color: Colors.cyanAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OFFLINE TIMETABLE ACTIVE',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.cyanAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Showing verified institutional stop arrival times & direct driver hotline (works without internet).',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: -0.05),

        // Route Shifts & 1-Tap Driver Call Card
        ...shifts.map((entry) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46, height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          entry.busNumber.length > 8 && entry.busNumber.contains(' ')
                              ? entry.busNumber.split(' ').last
                              : entry.busNumber,
                          maxLines: 1,
                          textScaler: TextScaler.noScaling,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.primaryLight,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.displayBusLabel,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.shiftTag,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primaryLight,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Morning: ${entry.morningDeparture} ➔ ${entry.campusArrival} • Return: ${entry.returnDeparture}',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Registration: ${entry.vehicleNo}',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Tactile 1-Tap Driver Call Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, color: Colors.cyanAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.driverName,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            entry.driverPhone,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primaryLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 14),
                      label: Text(
                        '1-Tap Call',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: () => _makePhoneCall(entry.driverPhone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )),

        // Campus Emergency Driver Directory Quick Launch Banner
        GestureDetector(
          onTap: () => _showEmergencyDriverDirectory(context),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.primary.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.contact_phone_rounded, size: 18, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMERGENCY DRIVER DIRECTORY',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.primaryLight,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        'All 37 College Route Drivers & Hotlines (Offline)',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 20),
              ],
            ),
          ),
        ),

        // Transport Incharge Helpline Card with direct 1-tap call chips
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.support_agent_rounded, size: 18, color: AppColors.primaryLight),
                  const SizedBox(width: 8),
                  Text(
                    'TRANSPORT INCHARGE HELPLINE (RATIBAD)',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _makePhoneCall('7024256904'),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.phone_rounded, color: AppColors.accentGreen, size: 12),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Vaibhav: 7024256904',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => _makePhoneCall('9669660990'),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.phone_rounded, color: AppColors.accentGreen, size: 12),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Ramswroop: 9669660990',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ROUTE STOP TIMINGS',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              '${_getStopsList().length} STOPS SCHEDULED',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.primaryLight,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildStopCard(String stopName, List<String> times, int index, int totalStops) {
    final isFirst = index == 0;
    final isLast = index == totalStops - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stop Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst
                        ? AppColors.primary
                        : isLast
                            ? AppColors.accentGreen
                            : AppColors.surfaceLight,
                    border: Border.all(
                      color: isFirst
                          ? AppColors.primaryLight
                          : isLast
                              ? AppColors.accentGreen
                              : const Color(0xFF475569),
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stopName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (isFirst)
                  _pill('ORIGIN', AppColors.primaryLight)
                else if (isLast)
                  _pill('CAMPUS DESTINATION', AppColors.accentGreen)
                else
                  InkWell(
                    onTap: () {
                      final stops = _getStopsList();
                      final stopData = index < stops.length ? stops[index] : null;
                      final lat = (stopData?['lat'] ?? 0.0).toDouble();
                      final lng = (stopData?['lng'] ?? 0.0).toDouble();
                      StopFeedbackSheet.show(
                        context,
                        routeId: _activeRoute.id,
                        routeName: _activeRoute.name,
                        stopName: stopName,
                        currentLat: lat,
                        currentLng: lng,
                        onFeedbackSubmitted: _fetchSchedule,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_outlined, color: AppColors.primaryLight, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Verify',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primaryLight,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Times Grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: times.map((t) => _buildTimeChip(t)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String time) {
    final color = _timeColor(time);
    final period = _period(time);
    final icon = _periodIcon(time);
    return Tooltip(
      message: period,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              time,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showRoutePickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF141923),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.alt_route_rounded, color: Colors.cyanAccent),
                  const SizedBox(width: 10),
                  Text(
                    'Select Campus Route (Offline)',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: TimetableResolver.masterFleet.length,
                itemBuilder: (ctx, i) {
                  final item = TimetableResolver.masterFleet[i];
                  final isCurrent = _activeRoute.name.contains(item.routeName);
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: isCurrent ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Center(
                        child: Text(
                          item.busNumber,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      item.routeName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '${item.driverName} • ${item.morningDeparture}',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchRoute(item);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmergencyDriverDirectory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmergencyDriverDirectorySheet(onCall: _makePhoneCall),
    );
  }
}

class _EmergencyDriverDirectorySheet extends StatefulWidget {
  final Future<void> Function(String phone) onCall;

  const _EmergencyDriverDirectorySheet({required this.onCall});

  @override
  State<_EmergencyDriverDirectorySheet> createState() => _EmergencyDriverDirectorySheetState();
}

class _EmergencyDriverDirectorySheetState extends State<_EmergencyDriverDirectorySheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = TimetableResolver.masterFleet.where((entry) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return entry.busNumber.toLowerCase().contains(q) ||
          entry.routeName.toLowerCase().contains(q) ||
          entry.driverName.toLowerCase().contains(q) ||
          entry.driverPhone.contains(q) ||
          entry.vehicleNo.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF121722),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.contact_phone_rounded, color: AppColors.accentGreen, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMERGENCY DRIVER DIRECTORY',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.accentGreen,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Campus Fleet Roster (37 Drivers)',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '100% OFFLINE',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.cyanAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _query = val.trim()),
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search bus #, driver name, route, phone...',
                hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primaryLight),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final entry = filtered[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF192030),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                        ),
                        child: Center(
                          child: Text(
                            entry.busNumber,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primaryLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.driverName,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.routeName} • ${entry.vehicleNo}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Morning Departure: ${entry.morningDeparture}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.phone_rounded, color: Colors.white, size: 14),
                        label: Text(
                          'Call',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: () => widget.onCall(entry.driverPhone),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
