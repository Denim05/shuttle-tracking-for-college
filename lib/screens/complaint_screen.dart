import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/route_model.dart';
import '../models/bus_model.dart';
import '../theme/app_theme.dart';

class ComplaintScreen extends StatefulWidget {
  final RouteModel? selectedRoute;
  final Bus? activeBus;

  const ComplaintScreen({
    super.key,
    this.selectedRoute,
    this.activeBus,
  });

  @override
  State<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  String _selectedCategory = 'rash_driving';
  bool _isSubmitting = false;
  bool _submitted = false;

  static const Map<String, Map<String, dynamic>> _categories = {
    'rash_driving': {
      'label': 'Rash Driving',
      'icon': Icons.speed_rounded,
      'color': AppColors.danger,
      'desc': 'Overspeeding, unsafe maneuvers, sudden braking',
    },
    'late_arrival': {
      'label': 'Late Arrival',
      'icon': Icons.schedule_rounded,
      'color': AppColors.warning,
      'desc': 'Bus arrived significantly later than schedule',
    },
    'misconduct': {
      'label': 'Driver Misconduct',
      'icon': Icons.person_off_rounded,
      'color': AppColors.accentPurple,
      'desc': 'Rude behavior, ignoring stops, phone while driving',
    },
    'overloaded': {
      'label': 'Bus Overloaded',
      'icon': Icons.people_alt_rounded,
      'color': AppColors.primaryLight,
      'desc': 'Bus carrying more passengers than safe capacity',
    },
    'other': {
      'label': 'Other Issue',
      'icon': Icons.report_problem_rounded,
      'color': AppColors.accent,
      'desc': 'Any other campus transit concern',
    },
  };

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      await _api.post('complaints', {
        'userId': auth.currentUser?.id ?? 'guest',
        'userName': auth.currentUser?.username ?? 'User',
        'routeId': widget.selectedRoute?.id,
        'routeName': widget.selectedRoute?.name,
        'driverName': 'Driver',
        'busNumber': widget.activeBus?.routeName,
        'category': _selectedCategory,
        'description': _descController.text.trim(),
      });
      if (mounted) setState(() { _submitted = true; _isSubmitting = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgSecondary,
        elevation: 0,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FILE A COMPLAINT',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              widget.selectedRoute?.name ?? 'General Feedback',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: _submitted ? _buildSuccessView() : _buildForm(),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.accentGreen.withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.accentGreen, size: 40),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              'COMPLAINT SUBMITTED',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Text(
              'Your concern has been forwarded directly to campus transit management for review.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: 32),
            SizedBox(
              width: 180,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Text(
                  'DONE',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    fontSize: 13,
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Incident Category Selector
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'SELECT INCIDENT TYPE',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            ..._categories.entries.map((e) => _buildCategoryTile(e.key, e.value)),
            const SizedBox(height: 24),

            // Description
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'INCIDENT DETAILS',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: TextFormField(
                controller: _descController,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                maxLines: 5,
                minLines: 4,
                decoration: InputDecoration(
                  hintText: 'Tell us what happened — include time, stop, or specific details...',
                  hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(18),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 15) {
                    return 'Please provide at least 15 characters of detail';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.textMuted, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your complaint is securely delivered to the transport coordinator.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitComplaint,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.3),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'SUBMIT COMPLAINT',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 1,
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
  }

  Widget _buildCategoryTile(String key, Map<String, dynamic> cat) {
    final isSelected = _selectedCategory == key;
    final color = cat['color'] as Color;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedCategory = key);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(cat['icon'] as IconData, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat['label'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? Colors.white : AppColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cat['desc'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 18)
            else
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


