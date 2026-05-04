import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';

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
      // Assuming endpoint /admin/logs exists or fallback to empty
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
          // Mock data if real endpoint fails during dev
          _logs = [
            {'timestamp': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(), 'level': 'INFO', 'message': 'System Initialized', 'source': 'KERNEL'},
            {'timestamp': DateTime.now().subtract(const Duration(minutes: 12)).toIso8601String(), 'level': 'WARN', 'message': 'Connection latency detected', 'source': 'NETWORK'},
            {'timestamp': DateTime.now().subtract(const Duration(minutes: 25)).toIso8601String(), 'level': 'ERROR', 'message': 'Socket handshake failed: Auth mismatch', 'source': 'SOCKET'},
            {'timestamp': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(), 'level': 'INFO', 'message': 'Database maintenance completed', 'source': 'DB'},
          ];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('System Logs', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.blueAccent), onPressed: _fetchLogs),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              final Color color = _getLogColor(log['level']);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            log['level'] ?? 'INFO',
                            style: GoogleFonts.plusJakartaSans(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          _formatTime(log['timestamp']),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      log['message'] ?? '',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SOURCE: ${log['source'] ?? 'UNKNOWN'}',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1);
            },
          ),
    );
  }

  Color _getLogColor(String? level) {
    switch (level) {
      case 'ERROR': return Colors.redAccent;
      case 'WARN': return Colors.orangeAccent;
      case 'SUCCESS': return Colors.greenAccent;
      default: return Colors.blueAccent;
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '--:--';
    final date = DateTime.parse(timestamp).toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}

