import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../components/update_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String _selectedRole = 'user';
  bool _isLoginLoading = false;
  bool _isGuestLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _requestInitialPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkForAppUpdate(context);
    });
  }

  Future<void> _requestInitialPermissions() async {
    // permission_handler does not work on web — browser handles it natively.
    if (kIsWeb) return;
    await [
      Permission.location,
      Permission.notification,
    ].request();
  }

  final List<Map<String, dynamic>> _roles = [
    {'id': 'user', 'icon': Icons.person_outline_rounded, 'label': 'USER'},
    {'id': 'driver', 'icon': Icons.directions_bus_outlined, 'label': 'DRIVER'},
    {'id': 'admin', 'icon': Icons.shield_outlined, 'label': 'ADMIN'},
    {'id': 'manager', 'icon': Icons.settings_outlined, 'label': 'MANAGER'},
  ];

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Identity Verification Failed', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoginLoading = true);

    if (_selectedRole == 'driver') {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required for Drivers'), backgroundColor: Colors.redAccent),
          );
        }
        setState(() => _isLoginLoading = false);
        return;
      }
    }

    if (!mounted) return;
    try {
      await Provider.of<AuthService>(context, listen: false)
          .login(_usernameController.text, _passwordController.text, _selectedRole);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Access Denied: ${e.toString().replaceAll('Exception:', '')}', style: GoogleFonts.plusJakartaSans()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoginLoading = false);
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isGuestLoading = true);
    try {
      await Provider.of<AuthService>(context, listen: false).loginAsGuest();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guest Authorization Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGuestLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    try {
      final api = ApiService();
      final data = await api.get('public/active-form');
      if (data != null && data['active'] == true && data['url'] != null) {
        final url = Uri.parse(data['url']);
        try {
          final success = await launchUrl(url, mode: LaunchMode.externalApplication);
          if (!success) {
            await launchUrl(url);
          }
        } catch (e) {
          debugPrint('Error launching registration URL: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open link: $e'), backgroundColor: Colors.redAccent),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration is currently closed.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect to registration portal'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showForgotPasswordSheet() {
    HapticFeedback.lightImpact();
    final identifierController = TextEditingController();
    final accountController = TextEditingController();
    final tempPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    int step = 1; // 1 = Request Temp Password, 2 = Set New Password
    bool isSubmitting = false;
    bool obscureTemp = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String maskedEmail = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Header with Icon & Steps
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (step == 1 ? AppColors.primary : const Color(0xFF10B981)).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: (step == 1 ? AppColors.primary : const Color(0xFF10B981)).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            step == 1 ? Icons.mark_email_read_rounded : Icons.lock_reset_rounded,
                            color: step == 1 ? AppColors.primaryLight : const Color(0xFF10B981),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step == 1 ? 'Password Recovery' : 'Create New Password',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                step == 1 
                                  ? 'Send temporary password to registered email'
                                  : (maskedEmail.isNotEmpty ? 'Sent to $maskedEmail' : 'Enter temporary and new password'),
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ══════════════════════════════════════════════════════════════
                    // STEP 1: Enter Email / Enrollment & Send Temporary Password
                    // ══════════════════════════════════════════════════════════════
                    if (step == 1) ...[
                      Text(
                        'Enter your registered email address or enrollment number. We will send a secure temporary password to your email to reset your credentials.',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: identifierController,
                        hint: 'Registered Email or Enrollment No.',
                        icon: Icons.alternate_email_rounded,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Works for both Students and Bus Drivers registered in the SISTec transit system.',
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final input = identifierController.text.trim();
                                  if (input.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter your email or enrollment number'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                    return;
                                  }
                                  setModalState(() => isSubmitting = true);
                                  HapticFeedback.mediumImpact();
                                  try {
                                    final api = ApiService();
                                    final res = await api.post('auth/forgot-password', {
                                      'identifier': input,
                                      'email': input.contains('@') ? input : null,
                                      'username': !input.contains('@') ? input : null,
                                    });

                                    setModalState(() {
                                      isSubmitting = false;
                                      step = 2;
                                      accountController.text = res['username'] ?? input;
                                      maskedEmail = res['email'] ?? (input.contains('@') ? input : '');
                                      if (res['tempPassword'] != null) {
                                        tempPasswordController.text = res['tempPassword'].toString();
                                      }
                                    });

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            res['message'] ?? 'Temporary password sent! Please check your email.',
                                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
                                          ),
                                          backgroundColor: const Color(0xFF10B981),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setModalState(() => isSubmitting = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            e.toString().replaceAll('Exception:', '').replaceAll('ApiException(0):', '').trim(),
                                            style: GoogleFonts.plusJakartaSans(),
                                          ),
                                          backgroundColor: Colors.redAccent,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'SEND TEMPORARY PASSWORD',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            setModalState(() {
                              step = 2;
                              accountController.text = identifierController.text.trim();
                            });
                          },
                          child: Text(
                            'Already have a temporary password? Set password here',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primaryLight,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],

                    // ══════════════════════════════════════════════════════════════
                    // STEP 2: Enter Temporary Password & Set New Permanent Password
                    // ══════════════════════════════════════════════════════════════
                    if (step == 2) ...[
                      Text(
                        'Check your email inbox for your temporary password. Enter it below and choose your new permanent password.',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        controller: accountController,
                        hint: 'Enrollment No. / Username',
                        icon: Icons.badge_outlined,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: TextField(
                          controller: tempPasswordController,
                          obscureText: obscureTemp,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
                          decoration: InputDecoration(
                            hintText: 'Temporary Password (from email)',
                            hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontSize: 13.5),
                            prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFFF59E0B), size: 21),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureTemp ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () => setModalState(() => obscureTemp = !obscureTemp),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: TextField(
                          controller: newPasswordController,
                          obscureText: obscureNew,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
                          decoration: InputDecoration(
                            hintText: 'New Password (min. 6 characters)',
                            hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontSize: 13.5),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primaryLight, size: 21),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () => setModalState(() => obscureNew = !obscureNew),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: TextField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirm,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
                          decoration: InputDecoration(
                            hintText: 'Confirm New Password',
                            hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontSize: 13.5),
                            prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.primaryLight, size: 21),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final username = accountController.text.trim();
                                  final tempPwd = tempPasswordController.text.trim();
                                  final newPwd = newPasswordController.text.trim();
                                  final confirmPwd = confirmPasswordController.text.trim();

                                  if (username.isEmpty || tempPwd.isEmpty || newPwd.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please fill all required password fields'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                    return;
                                  }

                                  if (newPwd.length < 6) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('New password must be at least 6 characters long'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                    return;
                                  }

                                  if (newPwd != confirmPwd) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('New passwords do not match. Please recheck.'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSubmitting = true);
                                  HapticFeedback.mediumImpact();

                                  try {
                                    final api = ApiService();
                                    await api.post('auth/force-change-password', {
                                      'username': username,
                                      'currentPassword': tempPwd,
                                      'oldPassword': tempPwd,
                                      'newPassword': newPwd,
                                    });

                                    if (context.mounted) {
                                      Navigator.pop(ctx);
                                      _usernameController.text = username;
                                      _passwordController.text = newPwd;

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Password successfully updated! Signing you in...',
                                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                          backgroundColor: const Color(0xFF10B981),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );

                                      // Auto-login with updated credentials
                                      _handleLogin();
                                    }
                                  } catch (e) {
                                    setModalState(() => isSubmitting = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            e.toString().replaceAll('Exception:', '').replaceAll('ApiException(0):', '').replaceAll('ApiException(400):', '').trim(),
                                            style: GoogleFonts.plusJakartaSans(),
                                          ),
                                          backgroundColor: Colors.redAccent,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'SAVE NEW PASSWORD & SIGN IN',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => setModalState(() => step = 1),
                          child: Text(
                            '← Back to email request',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Background Subtle Depth with ambient breathing animation
          Positioned(
            top: -90,
            left: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
              duration: 3500.ms,
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.15, 1.15),
              curve: Curves.easeInOut,
            ),
          ),
          Positioned(
            bottom: -70,
            right: -60,
            child: Container(
              width: 290,
              height: 290,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
              duration: 4000.ms,
              begin: const Offset(0.95, 0.95),
              end: const Offset(1.2, 1.2),
              curve: Curves.easeInOut,
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),

                    // App Title - Bold, Prominent Modern Typography
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SISTec',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 45,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1.0,
                            ),
                          ),
                          Text(
                            'Chalo',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 45,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF00F0FF),
                              letterSpacing: -1.0,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.12, curve: Curves.easeOutCubic),
                    
                    const SizedBox(height: 10),

                    // Live Beacon Subtitle Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primaryLight.withValues(alpha: 0.28),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Dual Sonar Radar Pulse
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.statusOnline.withValues(alpha: 0.35),
                                ),
                              )
                              .animate(onPlay: (c) => c.repeat())
                              .scale(duration: 1500.ms, begin: const Offset(0.5, 0.5), end: const Offset(2.2, 2.2))
                              .fadeOut(duration: 1500.ms),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.statusOnline,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: AppColors.statusOnline, blurRadius: 6, spreadRadius: 1),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 9),
                          Text(
                            'Track Your Bus In Real-Time',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryLight,
                              letterSpacing: 0.6,
                            ),
                          )
                          .animate(onPlay: (c) => c.repeat())
                          .shimmer(duration: 2200.ms, delay: 2800.ms, color: Colors.white70),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    
                    const SizedBox(height: 20),
                    
                    // Main Login Card
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: AppShadows.card,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 3.5,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'IDENTIFY AS',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Modern Segmented Role Selector
                          Row(
                            children: _roles.map((role) {
                              final isSelected = _selectedRole == role['id'];
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _selectedRole = role['id']);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary.withValues(alpha: 0.18)
                                          : Colors.white.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary
                                            : Colors.white.withValues(alpha: 0.06),
                                        width: isSelected ? 1.8 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          role['icon'], 
                                          color: isSelected ? AppColors.primaryLight : AppColors.textMuted, 
                                          size: 26,
                                        ),
                                        const SizedBox(height: 6),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            role['label'],
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: isSelected ? Colors.white : AppColors.textMuted,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                              
                          const SizedBox(height: 22),
                          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
                          const SizedBox(height: 22),
                          
                          _buildInputField(
                            controller: _usernameController,
                            hint: 'Enrollment No. / Username',
                            icon: Icons.badge_outlined,
                          ),
                          const SizedBox(height: 14),
                          _buildInputField(
                            controller: _passwordController,
                            hint: 'Password',
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                          ),
                          
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordSheet,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 18),
                          
                          // Sign In Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: (_isLoginLoading || _isGuestLoading) ? null : () {
                                HapticFeedback.mediumImpact();
                                _handleLogin();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _isLoginLoading
                                  ? const SizedBox(
                                      width: 20, 
                                      height: 20, 
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'SIGN IN',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.05),
                    
                    const SizedBox(height: 16),
                    
                    // Guest Access Button
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: (_isLoginLoading || _isGuestLoading) ? null : _handleGuestLogin,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.explore_rounded, color: AppColors.accent, size: 20),
                                const SizedBox(width: 8),
                                _isGuestLoading 
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                                  : Text(
                                      'Continue as Guest',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontSize: 13.5),
          prefixIcon: Icon(icon, color: AppColors.primaryLight, size: 21),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
    );
  }
}
