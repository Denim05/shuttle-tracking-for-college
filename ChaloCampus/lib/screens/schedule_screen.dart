import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';

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
    if (h < 12) return const Color(0xFFFFB347);  // morning
    if (h < 17) return Colors.blueAccent;  // afternoon
    return const Color(0xFFB721FF);               // evening
  }

  String _period(String t) {
    final h = int.tryParse(t.split(':').first) ?? 12;
    if (h < 12) return '🌅 Morning';
    if (h < 17) return '☀️ Afternoon';
    return '🌙 Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070E),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            backgroundColor: const Color(0xFF05070E),
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SCHEDULE',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.blueAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    widget.route.name,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFF2D5BFF))),
            )
          else if (_error != null && _schedules.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded, color: Colors.white24, size: 60),
                    const SizedBox(height: 16),
                    Text(
                      'USING DEFAULT SCHEDULE',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No custom schedule uploaded yet.\nShowing standard SGI bus timings.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final stop = widget.route.stops[i];
                    final stopName = stop['name'] as String? ?? 'Stop ${i + 1}';
                    final times = _timesForStop(stopName);
                    return _buildStopCard(stopName, times, i)
                        .animate()
                        .fadeIn(delay: (i * 50).ms)
                        .slideX(begin: 0.05, duration: 350.ms);
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: (isFirst
              ? Colors.blueAccent
              : isLast
                  ? Colors.redAccent
                  : Colors.white)
              .withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stop Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst
                        ? Colors.blueAccent
                        : isLast
                            ? Colors.redAccent
                            : const Color(0xFF2D5BFF),
                    boxShadow: [
                      BoxShadow(
                        color: (isFirst
                                ? Colors.blueAccent
                                : isLast
                                    ? Colors.redAccent
                                    : const Color(0xFF2D5BFF))
                            .withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    stopName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (isFirst)
                  _pill('ORIGIN', Colors.blueAccent)
                else if (isLast)
                  _pill('FINAL STOP', Colors.redAccent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white10, height: 1),
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
    return Tooltip(
      message: period,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(
          time,
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1,
        ),
      ),
    );
  }
}

