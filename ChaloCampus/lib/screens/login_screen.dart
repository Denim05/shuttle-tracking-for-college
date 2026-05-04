import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

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
                color: const Color(0xFF2D5BFF).withValues(alpha: 0.1),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2), duration: 5.seconds),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  // Logo
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2D5BFF).withValues(alpha: 0.2),
                          blurRadius: 40,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF2D5BFF), size: 64),
                    ),
                  ).animate().fadeIn(duration: 800.ms).slideY(begin: -0.2),
                  
                  const SizedBox(height: 60),
                  
                  Text(
                    'ChaloCampus',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                  
                  Text(
                    'Track Your Bus In Real Time',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2D5BFF),
                      letterSpacing: 4,
                    ),
                  ).animate().fadeIn(delay: 400.ms),
                  
                  const SizedBox(height: 60),
                  
                  // Login Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 3, height: 16, decoration: BoxDecoration(color: const Color(0xFF2D5BFF), borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 8),
                            Text(
                              'IDENTIFY AS',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.white60,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        Row(
                          children: _roles.map((role) {
                            final isSelected = _selectedRole == role['id'];
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _selectedRole = role['id']);
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  height: 85,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF2D5BFF) : Color(0xFF1E1E1E).withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? Colors.white24 : Colors.white.withValues(alpha: 0.05),
                                      width: 1,
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: const Color(0xFF2D5BFF).withValues(alpha: 0.4),
                                        blurRadius: 25,
                                        offset: const Offset(0, 8),
                                      )
                                    ] : [],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        role['icon'], 
                                        color: isSelected ? Colors.white : Colors.white38, 
                                        size: 26
                                      ).animate(target: isSelected ? 1 : 0).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2)),
                                      const SizedBox(height: 8),
                                      Text(
                                        role['label'],
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: isSelected ? Colors.white : Colors.white24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        
                        const SizedBox(height: 32),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 32),
                        
                        _buildInputField(
                          controller: _usernameController,
                          hint: 'Username',
                          icon: Icons.alternate_email_rounded,
                        ),
                        const SizedBox(height: 20),
                        _buildInputField(
                          controller: _passwordController,
                          hint: 'Password',
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                        ),
                        
                        const SizedBox(height: 40),
                        
                        SizedBox(
                          width: double.infinity,
                          height: 64,
                          child: ElevatedButton(
                            onPressed: (_isLoginLoading || _isGuestLoading) ? null : () {
                              HapticFeedback.mediumImpact();
                              _handleLogin();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2D5BFF),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            child: _isLoginLoading
                                ? const SizedBox(
                                    width: 24, 
                                    height: 24, 
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                                  )
                                : Text(
                                    'SIGN IN',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1),
                  
                  const SizedBox(height: 32),
                  
                  TextButton(
                    onPressed: (_isLoginLoading || _isGuestLoading) ? null : _handleGuestLogin,
                    child: _isGuestLoading 
                      ? const CircularProgressIndicator()
                      : RichText(
                          text: TextSpan(
                            style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 14),
                            children: [
                              const TextSpan(text: 'Not a Registered User? '),
                              TextSpan(
                                text: 'Continue as Guest',
                                style: TextStyle(
                                  color: const Color(0xFF2D5BFF).withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                  const SizedBox(height: 40),
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
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: Colors.white38, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        ),
      ),
    );
  }
}
