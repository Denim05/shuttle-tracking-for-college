import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../components/custom_text_field.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

  final List<String> _roles = ['user', 'driver', 'admin', 'manager'];

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Username and Password')),
      );
      return;
    }

    setState(() => _isLoginLoading = true);

    try {
      final success = await Provider.of<AuthService>(context, listen: false)
          .login(_usernameController.text, _passwordController.text, _selectedRole);

      if (success) {
        // Navigation is handled in main.dart
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoginLoading = false);
      }
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isGuestLoading = true);
    try {
      await Provider.of<AuthService>(context, listen: false).loginAsGuest();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guest Login Failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isGuestLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, // Transparent status bar
        statusBarIconBrightness: Brightness.light, // Light icons for dark background
        statusBarBrightness: Brightness.dark, // iOS dark background
      ),
      child: Scaffold(
        body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF02040A), Color(0xFF060B19), Color(0xFF0B132B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo Container
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1528),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1A4CFF).withValues(alpha: 0.15),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded, 
                        size: 70, 
                        color: const Color(0xFF1A4CFF),
                        shadows: [
                          Shadow(
                            color: const Color(0xFF1A4CFF).withValues(alpha: 0.5),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sistec Chalo',
                    style: GoogleFonts.outfit(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'SHUTTLE TRACKER',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                      color: const Color(0xFF1A4CFF),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Glassmorphic Login Card
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Role Selection Header
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A4CFF),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'IDENTIFY AS',
                              style: GoogleFonts.outfit(
                                color: Colors.white70,
                                fontSize: 12,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Improved Role Selection
                        Row(
                          children: _roles.map((role) {
                            final isSelected = _selectedRole == role;
                            IconData roleIcon;
                            String label;
                            switch (role) {
                              case 'admin': roleIcon = Icons.shield_outlined; label = 'ADMIN'; break;
                              case 'manager': roleIcon = Icons.settings_outlined; label = 'MANAGER'; break;
                              case 'driver': roleIcon = Icons.directions_bus_filled_outlined; label = 'DRIVER'; break;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  default: roleIcon = Icons.person_outline_rounded; label = 'USER';
                            }

                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedRole = role),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: isSelected 
                                        ? const Color(0xFF1A4CFF) 
                                        : Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.05),
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: const Color(0xFF1A4CFF).withValues(alpha: 0.4),
                                        blurRadius: 15,
                                        offset: const Offset(0, 4),
                                      )
                                    ] : [],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        roleIcon,
                                        size: 20,
                                        color: isSelected ? Colors.white : Colors.white24,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        label,
                                        style: GoogleFonts.outfit(
                                          color: isSelected ? Colors.white : Colors.white38,
                                          fontSize: 9,
                                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ).animate(target: isSelected ? 1 : 0)
                               .shimmer(duration: 1000.ms, color: Colors.white24),
                            );
                          }).toList(),
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(color: Colors.white10, thickness: 1),
                        ),

                        CustomTextField(
                          controller: _usernameController,
                          hintText: 'Username',
                          icon: Icons.alternate_email_rounded,
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          controller: _passwordController,
                          hintText: 'Password',
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                        ),
                        const SizedBox(height: 32),

                        // Login Button
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton(
                            onPressed: (_isLoginLoading || _isGuestLoading) ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A4CFF),
                              disabledBackgroundColor: const Color(0xFF1A4CFF).withValues(alpha: 0.6),
                              foregroundColor: Colors.white,
                              elevation: 8,
                              shadowColor: const Color(0xFF1A4CFF).withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _isLoginLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Text(
                                    'SIGN IN',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                          ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                           .shimmer(duration: 2000.ms, color: Colors.white12),
                        ),
                        const SizedBox(height: 16),
                        
                        // Guest Button
                        TextButton(
                          onPressed: (_isLoginLoading || _isGuestLoading) ? null : _handleGuestLogin,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white54,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                          ),
                          child: _isGuestLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                                )
                              : RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.outfit(fontSize: 14, color: Colors.white54),
                                    children: [
                                      const TextSpan(text: 'Not a Registered User? '),
                                      TextSpan(
                                        text: 'Continue as Guest',
                                        style: TextStyle(
                                          color: const Color(0xFF1A4CFF).withValues(alpha: 0.8),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}
