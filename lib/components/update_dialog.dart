import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../constants/constants.dart';
import '../theme/app_theme.dart';

/// Tracks whether update dialog was already shown this session to prevent repetitive interruptions
bool _hasCheckedUpdateThisSession = false;

/// Checks for app updates against the backend API and presents the update modal if available.
Future<void> checkForAppUpdate(BuildContext context, {bool forceCheck = false, bool showToastIfLatest = false}) async {
  if (_hasCheckedUpdateThisSession && !forceCheck) return;
  _hasCheckedUpdateThisSession = true;

  try {
    final response = await http.get(
      Uri.parse('${AppConstants.apiUrl}/app-version'),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final int latestBuild = data['latestBuildNumber'] ?? AppConstants.currentBuildNumber;
      final String latestVersion = data['latestVersion'] ?? AppConstants.currentAppVersion;
      final List<dynamic> releaseNotes = data['releaseNotes'] ?? [];
      final String playStoreUrl = data['playStoreUrl'] ?? AppConstants.playStoreUrl;
      final bool isForceUpdate = data['isForceUpdate'] ?? false;

      if (latestBuild > AppConstants.currentBuildNumber) {
        if (!context.mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          isDismissible: !isForceUpdate,
          enableDrag: !isForceUpdate,
          backgroundColor: Colors.transparent,
          builder: (ctx) => AppUpdateSheet(
            latestVersion: latestVersion,
            releaseNotes: releaseNotes.map((e) => e.toString()).toList(),
            playStoreUrl: playStoreUrl,
            isForceUpdate: isForceUpdate,
          ),
        );
      } else if (showToastIfLatest) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Text(
                  'SISTec Chalo is up to date (v${AppConstants.currentAppVersion})',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('App update check error: $e');
  }
}

class AppUpdateSheet extends StatelessWidget {
  final String latestVersion;
  final List<String> releaseNotes;
  final String playStoreUrl;
  final bool isForceUpdate;

  const AppUpdateSheet({
    super.key,
    required this.latestVersion,
    required this.releaseNotes,
    required this.playStoreUrl,
    this.isForceUpdate = false,
  });

  Future<void> _openPlayStore() async {
    final Uri marketUri = Uri.parse('market://details?id=com.smartcampus.shuttle');
    final Uri webUri = Uri.parse(playStoreUrl);

    try {
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching Play Store URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header Icon & Title
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Update Available',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'v$latestVersion',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF38BDF8),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'A new version of SISTec Chalo is ready on Play Store.',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // What's New Box
          if (releaseNotes.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "WHAT'S NEW",
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...releaseNotes.map((note) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Action Buttons
          Row(
            children: [
              if (!isForceUpdate) ...[
                Expanded(
                  flex: 2,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'LATER',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white54,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _openPlayStore();
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    'UPDATE NOW',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.1);
  }
}
