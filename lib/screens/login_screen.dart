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
import '../components/developer_info_dialog.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070E),
      body: Stack(
        children: [
          // Background Depth
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2D5BFF).withOpacity(0.1),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2), duration: 5.seconds),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  Text(
                    'SISTecChalo',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                  
                  Text(
                    'TRACK YOUR BUS IN REAL TIME',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryLight,
                      letterSpacing: 3,
                    ),
                  ).animate().fadeIn(delay: 400.ms),
                  
                  const SizedBox(height: 48),
                  
                  // Login Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 4, height: 16, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 8),
                            Text(
                              'IDENTIFY AS',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        
                        Row(
                          children: _roles.map((role) {
                            final isSelected = _selectedRole == role['id'];
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _selectedRole = role['id']);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  height: 82,
                                  decoration: BoxDecoration(
                                    gradient: isSelected ? const LinearGradient(
                                      colors: [AppColors.primary, Color(0xFF2563EB)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ) : null,
                                    color: isSelected ? null : Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? Colors.white.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
                                      width: 1.2,
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.45),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                      )
                                    ] : [],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        role['icon'], 
                                        color: isSelected ? Colors.white : AppColors.textMuted, 
                                        size: 24
                                      ).animate(target: isSelected ? 1 : 0).scale(begin: const Offset(1,1), end: const Offset(1.1,1.1)),
                                      const SizedBox(height: 6),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          role['label'],
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
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
                            
                            const SizedBox(height: 28),
                            const Divider(color: Colors.white10),
                            const SizedBox(height: 28),
                                                       _buildInputField(
                              controller: _usernameController,
                              hint: 'Username / Enrollment No.',
                              icon: Icons.alternate_email_rounded,
                            ),
                            const SizedBox(height: 16),
                            _buildInputField(
                              controller: _passwordController,
                              hint: 'Password',
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                            ),
                            
                            const SizedBox(height: 28),
                            
                            Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.accent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.4),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: (_isLoginLoading || _isGuestLoading) ? null : () {
                                  HapticFeedback.mediumImpact();
                                  _handleLogin();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                child: _isLoginLoading
                                    ? const SizedBox(
                                        width: 22, 
                                        height: 22, 
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.login_rounded, color: Colors.white, size: 18),
                                          const SizedBox(width: 8),
                                          Text(
                                            'SIGN IN',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.5,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        )
                      ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.08),
                  
                  const SizedBox(height: 24),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: TextButton.icon(
                      onPressed: (_isLoginLoading || _isGuestLoading) ? null : _handleGuestLogin,
                      icon: const Icon(Icons.explore_rounded, color: AppColors.accent, size: 18),
                      label: _isGuestLoading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            'Continue as Guest (Live Tracker)',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Developer Credits Footer Badge
                  InkWell(
                    onTap: () => showDeveloperCreditsModal(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          const Icon(Icons.rocket_launch_rounded, color: Color(0xFF60A5FA), size: 13),
                          Text(
                            'Team Rafftar',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF93C5FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '•',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white30,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Lead: Denim Hajare',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFFFBBF24),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
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
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white30, fontWeight: FontWeight.w500, fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.primaryLight, size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}


