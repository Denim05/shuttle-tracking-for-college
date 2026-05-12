import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  final _titleCtrl = TextEditingController(text: 'ChaloCampus Bus Registration');
  final _descCtrl  = TextEditingController(text: 'Register for the college bus service by filling in this form.');
  List<RouteModel> _selectedRoutes = [];

  // Submissions state
  List<dynamic> _submissions = [];
  bool _subsLoading = true;
  String _filterStatus = 'all';

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

  Future<void> _approve(String id) async {
    try {
      final data = await _api.put('manager/registrations/$id/approve', {});
      if (!mounted) return;
      final msg = data['message'] ?? 'Approved';
      showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('✅ Account Created', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, height: 1.5)),
          const SizedBox(height: 16),
          _credRow('Username', data['username'] ?? ''),
          const SizedBox(height: 8),
          _credRow('Password', data['password'] ?? ''),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: 'Username: ${data['username']}\nPassword: ${data['password']}'));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Credentials copied!'), backgroundColor: Color(0xFF2D5BFF)));
            },
            child: Text('COPY & CLOSE', style: GoogleFonts.plusJakartaSans(color: Colors.blueAccent, fontWeight: FontWeight.w900)),
          ),
        ],
      ));
      _loadSubmissions();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
    }
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
    final filtered = _filterStatus == 'all'
        ? _submissions
        : _submissions.where((s) => s['status'] == _filterStatus).toList();

    return Column(children: [
      // Filter chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
        if (isPending) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _btn('APPROVE', const Color(0xFF38EF7D), () => _approve(s['_id']))),
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

