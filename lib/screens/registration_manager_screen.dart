import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';
import '../theme/app_theme.dart';

String generateSecureRandomPassword({int length = 10}) {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const digits = '23456789';
  const symbols = '!@#\$%&*?';
  
  final rand = Random.secure();
  final chars = <String>[
    upper[rand.nextInt(upper.length)],
    lower[rand.nextInt(lower.length)],
    digits[rand.nextInt(digits.length)],
    symbols[rand.nextInt(symbols.length)],
  ];
  
  const all = upper + lower + digits + symbols;
  for (int i = chars.length; i < length; i++) {
    chars.add(all[rand.nextInt(all.length)]);
  }
  
  chars.shuffle(rand);
  return chars.join();
}

class RegistrationManagerScreen extends StatefulWidget {
  final List<RouteModel> routes;
  const RegistrationManagerScreen({super.key, required this.routes});

  @override
  State<RegistrationManagerScreen> createState() => _RegistrationManagerScreenState();
}

class _RegistrationManagerScreenState extends State<RegistrationManagerScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tab;

  // Form state
  Map<String, dynamic>? _activeForm;
  String? _shareUrl;
  bool _formLoading = true;
  bool _creating = false;
  final _titleCtrl = TextEditingController(text: 'SISTecChalo Bus Registration');
  final _descCtrl  = TextEditingController(text: 'Register for the college bus service by filling in this form.');
  List<RouteModel> _selectedRoutes = [];

  // Submissions state
  List<dynamic> _submissions = [];
  bool _subsLoading = true;
  String _filterStatus = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedSubmissionIds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadForm();
    _loadSubmissions();
  }

  @override
  void dispose() {
    _tab.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadForm() async {
    setState(() => _formLoading = true);
    try {
      final data = await _api.get('manager/registration-form');
      if (mounted) setState(() {
        _activeForm = data['form'];
        _shareUrl   = data['shareUrl'];
        _formLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _formLoading = false);
    }
  }

  Future<void> _loadSubmissions() async {
    setState(() => _subsLoading = true);
    try {
      final data = await _api.get('manager/registrations');
      if (mounted) setState(() {
        _submissions = data as List;
        _selectedSubmissionIds.clear(); // Clear selections on load
        _subsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _subsLoading = false);
    }
  }

  Future<void> _createForm() async {
    if (_selectedRoutes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one route'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _creating = true);
    try {
      final routeOptions = _selectedRoutes.map((r) => {'routeId': r.id, 'routeName': r.name}).toList();
      final stopOptions  = _selectedRoutes.map((r) => {
        'routeId': r.id,
        'stops': r.stops.map((s) => s['name']?.toString() ?? '').where((s) => s.isNotEmpty).toList(),
      }).toList();

      final data = await _api.post('manager/registration-form', {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'routeOptions': routeOptions,
        'stopOptions': stopOptions,
      });
      if (mounted) {
        setState(() {
          _activeForm = data['form'];
          _shareUrl   = data['shareUrl'];
          _creating   = false;
        });
        _tab.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _closeForm() async {
    if (_activeForm == null) return;
    try {
      await _api.put('manager/registration-form/${_activeForm!['_id']}/close', {});
      if (mounted) setState(() { _activeForm = null; _shareUrl = null; });
    } catch (_) {}
  }

  Future<void> _unapprove(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Revert Approval?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('This will delete the student\'s active user account and put their submission back into the pending list.', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('UNAPPROVE', style: GoogleFonts.plusJakartaSans(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _subsLoading = true);
    try {
      await _api.put('manager/registrations/$id/unapprove', {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Approval reverted and user account deleted successfully.'), backgroundColor: Colors.orange),
      );
      _loadSubmissions();
    } catch (e) {
      setState(() => _subsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _resendEmail(String id, String? currentEmail, String studentName) async {
    final emailCtrl = TextEditingController(text: currentEmail ?? '');
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F1528),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.mark_email_read_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 10),
            Text('Resend Credentials', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send official welcome and bus tracking login details to $studentName:', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Enter student email address',
                  hintStyle: TextStyle(color: Colors.white30),
                  prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF38BDF8), size: 18),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send_rounded, size: 14),
            label: Text('SEND EMAIL', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: Colors.black),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final email = emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a valid email address.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dispatching credentials email to $email...'), backgroundColor: const Color(0xFF4F46E5), behavior: SnackBarBehavior.floating),
      );
      final res = await _api.post('manager/registrations/$id/resend-email', {
        'email': email,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Email dispatched successfully!'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadSubmissions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send email: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _bulkApproveSelected() async {
    if (_selectedSubmissionIds.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Approve Selected?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to bulk approve all ${_selectedSubmissionIds.length} selected students? Their user accounts will be created automatically with standard passwords (SGI@[Enrollment ID]).', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('APPROVE ALL', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF38EF7D), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _subsLoading = true);
    try {
      final response = await _api.post('manager/registrations/bulk-approve', {
        'ids': _selectedSubmissionIds.toList(),
      });
      
      final approvedCount = response['approvedCount'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully approved $approvedCount students!'),
          backgroundColor: const Color(0xFF38EF7D),
        ),
      );
      
      setState(() {
        _selectedSubmissionIds.clear();
      });
      _loadSubmissions();
    } catch (e) {
      setState(() => _subsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedSubmissionIds.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151D30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text('Delete Selected?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete ${_selectedSubmissionIds.length} selected registration(s)? Any created student login accounts will also be removed.',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('DELETE ALL', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _subsLoading = true);
    try {
      final response = await _api.post('manager/registrations/bulk-delete', {
        'ids': _selectedSubmissionIds.toList(),
      });
      
      final deletedCount = response['deletedCount'] ?? _selectedSubmissionIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully deleted $deletedCount registrations!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      
      setState(() {
        _selectedSubmissionIds.clear();
      });
      _loadSubmissions();
    } catch (e) {
      setState(() => _subsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _deleteSubmission(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151D30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text('Delete Registration?', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text('Permanently remove this registration submission and any associated account?', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: Colors.white38))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('DELETE', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _api.delete('manager/registrations/$id');
      _loadSubmissions();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration deleted'), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _approve(Map<String, dynamic> s) async {
    final String id = s['_id'];
    final String studentName = s['name'] ?? 'Student';
    final String studentId = s['studentId'] ?? '';
    final String? studentEmail = s['email'];

    final passwordCtrl = TextEditingController(text: generateSecureRandomPassword());
    final emailCtrl = TextEditingController(text: studentEmail ?? '');
    bool sendEmail = emailCtrl.text.trim().isNotEmpty;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              backgroundColor: const Color(0xFF0F1528),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF38EF7D), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Approve Student',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assign login details for $studentName.',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'LOGIN PASSWORD',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              passwordCtrl.text = generateSecureRandomPassword();
                            });
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.shuffle_rounded, size: 12, color: AppColors.accent),
                              const SizedBox(width: 4),
                              Text(
                                'RE-GENERATE',
                                style: GoogleFonts.plusJakartaSans(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                      ),
                      child: TextField(
                        controller: passwordCtrl,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        decoration: InputDecoration(
                          hintText: 'Enter password',
                          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white10, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.shuffle_rounded, color: AppColors.accent, size: 17),
                                tooltip: 'New Random Password',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () {
                                  setDialogState(() {
                                    passwordCtrl.text = generateSecureRandomPassword();
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 17),
                                tooltip: 'Copy Password',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: passwordCtrl.text));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password copied to clipboard!'), backgroundColor: AppColors.primary),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: Color(0xFF38EF7D), size: 12),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'High-entropy (A-Z, a-z, 0-9 & symbols)',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'STUDENT EMAIL (FOR CREDENTIALS DELIVERY)',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                        onChanged: (val) {
                          setDialogState(() {
                            sendEmail = val.trim().isNotEmpty;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Enter student email',
                          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white10, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: sendEmail,
                            activeColor: Colors.blueAccent,
                            checkColor: Colors.white,
                            onChanged: emailCtrl.text.trim().isEmpty
                                ? null
                                : (val) {
                                    setDialogState(() {
                                      sendEmail = val ?? false;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Email credentials to student',
                                style: GoogleFonts.plusJakartaSans(
                                  color: emailCtrl.text.trim().isEmpty
                                      ? Colors.white.withValues(alpha: 0.3)
                                      : Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (emailCtrl.text.trim().isNotEmpty)
                                Text(
                                  emailCtrl.text.trim(),
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white30, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    'CANCEL',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontWeight: FontWeight.w900, fontSize: 11),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final password = passwordCtrl.text.trim();
                          if (password.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password must be at least 6 characters.'), backgroundColor: Colors.redAccent),
                            );
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                          });
                          try {
                            final data = await _api.put('manager/registrations/$id/approve', {
                              'password': password,
                              'sendEmail': sendEmail,
                              'email': emailCtrl.text.trim(),
                            });
                            Navigator.pop(dialogContext); // Close first dialog
                            
                            // Show success summary
                            if (!mounted) return;
                            final msg = data['message'] ?? 'Approved';
                            showDialog(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                backgroundColor: const Color(0xFF1E1E1E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF34D399).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Text('Account Created', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                  ],
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(msg, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, height: 1.5)),
                                    const SizedBox(height: 16),
                                    _credRow('Username', data['username'] ?? ''),
                                    const SizedBox(height: 8),
                                    _credRow('Password', data['password'] ?? ''),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: 'Username: ${data['username']}\nPassword: ${data['password']}'));
                                      Navigator.pop(dialogCtx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Credentials copied!'), backgroundColor: Color(0xFF2D5BFF)),
                                      );
                                    },
                                    child: Text('COPY & CLOSE', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontWeight: FontWeight.w900)),
                                  ),
                                ],
                              ),
                            );
                            _loadSubmissions();
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38EF7D),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Text('APPROVE', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 11)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _reject(String id) async {
    try {
      await _api.put('manager/registrations/$id/reject', {'note': 'Rejected by manager'});
      _loadSubmissions();
    } catch (_) {}
  }

  Widget _credRow(String label, String val) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D5BFF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D5BFF).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Text('$label: ', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700)),
        Expanded(child: Text(val, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('REGISTRATION PORTAL', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
          Text('Manage student registrations', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10)),
        ]),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 11),
          tabs: const [Tab(text: 'FORM & LINK'), Tab(text: 'SUBMISSIONS')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_buildFormTab(), _buildSubmissionsTab()],
      ),
    );
  }

  Widget _buildFormTab() {
    if (_formLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF2D5BFF)));

    return ListView(padding: const EdgeInsets.all(20), children: [
      // Active form card
      if (_activeForm != null && _shareUrl != null) ...[
        _sectionLabel('ACTIVE FORM'),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
              ).animate(onPlay: (c) => c.repeat()).fadeOut(duration: 1.seconds),
              const SizedBox(width: 8),
              Text('FORM ACTIVE', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ]),
            const SizedBox(height: 12),
            Text(_activeForm!['title'] ?? '', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${_activeForm!['submissionCount'] ?? 0} submissions received',
              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            // Share link
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(children: [
                const Icon(Icons.link_rounded, color: Color(0xFF2D5BFF), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_shareUrl!, style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 11), overflow: TextOverflow.ellipsis)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _btn('COPY LINK', const Color(0xFF2D5BFF), () {
                Clipboard.setData(ClipboardData(text: _shareUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('Link copied! Share in WhatsApp/college groups.'),
                    backgroundColor: const Color(0xFF2D5BFF), behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
              })),
              const SizedBox(width: 10),
              Expanded(child: _btn('CLOSE FORM', Colors.redAccent, _closeForm)),
            ]),
          ]),
        ).animate().fadeIn().slideY(begin: 0.05),
        const SizedBox(height: 32),
      ],

      // Create new form
      _sectionLabel(_activeForm != null ? 'CREATE NEW FORM (REPLACES ACTIVE)' : 'CREATE REGISTRATION FORM'),
      const SizedBox(height: 12),
      _inputField('Form Title', _titleCtrl),
      const SizedBox(height: 12),
      _inputField('Description', _descCtrl, maxLines: 2),
      const SizedBox(height: 20),
      _sectionLabel('SELECT ROUTES TO INCLUDE'),
      const SizedBox(height: 10),
      ...widget.routes.map((r) {
        final sel = _selectedRoutes.any((s) => s.id == r.id);
        return GestureDetector(
          onTap: () => setState(() { if (sel) _selectedRoutes.removeWhere((s) => s.id == r.id); else _selectedRoutes.add(r); }),
          child: AnimatedContainer(
            duration: 200.ms,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFF2D5BFF).withValues(alpha: 0.1) : Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sel ? const Color(0xFF2D5BFF).withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.04)),
            ),
            child: Row(children: [
              Icon(Icons.alt_route_rounded, color: sel ? const Color(0xFF2D5BFF) : Colors.white24, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Text(r.name, style: GoogleFonts.plusJakartaSans(color: sel ? Colors.white : Colors.white60, fontWeight: FontWeight.w700, fontSize: 13))),
              if (sel) const Icon(Icons.check_circle_rounded, color: Colors.blueAccent, size: 18),
            ]),
          ),
        );
      }),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _creating ? null : _createForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D5BFF),
            padding: const EdgeInsets.all(18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: _creating
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('GENERATE FORM & LINK', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
        ),
      ),
    ]);
  }

  Widget _buildSubmissionsTab() {
    final filtered = _submissions.where((s) {
      final matchesStatus = _filterStatus == 'all' || s['status'] == _filterStatus;
      if (!matchesStatus) return false;
      if (_searchQuery.trim().isEmpty) return true;
      
      final q = _searchQuery.trim().toLowerCase();
      final name = (s['name'] ?? '').toString().toLowerCase();
      final studentId = (s['studentId'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      final routeName = (s['routeName'] ?? '').toString().toLowerCase();
      final pickupStop = (s['pickupStop'] ?? '').toString().toLowerCase();
      
      return name.contains(q) ||
          studentId.contains(q) ||
          phone.contains(q) ||
          routeName.contains(q) ||
          pickupStop.contains(q);
    }).toList();

    return Column(children: [
      // Search Bar
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by name, ID, phone, route...',
              hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                      onPressed: () {
                        setState(() {
                          _searchCtrl.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
      // Filter chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(children: [
          for (final f in ['all', 'pending', 'approved', 'rejected'])
            GestureDetector(
              onTap: () => setState(() => _filterStatus = f),
              child: AnimatedContainer(
                duration: 200.ms,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _filterStatus == f ? _statusColor(f).withValues(alpha: 0.15) : Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _filterStatus == f ? _statusColor(f).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05)),
                ),
                child: Text(f.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(color: _filterStatus == f ? _statusColor(f) : Colors.white38, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      ),
      // Bulk Actions Header (if there are any pending submissions)
      if (filtered.any((s) => s['status'] == 'pending') || _selectedSubmissionIds.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: Icon(
                      filtered.where((s) => s['status'] == 'pending').isNotEmpty &&
                              filtered.where((s) => s['status'] == 'pending').every((s) => _selectedSubmissionIds.contains(s['_id']))
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    label: Text(
                      filtered.where((s) => s['status'] == 'pending').isNotEmpty &&
                              filtered.where((s) => s['status'] == 'pending').every((s) => _selectedSubmissionIds.contains(s['_id']))
                          ? 'DESELECT ALL'
                          : 'SELECT ALL PENDING',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      final pendingIds = filtered
                          .where((s) => s['status'] == 'pending')
                          .map((s) => s['_id'] as String)
                          .toList();
                      
                      setState(() {
                        if (pendingIds.isNotEmpty && pendingIds.every((id) => _selectedSubmissionIds.contains(id))) {
                          _selectedSubmissionIds.removeAll(pendingIds);
                        } else {
                          _selectedSubmissionIds.addAll(pendingIds);
                        }
                      });
                    },
                  ),
                  if (_selectedSubmissionIds.isNotEmpty)
                    Text(
                      '${_selectedSubmissionIds.length} Selected',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              if (_selectedSubmissionIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.verified_rounded, size: 15, color: Colors.white),
                        label: Text(
                          'APPROVE (${_selectedSubmissionIds.length})', 
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.white, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                        ),
                        onPressed: _bulkApproveSelected,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever_rounded, size: 15, color: Colors.white),
                        label: Text(
                          'DELETE (${_selectedSubmissionIds.length})', 
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.white, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                          shadowColor: Colors.redAccent.withValues(alpha: 0.4),
                        ),
                        onPressed: _bulkDeleteSelected,
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1),
              ],
            ],
          ),
        ),
      ],
      if (_subsLoading)
        const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF2D5BFF))))
      else if (filtered.isEmpty)
        Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inbox_rounded, color: Colors.white24, size: 50),
          const SizedBox(height: 12),
          Text('NO SUBMISSIONS', style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ])))
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSubmissions,
            color: const Color(0xFF2D5BFF),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              itemCount: filtered.length,
              itemBuilder: (context, i) => _buildSubmissionCard(filtered[i], i),
            ),
          ),
        ),
    ]);
  }

  Widget _buildSubmissionCard(dynamic s, int i) {
    final status = s['status'] ?? 'pending';
    final color  = _statusColor(status);
    final isPending = status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (isPending)
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedSubmissionIds.contains(s['_id'])) {
                    _selectedSubmissionIds.remove(s['_id']);
                  } else {
                    _selectedSubmissionIds.add(s['_id']);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  _selectedSubmissionIds.contains(s['_id'])
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _selectedSubmissionIds.contains(s['_id']) ? const Color(0xFF38EF7D) : Colors.white30,
                  size: 22,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.person_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['name'] ?? '', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text('ID: ${s['studentId'] ?? ''}  •  ${s['phone'] ?? ''}',
              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10)),
            if (s['email'] != null && s['email'].toString().isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.email_outlined, color: Color(0xFF38BDF8), size: 11),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s['email'],
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFF38BDF8).withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ])),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.25))),
                child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
              ),
              if (s['emailSent'] == true) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mark_email_read_rounded, color: Color(0xFF10B981), size: 10),
                      const SizedBox(width: 3),
                      Text('EMAILED', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF10B981), fontSize: 7, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.alt_route_rounded, color: Color(0xFF2D5BFF), size: 13),
          const SizedBox(width: 6),
          Expanded(child: Text('${s['routeName'] ?? ''}  →  ${s['pickupStop'] ?? ''}',
            style: GoogleFonts.plusJakartaSans(color: Colors.white60, fontSize: 12))),
        ]),
        if (status == 'approved' && s['generatedUsername'] != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.15)),
            ),
            child: Row(children: [
              const Icon(Icons.key_rounded, color: Colors.blueAccent, size: 14),
              const SizedBox(width: 8),
              Text('${s['generatedUsername']} / ${s['generatedPassword']}',
                style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => Clipboard.setData(ClipboardData(text: 'Username: ${s['generatedUsername']}\nPassword: ${s['generatedPassword']}')),
                child: const Icon(Icons.copy_rounded, color: Colors.blueAccent, size: 16),
              ),
            ]),
          ),
        ],
        if (status == 'approved') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _btn('RESEND EMAIL', const Color(0xFF38BDF8), () => _resendEmail(s['_id'], s['email'], s['name'] ?? 'Student'), icon: Icons.mark_email_read_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _btn('REVERT', Colors.orangeAccent, () => _unapprove(s['_id']), icon: Icons.history_rounded),
              ),
              const SizedBox(width: 8),
              _iconBtn(Icons.delete_outline_rounded, Colors.redAccent, () => _deleteSubmission(s['_id'])),
            ],
          ),
        ],
        if (status == 'rejected') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _btn('APPROVE', const Color(0xFF10B981), () => _approve(s), icon: Icons.check_circle_outline_rounded),
              ),
              const SizedBox(width: 8),
              _iconBtn(Icons.delete_outline_rounded, Colors.redAccent, () => _deleteSubmission(s['_id'])),
            ],
          ),
        ],
        if (isPending) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _btn('APPROVE', const Color(0xFF10B981), () => _approve(s), icon: Icons.verified_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _btn('DELETE', Colors.redAccent, () => _deleteSubmission(s['_id']), icon: Icons.delete_outline_rounded)),
          ]),
        ],
      ]),
    ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.05);
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(child: Icon(icon, color: color, size: 18)),
    ),
  );

  Color _statusColor(String s) => switch (s) {
    'approved' => const Color(0xFF10B981),
    'rejected' => Colors.redAccent,
    'pending'  => const Color(0xFFFFB347),
    _          => AppColors.primary,
  };

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 0),
    child: Text(t, style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
  );

  Widget _inputField(String hint, TextEditingController ctrl, {int maxLines = 1}) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13), border: InputBorder.none, contentPadding: const EdgeInsets.all(16)),
    ),
  );

  Widget _btn(String label, Color color, VoidCallback onTap, {IconData? icon}) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
          ],
          Text(
            label, 
            style: GoogleFonts.plusJakartaSans(
              color: color, 
              fontWeight: FontWeight.w900, 
              fontSize: 11, 
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    ),
  );
}


