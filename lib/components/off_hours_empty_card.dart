import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/route_model.dart';
import '../screens/schedule_screen.dart';
import '../theme/app_theme.dart';

class OffHoursEmptyCard extends StatelessWidget {
  final RouteModel? selectedRoute;
  final VoidCallback onSelectRoute;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;
  final bool isCompact;
  final EdgeInsets? margin;

  const OffHoursEmptyCard({
    super.key,
    required this.selectedRoute,
    required this.onSelectRoute,
    this.onDismiss,
    this.onTap,
    this.isCompact = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bool isNight = now.hour >= 19 || now.hour < 6;
    final String timeContext = isNight
        ? 'Morning pickup roster resumes at 07:00 AM.'
        : 'Next scheduled college run will appear when the driver starts the trip.';

    if (isCompact) {
      return _buildCompactPill(context, isNight);
    }

    return _buildFullCard(context, isNight, timeContext);
  }

  /// Compact floating pill that never obscures or blocks gestures to the map
  Widget _buildCompactPill(BuildContext context, bool isNight) {
    return Semantics(
      label: 'Shuttles currently offline. Tap for timetable or route options.',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (onTap != null) {
            onTap!();
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ScheduleScreen(route: selectedRoute)),
            );
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status dot & Icon
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isNight ? Icons.nightlight_round_rounded : Icons.schedule_rounded,
                      color: AppColors.warning,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      isNight ? 'OFFLINE • RESUMES 07:00 AM' : 'SHUTTLES OFFLINE',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Timetable quick button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ScheduleScreen(route: selectedRoute)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 10, color: AppColors.primaryLight),
                          const SizedBox(width: 4),
                          Text(
                            'TIMETABLE',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primaryLight,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Optional dismiss button
                  if (onDismiss != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onDismiss!();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white70, size: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.2);
  }

  /// Full rich card embedded inside the draggable bottom sheet
  Widget _buildFullCard(BuildContext context, bool isNight, String timeContext) {
    return Semantics(
      label: 'No active buses on this route right now. $timeContext',
      child: Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    isNight ? Icons.nightlight_round_rounded : Icons.schedule_rounded,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'SHUTTLES CURRENTLY OFFLINE',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.warning,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        selectedRoute?.name ?? 'No Bus Broadcasting',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onDismiss!();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white60, size: 14),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              timeContext,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScheduleScreen(route: selectedRoute),
                        ),
                      );
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 13),
                    label: Text(
                      'View Timetable',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onSelectRoute();
                    },
                    icon: const Icon(Icons.alt_route_rounded, size: 13),
                    label: Text(
                      'Switch Route',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
