import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

class ComplaintManagerScreen extends StatefulWidget {
  final bool nested;
  const ComplaintManagerScreen({super.key, this.nested = false});

  @override
  State<ComplaintManagerScreen> createState() => _ComplaintManagerScreenState();
}

class _ComplaintManagerScreenState extends State<ComplaintManagerScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _complaints = [];
  bool _isLoading = true;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadComplaints();
  }

  Future<void> _loadComplaints() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.get('complaints');
      if (mounted) {
        setState(() {
          _complaints = data as List;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _api.put('complaints/$id', {'status': status});
      _loadComplaints();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterStatus == 'all'
        ? _complaints
        : _complaints.where((c) => c['status'] == _filterStatus).toList();

    return Scaffold(
      backgroundColor: widget.nested ? Colors.transparent : const Color(0xFF121212),
      appBar: widget.nested
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF121212),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COMPLAINT BOX',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    'Manage and resolve student concerns',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.blueAccent),
                  onPressed: _loadComplaints,
                ),
              ],
            ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D5BFF)))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadComplaints,
                        color: const Color(0xFF2D5BFF),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => _buildComplaintCard(filtered[i], i),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        children: [
          for (final f in ['all', 'pending', 'resolved', 'dismissed'])
            GestureDetector(
              onTap: () => setState(() => _filterStatus = f),
              child: AnimatedContainer(
                duration: 200.ms,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _filterStatus == f ? _statusColor(f).withOpacity(0.15) : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _filterStatus == f ? _statusColor(f).withOpacity(0.4) : Colors.white.withOpacity(0.05),
                  ),
                ),
                child: Text(
                  f.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    color: _filterStatus == f ? _statusColor(f) : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: Colors.white10, size: 64),
          const SizedBox(height: 16),
          Text(
            'NO COMPLAINTS FOUND',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white24,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintCard(dynamic c, int i) {
    final status = c['status'] ?? 'pending';
    final color = _statusColor(status);
    final category = c['category'] ?? 'other';
    final timestamp = DateTime.parse(c['createdAt'] ?? DateTime.now().toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(color: color, fontSize: 8, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _categoryLabel(category),
            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            c['description'] ?? '',
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildInfoChip(Icons.person_rounded, c['userName'] ?? 'User'),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.directions_bus_rounded, c['busNumber'] ?? 'Bus'),
            ],
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _btn('RESOLVE', const Color(0xFF38EF7D), () => _updateStatus(c['_id'], 'resolved')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _btn('DISMISS', Colors.white24, () => _updateStatus(c['_id'], 'dismissed')),
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: (i * 50).ms).slideY(begin: 0.1);
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.blueAccent, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) => switch (s) {
    'resolved' => const Color(0xFF38EF7D),
    'dismissed' => Colors.white24,
    'pending' => const Color(0xFFFFB347),
    _ => const Color(0xFF2D5BFF),
  };

  String _categoryLabel(String cat) => switch (cat) {
    'rash_driving' => 'Rash Driving',
    'late_arrival' => 'Late Arrival',
    'misconduct' => 'Driver Misconduct',
    'overloaded' => 'Bus Overloaded',
    _ => 'Other Issue',
  };
}
