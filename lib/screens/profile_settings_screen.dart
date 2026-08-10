import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';

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
          SnackBar(content: Text('Failed to load profile: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Color _getRoleColor() {
    switch (_role.toLowerCase()) {
      case 'admin': return Colors.purpleAccent;
      case 'manager': return Colors.blueAccent;
      case 'driver': return Colors.tealAccent;
      default: return Colors.blue;
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
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showPasswordResetDialog() {
    _currPasswordCtrl.clear();
    _newPasswordCtrl.clear();
    _confirmPasswordCtrl.clear();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        bool resetting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F1528),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.vpn_key_rounded, color: Colors.purpleAccent),
                  const SizedBox(width: 12),
                  Text('Change Password', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _currPasswordCtrl,
                      obscureText: true,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'CURRENT PASSWORD',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPasswordCtrl,
                      obscureText: true,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'NEW PASSWORD',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmPasswordCtrl,
                      obscureText: true,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'CONFIRM NEW PASSWORD',
                        labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: resetting ? null : () => Navigator.pop(dialogCtx),
                  child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38)),
                ),
                ElevatedButton(
                  onPressed: resetting ? null : () async {
                    final curr = _currPasswordCtrl.text;
                    final next = _newPasswordCtrl.text;
                    final conf = _confirmPasswordCtrl.text;

                    if (curr.isEmpty || next.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All fields are required.'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }
                    if (next.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('New password must be at least 6 characters.'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }
                    if (next != conf) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Passwords do not match.'), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }

                    setDialogState(() => resetting = true);
                    try {
                      await _apiService.put('users/change-password', {
                        'currentPassword': curr,
                        'newPassword': next,
                      });
                      
                      if (mounted) {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => resetting = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to change password: $e'), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: resetting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('CHANGE', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ListView(
                controller: scrollController,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.security_rounded, color: Colors.tealAccent, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Privacy Policy',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last Updated: July 2026',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11),
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  
                  _buildPolicySection(
                    '1. Location Data Collection',
                    'Our app collects precise real-time location data of vehicles to provide tracking services. For drivers, location data is collected in the foreground and/or background when sharing route coordinates so students can see active buses. For users, location is optionally used to show your distance relative to stops.',
                  ),
                  _buildPolicySection(
                    '2. How We Use Data',
                    'Location and transit data are used solely to calculate accurate Estimated Time of Arrival (ETA), display live bus markers, and send notifications. We do not sell or share individual transit or location history with third-party advertising services.',
                  ),
                  _buildPolicySection(
                    '3. Data Protection & Security',
                    'All coordinates, speed updates, and profile details are encrypted in transit using Secure WebSockets (WSS) and HTTPS. Connection status is constantly audited for system security.',
                  ),
                  _buildPolicySection(
                    '4. Your Controls & Permissions',
                    'You can grant or revoke location permissions at any time through your device settings. Disabling location tracking will disable live broadcasting for drivers and personal proximity tracking for users.',
                  ),
                  _buildPolicySection(
                    '5. Contact & Support',
                    'For questions regarding safety policies or data compliance, please reach out to the campus transit administration help desk.',
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent.withOpacity(0.12),
                      foregroundColor: Colors.tealAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.tealAccent.withOpacity(0.3)),
                    ),
                    child: Text(
                      'I UNDERSTAND',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
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
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withOpacity(0.8),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white60,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 24),
              const SizedBox(width: 12),
              Text(
                'System Information',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAboutRow('Application', 'SmartCampus Bus'),
              _buildAboutRow('Platform Version', 'v2.4.0 (Stable)'),
              _buildAboutRow('API Gateway', 'Secure Gateway Active'),
              _buildAboutRow('WebSocket Client', 'WSS Connected'),
              _buildAboutRow('System Mode', _role.toUpperCase()),
              const Divider(color: Colors.white10, height: 20),
              Text(
                '© 2026 SmartTransit Systems. Designed for real-time fleet scheduling, driver telemetry, and safe campus logistics.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'CLOSE',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11)),
          Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'PROFILE & SETTINGS',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 2),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [Color(0xFF0F172A), Color(0xFF121212)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ListView(
                  children: [
                    const SizedBox(height: 16),
                    // Profile Header card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: roleColor.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: roleColor.withOpacity(0.1),
                            child: Icon(roleIcon, color: roleColor, size: 36),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            name,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: roleColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: roleColor.withOpacity(0.25)),
                            ),
                            child: Text(
                              _role.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(color: roleColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn().slideY(begin: 0.1),
                    
                    const SizedBox(height: 24),
                    Text('PROFILE DETAILS', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 12),

                    // Editable Fields
                    _buildEditableInput(_nameCtrl, 'Full Name', Icons.person_outline_rounded),
                    
                    if (_role == 'admin' || _role == 'manager' || _role == 'user' || _role == 'driver')
                      _buildEditableInput(_emailCtrl, 'Email Address', Icons.alternate_email_rounded, keyboardType: TextInputType.emailAddress),
                      
                    if (_role == 'user')
                      _buildEditableInput(_phoneCtrl, 'Contact Phone', Icons.phone_android_rounded, keyboardType: TextInputType.phone),

                    if (_role == 'driver')
                      _buildEditableInput(_contactNumCtrl, 'Contact Phone', Icons.phone_android_rounded, keyboardType: TextInputType.phone),

                    const SizedBox(height: 16),

                    // Read-only specific metadata based on role
                    if (_role == 'manager') ...[
                      _buildReadOnlyItem('Employee ID', _profile['employeeId'] ?? 'N/A', Icons.pin_rounded),
                      _buildReadOnlyItem('Department', _profile['department'] ?? 'N/A', Icons.business_rounded),
                      _buildReadOnlyItem('Management Scope', (_profile['canManage'] as List?)?.join(', ').toUpperCase() ?? 'N/A', Icons.shield_outlined),
                    ],

                    if (_role == 'driver') ...[
                      _buildReadOnlyItem('Assigned Bus', _profile['assignedBus'] ?? 'NOT ASSIGNED', Icons.directions_bus_rounded),
                      _buildReadOnlyItem('Account Status', _profile['status'] ?? 'ACTIVE', Icons.info_outline_rounded),
                    ],

                    if (_role == 'user') ...[
                      _buildReadOnlyItem('Student ID / Enrollment', username, Icons.assignment_ind_rounded),
                      _buildReadOnlyItem('Course & Branch', _profile['courseName'] ?? 'N/A', Icons.school_rounded),
                      _buildReadOnlyItem('Father\'s Name', _profile['fatherName'] ?? 'N/A', Icons.family_restroom_rounded),
                      _buildReadOnlyItem('Father\'s Contact', _profile['fatherPhone'] ?? 'N/A', Icons.phone_enabled_rounded),
                      _buildReadOnlyItem('Pickup Point Stop', _profile['pickupPoint'] ?? 'N/A', Icons.location_on_rounded),
                    ],

                    const SizedBox(height: 24),
                    Text('SECURITY & ACTIONS', style: GoogleFonts.plusJakartaSans(color: Colors.deepPurpleAccent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 12),

                     // Change password action
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        onTap: _showPasswordResetDialog,
                        leading: const Icon(Icons.vpn_key_rounded, color: Colors.orangeAccent, size: 20),
                        title: Text('CHANGE ACCOUNT PASSWORD', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                      ),
                    ),

                    // Privacy Policy & Data Usage action
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        onTap: _showPrivacyPolicy,
                        leading: const Icon(Icons.security_rounded, color: Colors.tealAccent, size: 20),
                        title: Text('PRIVACY POLICY & DATA USAGE', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                      ),
                    ),

                    // About & System Info action
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: ListTile(
                        onTap: _showAboutDialog,
                        leading: const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
                        title: Text('ABOUT & SYSTEM INFORMATION', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                      ),
                    ),

                    const SizedBox(height: 24),
                    
                    // Save Changes Button
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfileChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: roleColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text('SAVE CHANGES', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEditableInput(TextEditingController ctrl, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          icon: Icon(icon, color: Colors.white38, size: 18),
          labelText: label.toUpperCase(),
          labelStyle: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildReadOnlyItem(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.02)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 18),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? 'N/A' : value, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
