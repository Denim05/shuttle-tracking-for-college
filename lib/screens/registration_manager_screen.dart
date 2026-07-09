import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/route_model.dart';

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

  Future<void> _approve(Map<String, dynamic> s) async {
    final String id = s['_id'];
    final String studentName = s['name'] ?? 'Student';
    final String studentId = s['studentId'] ?? '';
    final String? studentEmail = s['email'];

    final passwordCtrl = TextEditingController(text: 'SGI@$studentId');
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
              backgroundColor: const Color(0xFF0F1528),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF38EF7D), size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Approve Student',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
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
                    const SizedBox(height: 20),
                    Text(
                      'LOGIN PASSWORD (MIN 6 CHARS)',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: TextField(
                        controller: passwordCtrl,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter custom password',
                          hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white10, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
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
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                                      ? Colors.white.withOpacity(0.3)
                                      : Colors.white.withOpacity(0.8),
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
                                title: Text('✅ Account Created', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900)),
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
        color: const Color(0xFF2D5BFF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D5BFF).withOpacity(0.2)),
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
            border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
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
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
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
              color: sel ? const Color(0xFF2D5BFF).withOpacity(0.1) : Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: sel ? const Color(0xFF2D5BFF).withOpacity(0.35) : Colors.white.withOpacity(0.04)),
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
            border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                  color: _filterStatus == f ? _statusColor(f).withOpacity(0.15) : Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _filterStatus == f ? _statusColor(f).withOpacity(0.4) : Colors.white.withOpacity(0.05)),
                ),
                child: Text(f.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(color: _filterStatus == f ? _statusColor(f) : Colors.white38, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      ),
      // Bulk Actions Header (if there are any pending submissions)
      if (filtered.any((s) => s['status'] == 'pending')) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: Icon(
                  filtered.where((s) => s['status'] == 'pending').every((s) => _selectedSubmissionIds.contains(s['_id']))
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: Colors.blueAccent,
                  size: 18,
                ),
                label: Text(
                  filtered.where((s) => s['status'] == 'pending').every((s) => _selectedSubmissionIds.contains(s['_id']))
                      ? 'DESELECT ALL'
                      : 'SELECT ALL PENDING',
                  style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  final pendingIds = filtered
                      .where((s) => s['status'] == 'pending')
                      .map((s) => s['_id'] as String)
                      .toList();
                  
                  setState(() {
                    if (pendingIds.every((id) => _selectedSubmissionIds.contains(id))) {
                      _selectedSubmissionIds.removeAll(pendingIds);
                    } else {
                      _selectedSubmissionIds.addAll(pendingIds);
                    }
                  });
                },
              ),
              if (_selectedSubmissionIds.isNotEmpty)
                ElevatedButton.icon(
                  icon: const Icon(Icons.verified_rounded, size: 14, color: Colors.black),
                  label: Text('APPROVE SELECTED (${_selectedSubmissionIds.length})', 
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38EF7D),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _bulkApproveSelected,
                ),
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
        border: Border.all(color: color.withOpacity(0.15)),
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
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.person_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['name'] ?? '', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            Text('ID: ${s['studentId'] ?? ''}  •  📞 ${s['phone'] ?? ''}',
              style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
            child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
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
              color: Colors.blueAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.15)),
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
          _btn('REVERT TO PENDING (UNAPPROVE)', Colors.orangeAccent, () => _unapprove(s['_id'])),
        ],
        if (isPending) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _btn('APPROVE', const Color(0xFF38EF7D), () => _approve(s))),
            const SizedBox(width: 10),
            Expanded(child: _btn('REJECT', Colors.redAccent, () => _reject(s['_id']))),
          ]),
        ],
      ]),
    ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.05);
  }

  Color _statusColor(String s) => switch (s) {
    'approved' => const Color(0xFF38EF7D),
    'rejected' => Colors.redAccent,
    'pending'  => const Color(0xFFFFB347),
    _          => const Color(0xFF2D5BFF),
  };

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 0),
    child: Text(t, style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
  );

  Widget _inputField(String hint, TextEditingController ctrl, {int maxLines = 1}) => Container(
    decoration: BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
    child: TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(hintText: hint, hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 13), border: InputBorder.none, contentPadding: const EdgeInsets.all(16)),
    ),
  );

  Widget _btn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.3))),
      child: Center(child: Text(label, style: GoogleFonts.plusJakartaSans(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8))),
    ),
  );
}


