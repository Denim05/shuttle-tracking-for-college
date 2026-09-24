import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import 'commute_setup_screen.dart';
import '../theme/app_theme.dart';
import '../components/developer_info_dialog.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../main.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  bool _isSaving = false;
  
  String _role = 'user';
  Map<String, dynamic> _profile = {};

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _contactNumCtrl = TextEditingController();

  // Password reset controllers
  final _currPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _contactNumCtrl.dispose();
    _currPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.get('users/profile');
      if (res != null) {
        setState(() {
          _role = res['role']?.toString() ?? 'user';
          _profile = res['profile'] as Map<String, dynamic>;
          
          _nameCtrl.text = _profile['name'] ?? _profile['username'] ?? '';
          _emailCtrl.text = _profile['email'] ?? '';
          _phoneCtrl.text = _profile['phone'] ?? '';
          _contactNumCtrl.text = _profile['contactNumber'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load profile: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    }
  }

  Color _getRoleColor() {
    switch (_role.toLowerCase()) {
      case 'admin': return AppColors.accentPurple;
      case 'manager': return AppColors.primary;
      case 'driver': return AppColors.accent;
      default: return AppColors.primaryLight;
    }
  }

  IconData _getRoleIcon() {
    switch (_role.toLowerCase()) {
      case 'admin': return Icons.admin_panel_settings_rounded;
      case 'manager': return Icons.manage_accounts_rounded;
      case 'driver': return Icons.directions_bus_rounded;
      default: return Icons.person_rounded;
    }
  }

  Future<void> _saveProfileChanges() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);
    try {
      final body = <String, dynamic>{};
      
      if (_role == 'admin' || _role == 'manager') {
        body['email'] = _emailCtrl.text.trim();
        body['name'] = _nameCtrl.text.trim();
      } else if (_role == 'driver') {
        body['name'] = _nameCtrl.text.trim();
        body['email'] = _emailCtrl.text.trim();
        body['contactNumber'] = _contactNumCtrl.text.trim();
      } else if (_role == 'user') {
        body['name'] = _nameCtrl.text.trim();
        body['email'] = _emailCtrl.text.trim();
        body['phone'] = _phoneCtrl.text.trim();
      }

      await _apiService.put('users/profile', body);
      await _fetchProfile();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 18),
                const SizedBox(width: 8),
                Text('Profile updated successfully!', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            backgroundColor: const Color(0xFF13222A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.3)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showPasswordResetDialog() {
    _currPasswordCtrl.clear();
    _newPasswordCtrl.clear();
    _confirmPasswordCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogCtx) {
        bool resetting = false;
        bool showCurr = false;
        bool showNew = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(dialogCtx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.vpn_key_rounded, color: AppColors.primaryLight, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'CHANGE PASSWORD',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ensure your new password contains at least 6 characters.',
                        style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 20),

                      // Current Password
                      _buildModalTextField(
                        controller: _currPasswordCtrl,
                        hint: 'Current Password',
                        obscure: !showCurr,
                        onToggle: () => setDialogState(() => showCurr = !showCurr),
                      ),
                      const SizedBox(height: 12),

                      // New Password
                      _buildModalTextField(
                        controller: _newPasswordCtrl,
                        hint: 'New Password (min 6 chars)',
                        obscure: !showNew,
                        onToggle: () => setDialogState(() => showNew = !showNew),
                      ),
                      const SizedBox(height: 12),

                      // Confirm Password
                      _buildModalTextField(
                        controller: _confirmPasswordCtrl,
                        hint: 'Confirm New Password',
                        obscure: !showNew,
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: resetting ? null : () async {
                            final curr = _currPasswordCtrl.text.trim();
                            final next = _newPasswordCtrl.text.trim();
                            final conf = _confirmPasswordCtrl.text.trim();

                            if (curr.isEmpty || next.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('All fields are required.'),
                                  backgroundColor: AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              );
                              return;
                            }
                            if (next.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('New password must be at least 6 characters.'),
                                  backgroundColor: AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              );
                              return;
                            }
                            if (next != conf) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Passwords do not match.'),
                                  backgroundColor: AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              );
                              return;
                            }

                            final messenger = ScaffoldMessenger.of(context);
                            final nav = Navigator.of(dialogCtx);
                            setDialogState(() => resetting = true);
                            try {
                              await _apiService.put('users/change-password', {
                                'currentPassword': curr,
                                'newPassword': next,
                              });
                              
                              if (mounted) {
                                nav.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 18),
                                        const SizedBox(width: 8),
                                        Text('Password updated successfully!', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                      ],
                                    ),
                                    backgroundColor: const Color(0xFF13222A),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.3)),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() => resetting = false);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Failed: $e'),
                                  backgroundColor: AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: resetting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text('UPDATE PASSWORD', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalTextField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    VoidCallback? onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          suffixIcon: onToggle != null
              ? IconButton(
                  icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.textMuted, size: 18),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ListView(
                controller: scrollController,
                children: [
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.security_rounded, color: AppColors.accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Privacy & Location Policy',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Campus Transit Data Standards • July 2026',
                    style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 11),
                  ),
                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 28),
                  
                  _buildPolicySection(
                    '1. Location Telemetry Collection',
                    'Our system collects real-time vehicle GPS coordinates to compute accurate transit ETAs. For drivers, location is transmitted during active trips. For students, proximity location is computed locally to calculate walking distance to stops.',
                  ),
                  _buildPolicySection(
                    '2. How Transit Data Is Used',
                    'Transit metrics are utilized solely for campus route scheduling, live map markers, and push notifications. Personal location history is never shared with third-party networks or advertisers.',
                  ),
                  _buildPolicySection(
                    '3. End-to-End Encryption',
                    'All WebSocket socket frames, route coordinates, and student identifiers are encrypted in transit over HTTPS and WSS with strict token authorization.',
                  ),
                  _buildPolicySection(
                    '4. User Controls & Privacy',
                    'You can toggle proximity alerts or update your commute pickup point at any time in settings.',
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text(
                        'I UNDERSTAND',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPolicySection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _getRoleColor();
    final roleIcon = _getRoleIcon();
    final username = _profile['username'] ?? 'N/A';
    final name = _profile['name'] ?? username;

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
        title: Text(
          'PROFILE & SETTINGS',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: GestureDetector(
                onTap: () => _handleLogout(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Profile Header Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: roleColor.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: Icon(roleIcon, color: roleColor, size: 34),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          if (username.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.badge_outlined, color: AppColors.textMuted, size: 12),
                                  const SizedBox(width: 5),
                                  Text(
                                    username,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _role.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                color: roleColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.06),
                
                const SizedBox(height: 24),
                _buildSectionHeader('EDITABLE INFORMATION'),
                const SizedBox(height: 10),

                // Editable Fields Container
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildModernInput(_nameCtrl, 'Full Name', Icons.person_outline_rounded),
                      const SizedBox(height: 12),
                      _buildModernInput(_emailCtrl, 'Email Address', Icons.alternate_email_rounded, keyboardType: TextInputType.emailAddress),
                      if (_role == 'user') ...[
                        const SizedBox(height: 12),
                        _buildModernInput(_phoneCtrl, 'Contact Phone', Icons.phone_android_rounded, keyboardType: TextInputType.phone),
                      ],
                      if (_role == 'driver') ...[
                        const SizedBox(height: 12),
                        _buildModernInput(_contactNumCtrl, 'Contact Phone', Icons.phone_android_rounded, keyboardType: TextInputType.phone),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Read-only metadata
                if (_role == 'user' || _role == 'manager' || _role == 'driver') ...[
                  _buildSectionHeader('SYSTEM VERIFICATION DATA'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        if (_role == 'manager') ...[
                          _buildReadOnlyItem('Employee ID', _profile['employeeId'] ?? 'N/A', Icons.badge_outlined),
                          _buildReadOnlyItem('Department', _profile['department'] ?? 'N/A', Icons.business_rounded),
                          _buildReadOnlyItem('Management Scope', (_profile['canManage'] as List?)?.join(', ').toUpperCase() ?? 'N/A', Icons.shield_outlined),
                        ],
                        if (_role == 'driver') ...[
                          _buildReadOnlyItem('Assigned Bus', _profile['assignedBus'] ?? 'NOT ASSIGNED', Icons.directions_bus_rounded),
                          _buildReadOnlyItem('Account Status', _profile['status'] ?? 'ACTIVE', Icons.verified_user_rounded),
                        ],
                        if (_role == 'user') ...[
                          _buildReadOnlyItem('Student Enrollment', username, Icons.badge_outlined),
                          _buildReadOnlyItem('Course & Branch', _profile['courseName'] ?? 'N/A', Icons.school_rounded),
                          _buildReadOnlyItem('Father\'s Name', _profile['fatherName'] ?? 'N/A', Icons.family_restroom_rounded),
                          _buildReadOnlyItem('Father\'s Contact', _profile['fatherPhone'] ?? 'N/A', Icons.phone_enabled_rounded),
                          _buildReadOnlyItem('Pickup Stop', _profile['pickupPoint'] ?? 'N/A', Icons.location_on_rounded),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                _buildSectionHeader('PREFERENCES & SECURITY'),
                const SizedBox(height: 10),

                // Action Tiles Group
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: _showPasswordResetDialog,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: AppColors.primaryLight, size: 18),
                          ),
                          title: Text('CHANGE ACCOUNT PASSWORD', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                        ),
                        if (_role == 'user') ...[
                          Divider(color: Colors.white.withValues(alpha: 0.04), height: 1),
                          ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CommuteSetupScreen(isInitialSetup: false)),
                              ).then((_) => _fetchProfile());
                            },
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.alt_route_rounded, color: AppColors.accent, size: 18),
                            ),
                            title: Text('DAILY COMMUTE & PICKUP STOP', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                            subtitle: Text(
                              _profile['pickupPoint'] != null 
                                ? 'Stop: ${_profile['pickupPoint']}'
                                : 'Tap to configure your daily Bhopal stop',
                              style: GoogleFonts.plusJakartaSans(color: AppColors.accent, fontSize: 11),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                          ),
                        ],
                        Divider(color: Colors.white.withValues(alpha: 0.04), height: 1),
                        ListTile(
                          onTap: _showPrivacyPolicy,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.accentGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.shield_rounded, color: AppColors.accentGreen, size: 18),
                          ),
                          title: Text('PRIVACY POLICY & DATA USAGE', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
                        ),
                        Divider(color: Colors.white.withValues(alpha: 0.04), height: 1),
                        ListTile(
                          onTap: () => showDeveloperCreditsModal(context),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.code_rounded, color: AppColors.primaryLight, size: 18),
                          ),
                          title: Text(
                            'DEVELOPER CREDITS (TEAM RAFFTAR)',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'Lead: Denim Hajare • SISTec Bhopal',
                            style: GoogleFonts.plusJakartaSans(color: AppColors.primaryLight, fontSize: 11),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primaryLight, size: 14),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                
                // Save Changes Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfileChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('SAVE CHANGES', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.2)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleLogout(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF87171),
                      side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(
                      'LOG OUT OF SESSION',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final auth = Provider.of<AuthService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        title: Text(
          'Confirm Logout',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to log out of your session on this device?',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'LOG OUT',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await auth.logout();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildModernInput(TextEditingController ctrl, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          icon: Icon(icon, color: AppColors.textMuted, size: 18),
          labelText: label.toUpperCase(),
          labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildReadOnlyItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textMuted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value.isEmpty ? 'N/A' : value,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
