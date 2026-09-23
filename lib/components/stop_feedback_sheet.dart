import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../screens/map_picker_dialog.dart';

class StopFeedbackSheet extends StatefulWidget {
  final String routeId;
  final String routeName;
  final String stopName;
  final double currentLat;
  final double currentLng;
  final VoidCallback? onFeedbackSubmitted;

  const StopFeedbackSheet({
    super.key,
    required this.routeId,
    required this.routeName,
    required this.stopName,
    required this.currentLat,
    required this.currentLng,
    this.onFeedbackSubmitted,
  });

  static Future<void> show(
    BuildContext context, {
    required String routeId,
    required String routeName,
    required String stopName,
    required double currentLat,
    required double currentLng,
    VoidCallback? onFeedbackSubmitted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StopFeedbackSheet(
        routeId: routeId,
        routeName: routeName,
        stopName: stopName,
        currentLat: currentLat,
        currentLng: currentLng,
        onFeedbackSubmitted: onFeedbackSubmitted,
      ),
    );
  }

  @override
  State<StopFeedbackSheet> createState() => _StopFeedbackSheetState();
}

class _StopFeedbackSheetState extends State<StopFeedbackSheet> {
  final ApiService _apiService = ApiService();
  final TextEditingController _commentController = TextEditingController();
  
  bool _isSubmitting = false;
  bool _isCapturingGps = false;
  LatLng? _suggestedLocation;
  double? _gpsAccuracy;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // ─── 1-Tap Positive Confirmation (👍 "Accurate") ─────────────────────────
  Future<void> _confirmAccurate() async {
    setState(() => _isSubmitting = true);
    try {
      final res = await _apiService.post('routes/${widget.routeId}/stops/feedback', {
        'stopName': widget.stopName,
        'feedbackType': 'confirm_correct',
        'comment': _commentController.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      _showSuccessSnackBar(res?['message'] ?? 'Thank you! Your verification has been recorded.');
      widget.onFeedbackSubmitted?.call();
    } catch (e) {
      if (mounted) _showErrorSnackBar('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── 1-Tap Capture Live GPS on Site ──────────────────────────────────────
  Future<void> _captureOnSiteGps() async {
    setState(() => _isCapturingGps = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorSnackBar('Location permission is required.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showErrorSnackBar('Please grant Location permission in settings.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _suggestedLocation = LatLng(pos.latitude, pos.longitude);
        _gpsAccuracy = pos.accuracy;
      });

      _showSuccessSnackBar('GPS Captured (±${pos.accuracy.toStringAsFixed(1)}m)! Tap Submit to confirm.');
    } catch (e) {
      _showErrorSnackBar('Could not acquire GPS: $e');
    } finally {
      if (mounted) setState(() => _isCapturingGps = false);
    }
  }

  // ─── Adjust Pin on Map ──────────────────────────────────────────────────
  Future<void> _pickOnMap() async {
    final double initialLat = _suggestedLocation?.latitude ?? widget.currentLat;
    final double initialLng = _suggestedLocation?.longitude ?? widget.currentLng;

    final LatLng? picked = await showDialog<LatLng>(
      context: context,
      builder: (ctx) => MapPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        stopName: widget.stopName,
        themeColor: AppColors.primary,
      ),
    );

    if (picked != null) {
      setState(() {
        _suggestedLocation = picked;
        _gpsAccuracy = 5.0; // Manual precision tag
      });
      _showSuccessSnackBar('Location selected on map! Tap Submit to record suggestion.');
    }
  }

  // ─── Submit Coordinate Suggestion ───────────────────────────────────────
  Future<void> _submitSuggestion() async {
    if (_suggestedLocation == null) {
      _showErrorSnackBar('Please capture your GPS or pick a location on map first.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res = await _apiService.post('routes/${widget.routeId}/stops/feedback', {
        'stopName': widget.stopName,
        'feedbackType': 'suggest_location',
        'suggestedLat': _suggestedLocation!.latitude,
        'suggestedLng': _suggestedLocation!.longitude,
        'accuracy': _gpsAccuracy ?? 10.0,
        'comment': _commentController.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      _showSuccessSnackBar(res?['message'] ?? 'Suggestion submitted for community consensus!');
      widget.onFeedbackSubmitted?.call();
    } catch (e) {
      if (mounted) _showErrorSnackBar('Failed to submit suggestion: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF7F1D1D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasCustomPos = _suggestedLocation != null;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 30, spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMMUNITY STOP VERIFICATION',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      widget.stopName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
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

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Help fellow students & drivers by verifying if the bus stops exactly here.',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Option 1: 1-Tap Positive Vote ("Yes, it's accurate")
          if (!hasCustomPos) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.thumb_up_alt_rounded, size: 18),
                label: Text(
                  'Yes, Stop Location is Accurate',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                onPressed: _isSubmitting ? null : _confirmAccurate,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider(color: Colors.white12)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'OR SUGGEST CORRECTION',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: Colors.white12)),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Option 2 & 3: Tag GPS or Pick on Map
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF06B6D4),
                    side: const BorderSide(color: Color(0xFF06B6D4), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isCapturingGps
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4)),
                        )
                      : const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(
                    'I\'m Here (GPS)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isCapturingGps ? null : _captureOnSiteGps,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: Text(
                    'Pick on Map',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _pickOnMap,
                ),
              ),
            ],
          ),

          // Suggested Location Preview Badge
          if (hasCustomPos) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pin_drop_rounded, color: Color(0xFF06B6D4), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SUGGESTED GPS POSITION',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF06B6D4),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '${_suggestedLocation!.latitude.toStringAsFixed(5)}, ${_suggestedLocation!.longitude.toStringAsFixed(5)}' +
                              (_gpsAccuracy != null ? ' (±${_gpsAccuracy!.toStringAsFixed(0)}m)' : ''),
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                    onPressed: () => setState(() => _suggestedLocation = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Optional note (e.g., Near yellow gate / opposite temple)',
                hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  'Submit Correction for Consensus',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                onPressed: _isSubmitting ? null : _submitSuggestion,
              ),
            ),
          ],
        ],
      ),
    ).animate().slideY(begin: 0.2, curve: Curves.easeOutCubic, duration: 250.ms);
  }
}
