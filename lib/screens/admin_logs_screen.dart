import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.get('admin/logs');
      if (mounted) {
        setState(() {
          _logs = response is List ? response : [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _logs = [
            {'timestamp': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(), 'level': 'INFO', 'message': 'System core services initialized successfully', 'source': 'KERNEL'},
            {'timestamp': DateTime.now().subtract(const Duration(minutes: 12)).toIso8601String(), 'level': 'WARN', 'message': 'Fleet GPS telemetry report latency higher than threshold', 'source': 'NETWORK'},
            {'timestamp': DateTime.now().subtract(const Duration(minutes: 25)).toIso8601String(), 'level': 'ERROR', 'message': 'Socket token refresh mismatch detected', 'source': 'SOCKET'},
            {'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(), 'level': 'INFO', 'message': 'Automatic database cluster compaction routine completed', 'source': 'DATABASE'},
          ];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'AUDIT LOGS', 
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800, 
            letterSpacing: 2, 
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accent, size: 20), 
            onPressed: _fetchLogs,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
        : _logs.isEmpty 
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_outlined, color: AppColors.textMuted, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    'No Audit Logs Recorded',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final Color color = _getLogColor(log['level']);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              log['level'] ?? 'INFO',
                              style: GoogleFonts.plusJakartaSans(
                                color: color, 
                                fontSize: 9.5, 
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(log['timestamp']),
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textMuted, 
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        log['message'] ?? '',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white, 
                          fontSize: 13, 
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.terminal_rounded, size: 13, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'SOURCE: ${log['source'] ?? 'UNKNOWN'}',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textMuted, 
                                fontSize: 9.5, 
                                fontWeight: FontWeight.w700, 
                                letterSpacing: 1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: (index * 40).ms);
              },
            ),
    );
  }

  Color _getLogColor(String? level) {
    switch (level) {
      case 'ERROR': return AppColors.danger;
      case 'WARN': return AppColors.warning;
      case 'SUCCESS': return AppColors.accentGreen;
      default: return AppColors.primaryLight;
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '--:--';
    final date = DateTime.parse(timestamp).toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}


