import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

/// Shows the Developer & Team Credits Modal Bottom Sheet with rich glassmorphic aesthetics.
void showDeveloperCreditsModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const DeveloperCreditsContent(),
  );
}

/// Shows the Developer & Team Credits as an AlertDialog.
void showDeveloperCreditsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: DeveloperCreditsContent(isDialog: true),
    ),
  );
}

class DeveloperCreditsContent extends StatelessWidget {
  final bool isDialog;
  const DeveloperCreditsContent({super.key, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!isDialog)
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

            // App Icon & Brand Badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: const Icon(
                Icons.directions_bus_rounded,
                color: AppColors.primaryLight,
                size: 26,
              ),
            ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),

            const SizedBox(height: 14),

            // App Name
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SISTec',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Chalo',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.primaryLight,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 4),

            Text(
              'Sagar Group of Institutions • Bhopal',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 18),

            // ── Primary Developer & Team Highlights Card ─────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  // Team Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          color: AppColors.primaryLight,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DEVELOPMENT TEAM',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textMuted,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'Team Rafftar',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppColors.accentGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          'CORE',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.accentGreen,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
                  ),

                  // Lead Developer
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.warning,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROJECT LEAD & ARCHITECT',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textMuted,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'Denim Hajare',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          'LEAD',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.warning,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 150.ms),

            const SizedBox(height: 14),

            // ── Features Grid / Platform Specs ──────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  _buildSpecRow(
                    icon: Icons.electric_bolt_rounded,
                    iconColor: AppColors.accent,
                    label: 'Live Telemetry',
                    value: 'Real-Time Bus Tracking',
                  ),
                  const SizedBox(height: 8),
                  _buildSpecRow(
                    icon: Icons.notifications_active_rounded,
                    iconColor: AppColors.accentPurple,
                    label: 'Geofence Push',
                    value: 'Proximity Arrival Alerts',
                  ),
                  const SizedBox(height: 8),
                  _buildSpecRow(
                    icon: Icons.hub_rounded,
                    iconColor: AppColors.accentGreen,
                    label: 'Multi-Role Engine',
                    value: 'Student • Driver • Admin',
                  ),
                  const SizedBox(height: 8),
                  _buildSpecRow(
                    icon: Icons.terminal_rounded,
                    iconColor: AppColors.primaryLight,
                    label: 'Release Build',
                    value: 'v2.4.0 (Production)',
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 18),

            // Close Action
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'CLOSE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 15),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
