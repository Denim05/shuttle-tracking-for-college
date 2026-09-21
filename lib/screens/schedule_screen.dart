import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';

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
      final data = await _api.get('schedule?routeId=${widget.route.id}');
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
    if (entry.isEmpty) return _defaultTimes;
    final times = entry.first['times'];
    if (times == null || (times as List).isEmpty) return _defaultTimes;
    return List<String>.from(times);
  }

  Color _timeColor(String t) {
    final h = int.tryParse(t.split(':').first) ?? 12;
    if (h < 12) return AppColors.warning;
    if (h < 17) return AppColors.primaryLight;
    return AppColors.accentPurple;
  }

  String _period(String t) {
    final h = int.tryParse(t.split(':').first) ?? 12;
    if (h < 12) return 'Morning Slot';
    if (h < 17) return 'Afternoon Slot';
    return 'Evening Slot';
  }

  IconData _periodIcon(String t) {
    final h = int.tryParse(t.split(':').first) ?? 12;
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
                    final stop = widget.route.stops[i];
                    final stopName = stop['name'] as String? ?? 'Stop ${i + 1}';
                    final times = _timesForStop(stopName);
                    return _buildStopCard(stopName, times, i)
                        .animate()
                        .fadeIn(delay: (i * 35).ms)
                        .slideY(begin: 0.04, duration: 250.ms);
                  },
                  childCount: widget.route.stops.length,
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                  _pill('CAMPUS DESTINATION', AppColors.accentGreen),
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

