import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/route_model.dart';
import '../models/bus_model.dart';

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
      'color': Color(0xFFFF2E63),
      'desc': 'Overspeeding, unsafe maneuvers, sudden braking',
    },
    'late_arrival': {
      'label': 'Late Arrival',
      'icon': Icons.schedule_rounded,
      'color': Color(0xFFFFB347),
      'desc': 'Bus arrived significantly later than schedule',
    },
    'misconduct': {
      'label': 'Driver Misconduct',
      'icon': Icons.person_off_rounded,
      'color': Color(0xFFB721FF),
      'desc': 'Rude behavior, ignoring stops, phone while driving',
    },
    'overloaded': {
      'label': 'Bus Overloaded',
      'icon': Icons.people_alt_rounded,
      'color': Color(0xFF00F0FF),
      'desc': 'Bus carrying more passengers than capacity',
    },
    'other': {
      'label': 'Other Issue',
      'icon': Icons.report_gmailerrorred_rounded,
      'color': Color(0xFF2D5BFF),
      'desc': 'Any other concern not listed above',
    },
  };

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      await _api.post('complaints', {
        'userId': auth.currentUser?.id ?? 'guest',
        'userName': auth.currentUser?.username ?? 'User',
        'routeId': widget.selectedRoute?.id,
        'routeName': widget.selectedRoute?.name,
        'driverName': 'Driver',
        'busNumber': widget.activeBus?.busNumber,
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
            backgroundColor: const Color(0xFFFF2E63),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
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
                letterSpacing: 1,
              ),
            ),
            Text(
              widget.selectedRoute?.name ?? 'All Routes',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white38,
                fontSize: 10,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00F0FF).withValues(alpha: 0.1),
              border: Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFF00F0FF), size: 44),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text(
            'COMPLAINT FILED',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 8),
          Text(
            'Our team will review it within 24 hours.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 13),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D5BFF).withValues(alpha: 0.15),
              foregroundColor: const Color(0xFF2D5BFF),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: Text(
              'DONE',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ).animate().fadeIn(delay: 500.ms),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category picker
            Text(
              'INCIDENT TYPE',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            ..._categories.entries.map((e) => _buildCategoryTile(e.key, e.value)),
            const SizedBox(height: 32),

            // Description
            Text(
              'DESCRIBE THE INCIDENT',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D121F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: TextFormField(
                controller: _descController,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                maxLines: 5,
                minLines: 4,
                decoration: InputDecoration(
                  hintText: 'Tell us what happened — be as specific as possible...',
                  hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(20),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 15) {
                    return 'Please provide at least 15 characters of detail';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your complaint is anonymous to other users and will only be reviewed by the transport manager.',
              style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10, height: 1.5),
            ),
            const SizedBox(height: 40),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitComplaint,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2E63),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  elevation: 0,
                  disabledBackgroundColor: const Color(0xFFFF2E63).withValues(alpha: 0.3),
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
                          const SizedBox(width: 10),
                          Text(
                            'SUBMIT COMPLAINT',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w900,
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
      onTap: () => setState(() => _selectedCategory = key),
      child: AnimatedContainer(
        duration: 200.ms,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : const Color(0xFF0D121F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.04),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.15 : 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(cat['icon'] as IconData, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat['label'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cat['desc'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white24,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
