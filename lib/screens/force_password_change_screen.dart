import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  int _passwordStrength = 0; // 0 to 3

  @override
  void initState() {
    super.initState();
    _newPasswordCtrl.addListener(_evaluatePasswordStrength);
  }

  @override
  void dispose() {
    _newPasswordCtrl.removeListener(_evaluatePasswordStrength);
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  void _evaluatePasswordStrength() {
    final text = _newPasswordCtrl.text;
    int strength = 0;
    if (text.length >= 6) strength++;
    if (RegExp(r'[a-zA-Z]').hasMatch(text) && RegExp(r'[0-9]').hasMatch(text)) strength++;
    if (text.length >= 8 && RegExp(r'[^a-zA-Z0-9]').hasMatch(text)) strength++;
    if (mounted) setState(() => _passwordStrength = strength);
  }

  Future<void> _handlePasswordChange() async {
    final current = _currentPasswordCtrl.text.trim();
    final newPass = _newPasswordCtrl.text.trim();
    final confirmPass = _confirmPasswordCtrl.text.trim();

    if (current.isEmpty) {
      _showErrorSnackBar('Please enter your current temporary password.');
      return;
    }

    if (newPass.length < 6) {
      _showErrorSnackBar('New password must be at least 6 characters long.');
      return;
    }

    if (newPass == current) {
      _showErrorSnackBar('New password cannot be identical to your temporary password.');
      return;
    }

    if (newPass != confirmPass) {
      _showErrorSnackBar('New passwords do not match. Please recheck.');
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.forceChangePassword(current, newPass);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Password updated successfully! Welcome to SISTecChalo.',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF151D30),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(e.toString().replaceAll('Exception:', '').trim());
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1524),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getStrengthColor() {
    switch (_passwordStrength) {
      case 1: return AppColors.danger;
      case 2: return AppColors.warning;
      case 3: return AppColors.accentGreen;
      default: return Colors.white24;
    }
  }

  String _getStrengthLabel() {
    switch (_passwordStrength) {
      case 1: return 'WEAK';
      case 2: return 'MODERATE';
      case 3: return 'STRONG & SECURE';
      default: return 'TOO SHORT';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;
    final userName = user?.name ?? user?.username ?? 'Commuter';

    return PopScope(
      canPop: false, // Compulsory — cannot back out without setting password
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          children: [
            // Ambient Background Glow
            Positioned(
              top: -80,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),

                    // Top Security Icon Badge
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: AppColors.primaryLight, size: 32),
                    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), curve: Curves.easeOutBack),

                    const SizedBox(height: 24),

                    // Header Text
                    Text(
                      'Welcome, $userName!',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 150.ms),

                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined, color: AppColors.warning, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'MANDATORY FIRST-TIME SECURITY SETUP',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppColors.warning,
                                letterSpacing: 1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 250.ms),

                    const SizedBox(height: 12),

                    Text(
                      'You are currently logged in with a temporary default password. For the security of your transit account, please set your permanent personal password to proceed.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 350.ms),

                    const SizedBox(height: 32),

                    // Password Card Form
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: AppShadows.card,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Current Temporary Password
                          _buildFieldLabel('CURRENT TEMPORARY PASSWORD'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _currentPasswordCtrl,
                            hint: 'Enter the password sent to you (e.g. 123456)',
                            obscure: _obscureCurrent,
                            onToggleObscure: () => setState(() => _obscureCurrent = !_obscureCurrent),
                            icon: Icons.key_rounded,
                          ),

                          const SizedBox(height: 20),

                          // 2. New Permanent Password
                          _buildFieldLabel('NEW PERSONAL PASSWORD'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _newPasswordCtrl,
                            hint: 'Create new password (min. 6 characters)',
                            obscure: _obscureNew,
                            onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
                            icon: Icons.lock_outline_rounded,
                          ),

                          // Live Strength Meter
                          if (_newPasswordCtrl.text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _passwordStrength / 3.0,
                                      backgroundColor: Colors.white10,
                                      color: _getStrengthColor(),
                                      minHeight: 5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _getStrengthLabel(),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: _getStrengthColor(),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 20),

                          // 3. Confirm New Password
                          _buildFieldLabel('CONFIRM NEW PASSWORD'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _confirmPasswordCtrl,
                            hint: 'Re-enter your new password',
                            obscure: _obscureConfirm,
                            onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            icon: Icons.check_circle_outline_rounded,
                          ),

                          const SizedBox(height: 28),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ? null : _handlePasswordChange,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'UPDATE & ACTIVATE ACCOUNT',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.8,
                                              color: Colors.white,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.08),

                    const SizedBox(height: 24),

                    // Sign Out Option
                    TextButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Provider.of<AuthService>(context, listen: false).logout();
                      },
                      icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.white38),
                      label: Text(
                        'Not your account? Sign Out',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: AppColors.primaryLight, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: onToggleObscure,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
