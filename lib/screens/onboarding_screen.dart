import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  const OnboardingScreen({super.key, required this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingItem> _pages = const [
    _OnboardingItem(
      badge: 'LIVE FLEET TELEMETRY',
      title: 'Track Your Campus\nShuttle Live',
      description:
          'Monitor your college bus in real-time with road-snapped GPS coordinates, live speedometer telemetry, and estimated arrival times.',
      icon: Icons.directions_bus_filled_rounded,
      accentColor: Color(0xFF2563EB),
      secondaryColor: Color(0xFF00E5FF),
      chip1Text: '38 km/h Live Speed',
      chip1Icon: Icons.speed_rounded,
      chip2Text: '3 min to Next Stop',
      chip2Icon: Icons.timer_outlined,
      statusPill: 'LIVE GPS TELEMETRY',
      featureTags: ['Road-Snapped GPS', 'Sub-Second Sync', 'Live Speedometer'],
      previewType: _PreviewCardType.telemetryHud,
    ),
    _OnboardingItem(
      badge: 'PROXIMITY GEOFENCING',
      title: 'Never Miss Your\nMorning Pickup',
      description:
          'Receive instant smart notifications on your lockscreen when your bus crosses the 500m perimeter around your assigned stop.',
      icon: Icons.notifications_active_rounded,
      accentColor: Color(0xFF10B981),
      secondaryColor: Color(0xFF34D399),
      chip1Text: '500m Proximity Radius',
      chip1Icon: Icons.radar_rounded,
      chip2Text: 'Lalghati Stop Active',
      chip2Icon: Icons.location_on_rounded,
      statusPill: 'AUTO-GEOFENCE ACTIVE',
      featureTags: ['Lockscreen Alerts', '500m Perimeter', 'Pickup Countdown'],
      previewType: _PreviewCardType.alertBanner,
    ),
    _OnboardingItem(
      badge: 'OFFLINE ROUTE DIRECTORY',
      title: 'Explore Routes &\nOffline Timetables',
      description:
          'Access complete schedules across all 24 college bus routes with turn-by-turn stop rosters, fully cached for zero-data offline use.',
      icon: Icons.alt_route_rounded,
      accentColor: Color(0xFFF59E0B),
      secondaryColor: Color(0xFFFCD34D),
      chip1Text: '24 Campus Routes',
      chip1Icon: Icons.alt_route_rounded,
      chip2Text: 'Offline Schedule Cache',
      chip2Icon: Icons.cloud_done_rounded,
      statusPill: 'ROUTE NETWORK READY',
      featureTags: ['All 24 Routes', 'Offline Cache', 'Shift Timetables'],
      previewType: _PreviewCardType.routeTimeline,
    ),
    _OnboardingItem(
      badge: 'SAFETY & DRIVER ASSIST',
      title: 'Verified Drivers &\nEmergency Safety',
      description:
          'Direct hotline to verified campus drivers, crowd density indicators, and 1-tap emergency SOS security dispatch.',
      icon: Icons.shield_rounded,
      accentColor: Color(0xFF8B5CF6),
      secondaryColor: Color(0xFFA78BFA),
      chip1Text: '1-Tap Emergency SOS',
      chip1Icon: Icons.emergency_rounded,
      chip2Text: 'Verified Driver Fleet',
      chip2Icon: Icons.verified_user_rounded,
      statusPill: 'CAMPUS TRANSIT SHIELD',
      featureTags: ['1-Tap SOS Dispatch', 'Verified Drivers', 'Warden Assistance'],
      previewType: _PreviewCardType.safetyShield,
    ),
  ];

  Future<void> _completeOnboarding() async {
    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_completed_onboarding', true);
    } catch (e) {
      debugPrint('Error saving onboarding flag: $e');
    }
    widget.onCompleted();
  }

  Future<void> _requestInitialPermissions() async {
    HapticFeedback.mediumImpact();
    await [
      Permission.location,
      Permission.notification,
    ].request();
    _completeOnboarding();
  }

  void _goToPreviousPage() {
    if (_currentPage > 0) {
      HapticFeedback.lightImpact();
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;
    final currentItem = _pages[_currentPage];

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: Stack(
        children: [
          // ── Ambient Radial Glow ──────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeInOutCubic,
            top: MediaQuery.of(context).size.height * 0.12,
            left: (MediaQuery.of(context).size.width / 2) - 180,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 550),
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    currentItem.accentColor.withValues(alpha: 0.28),
                    currentItem.secondaryColor.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.1, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Ambient Radar Concentric Ring Background ─────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _RadarBackgroundPainter(
                color: currentItem.accentColor.withValues(alpha: 0.04),
              ),
            ),
          ),

          // ── Main Layout SafeArea ─────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── Top Navigation Bar ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back Button or App Logo
                      Row(
                        children: [
                          if (_currentPage > 0)
                            GestureDetector(
                              onTap: _goToPreviousPage,
                              child: Container(
                                width: 38,
                                height: 38,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),

                          // App Branded Logo Container (Real Logo Image)
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: currentItem.accentColor.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: currentItem.accentColor.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/app_icon new.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [currentItem.accentColor, currentItem.secondaryColor],
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.directions_bus_rounded, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'SISTec ',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Chalo',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: currentItem.secondaryColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Frosted Glass "Skip" Pill
                      if (!isLastPage)
                        GestureDetector(
                          onTap: _completeOnboarding,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 1.0,
                                  ),
                                ),
                                child: Text(
                                  'Skip',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Swipeable Page Carousel ──────────────────────────────
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    itemBuilder: (context, index) {
                      final item = _pages[index];
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Multi-Layered Hero Interactive Visual Artwork ──
                            SizedBox(
                              width: double.infinity,
                              height: 236,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Concentric Radar Rings
                                  Container(
                                    width: 210,
                                    height: 210,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: item.accentColor.withValues(alpha: 0.15),
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 160,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: item.secondaryColor.withValues(alpha: 0.22),
                                        width: 1.4,
                                      ),
                                    ),
                                  ),

                                  // Central Feature Artwork Container
                                  _buildCenterVisual(item),

                                  // Floating Telemetry Glass Chip 1 (Top Left)
                                  Positioned(
                                    top: 10,
                                    left: 4,
                                    child: _buildFloatingGlassChip(
                                      icon: item.chip1Icon,
                                      label: item.chip1Text,
                                      accentColor: item.accentColor,
                                    ).animate().fadeIn(delay: 150.ms).slideX(begin: -0.1),
                                  ),

                                  // Floating Telemetry Glass Chip 2 (Bottom Right)
                                  Positioned(
                                    bottom: 10,
                                    right: 4,
                                    child: _buildFloatingGlassChip(
                                      icon: item.chip2Icon,
                                      label: item.chip2Text,
                                      accentColor: item.secondaryColor,
                                    ).animate().fadeIn(delay: 250.ms).slideX(begin: 0.1),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ── Category Badge ────────────────────────────
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: item.accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: item.accentColor.withValues(alpha: 0.35),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: item.secondaryColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: item.secondaryColor.withValues(alpha: 0.6),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    item.badge,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: item.secondaryColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ).animate().fadeIn(delay: 100.ms),

                            const SizedBox(height: 12),

                            // ── Headline Title ───────────────────────────
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Colors.white, Color(0xFFE2E8F0)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ).createShader(bounds),
                              child: Text(
                                item.title,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  height: 1.15,
                                  letterSpacing: -0.6,
                                ),
                              ),
                            ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.08),

                            const SizedBox(height: 12),

                            // ── Body Subtitle ────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                item.description,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 13,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ).animate().fadeIn(delay: 200.ms),

                            const SizedBox(height: 16),

                            // ── Feature Tags Showcase Pills ──────────────
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: item.featureTags.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 13,
                                        color: item.secondaryColor,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        tag,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ).animate().fadeIn(delay: 250.ms),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── Bottom Section: Page Indicators & Action Button ───────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  child: Column(
                    children: [
                      // Smooth Expanding Dot Indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pages.length, (i) {
                          final isSel = i == _currentPage;
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                i,
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeInOutCubic,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: isSel ? 32 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: isSel
                                    ? LinearGradient(
                                        colors: [
                                          currentItem.accentColor,
                                          currentItem.secondaryColor,
                                        ],
                                      )
                                    : null,
                                color: isSel ? null : Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: isSel
                                    ? [
                                        BoxShadow(
                                          color: currentItem.accentColor.withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ),

                      const SizedBox(height: 20),

                      // Flagship Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF1A52FF),
                                currentItem.accentColor,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: currentItem.accentColor.withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              if (isLastPage) {
                                _requestInitialPermissions();
                              } else {
                                HapticFeedback.lightImpact();
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeInOutCubic,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isLastPage ? 'Get Started & Grant Access' : 'Continue',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  isLastPage ? Icons.arrow_forward_rounded : Icons.arrow_forward_rounded,
                                  size: 19,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Multi-Type Center Visual Artwork ──────────────────────────────────────
  Widget _buildCenterVisual(_OnboardingItem item) {
    return Container(
      width: 114,
      height: 114,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            item.accentColor.withValues(alpha: 0.38),
            const Color(0xFF0F172A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: item.secondaryColor.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: item.accentColor.withValues(alpha: 0.45),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          item.icon,
          size: 52,
          color: Colors.white,
        ),
      ),
    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack);
  }

  Widget _buildFloatingGlassChip({
    required IconData icon,
    required String label,
    required Color accentColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.45),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PreviewCardType {
  telemetryHud,
  alertBanner,
  routeTimeline,
  safetyShield,
}

class _OnboardingItem {
  final String badge;
  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final Color secondaryColor;
  final String chip1Text;
  final IconData chip1Icon;
  final String chip2Text;
  final IconData chip2Icon;
  final String statusPill;
  final List<String> featureTags;
  final _PreviewCardType previewType;

  const _OnboardingItem({
    required this.badge,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.secondaryColor,
    required this.chip1Text,
    required this.chip1Icon,
    required this.chip2Text,
    required this.chip2Icon,
    required this.statusPill,
    required this.featureTags,
    required this.previewType,
  });
}

class _RadarBackgroundPainter extends CustomPainter {
  final Color color;
  _RadarBackgroundPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height * 0.36);
    canvas.drawCircle(center, 80, paint);
    canvas.drawCircle(center, 140, paint);
    canvas.drawCircle(center, 200, paint);
  }

  @override
  bool shouldRepaint(covariant _RadarBackgroundPainter oldDelegate) => oldDelegate.color != color;
}
