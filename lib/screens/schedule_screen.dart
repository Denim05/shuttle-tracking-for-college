import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';
import '../utils/timetable_resolver.dart';
import '../components/stop_feedback_sheet.dart';

class ScheduleScreen extends StatefulWidget {
  final RouteModel route;
  const ScheduleScreen({super.key, required this.route});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final ApiService _api = ApiService();
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
    _fetchSchedule();
  }

  Future<void> _fetchSchedule() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await _api.get('schedule?routeId=${widget.route.id}', useCache: true);
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

    final scheduled = TimetableResolver.getScheduledTimeForStop(widget.route.name, stopName);
    if (scheduled != null && scheduled.isNotEmpty) {
      return [scheduled, '04:30 PM'];
    }

    return _defaultTimes;
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
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
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 2),
                  Text(
                    widget.route.name,
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
          else if (_error != null && _schedules.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: const Icon(Icons.schedule_rounded, color: AppColors.textMuted, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'STANDARD SCHEDULE ACTIVE',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Showing standard campus departure timings.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i == 0) {
                      final shifts = TimetableResolver.getShiftsForRoute(widget.route.name);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...shifts.map((entry) => Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.bgSecondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
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
                                      Text(
                                        'Driver: ${entry.driverName} • Tel: ${entry.driverPhone}',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppColors.primaryLight,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
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
                          )),
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.support_agent_rounded, size: 20, color: AppColors.primaryLight),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TRANSPORT INCHARGE HELPLINE (RATIBAD)',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppColors.textMuted,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Vaibhav Pathak: 7024256904 • Ramswroop: 9669660990',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
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
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }

                    final stopIdx = i - 1;
                    final stop = widget.route.stops[stopIdx];
                    final stopName = stop['name'] as String? ?? 'Stop ${stopIdx + 1}';
                    final times = _timesForStop(stopName);
                    return _buildStopCard(stopName, times, stopIdx)
                        .animate()
                        .fadeIn(delay: (stopIdx * 25).ms)
                        .slideY(begin: 0.04, duration: 250.ms);
                  },
                  childCount: widget.route.stops.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStopCard(String stopName, List<String> times, int index) {
    final isFirst = index == 0;
    final isLast = index == widget.route.stops.length - 1;

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
                      final stopData = widget.route.stops[index];
                      final lat = (stopData['lat'] ?? 0.0).toDouble();
                      final lng = (stopData['lng'] ?? 0.0).toDouble();
                      StopFeedbackSheet.show(
                        context,
                        routeId: widget.route.id,
                        routeName: widget.route.name,
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
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          // Times Grid
          Padding(
            padding: const EdgeInsets.all(14),
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
}

