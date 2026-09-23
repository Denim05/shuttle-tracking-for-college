import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

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
    HapticFeedback.lightImpact();
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
      backgroundColor: widget.nested ? Colors.transparent : AppColors.bg,
      appBar: widget.nested
          ? null
          : AppBar(
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COMPLAINT BOX',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'Manage and resolve student concerns',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryLight),
                  onPressed: _loadComplaints,
                ),
              ],
            ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadComplaints,
                        color: AppColors.primary,
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          for (final f in ['all', 'pending', 'resolved', 'dismissed'])
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filterStatus = f);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _filterStatus == f ? _statusColor(f).withValues(alpha: 0.15) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _filterStatus == f ? _statusColor(f).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Text(
                  f.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    color: _filterStatus == f ? _statusColor(f) : AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'NO COMPLAINTS FOUND',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
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
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: AppShadows.card,
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
              Text(
                '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _categoryLabel(category),
            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            c['description'] ?? '',
            style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Flexible(child: _buildInfoChip(Icons.person_rounded, c['userName'] ?? 'User')),
              const SizedBox(width: 10),
              Flexible(child: _buildInfoChip(Icons.directions_bus_rounded, c['busNumber'] ?? 'Bus')),
            ],
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _btn('RESOLVE', AppColors.accentGreen, () => _updateStatus(c['_id'], 'resolved')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _btn('DISMISS', AppColors.textMuted, () => _updateStatus(c['_id'], 'dismissed')),
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: (i * 40).ms).slideY(begin: 0.06);
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 13),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) => switch (s) {
    'resolved' => AppColors.accentGreen,
    'dismissed' => AppColors.textMuted,
    'pending' => AppColors.warning,
    _ => AppColors.primary,
  };

  String _categoryLabel(String cat) => switch (cat) {
    'rash_driving' => 'Rash Driving',
    'late_arrival' => 'Late Arrival',
    'misconduct' => 'Driver Misconduct',
    'overloaded' => 'Bus Overloaded',
    _ => 'Other Transit Issue',
  };
}

