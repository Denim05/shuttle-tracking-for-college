import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/constants.dart';

/// Enterprise-grade report download & local file opening service.
/// Accurately handles:
/// - In-app binary streaming with status validation
/// - Automatic fallback between Render Cloud and Local Development server
/// - Local file persistence via path_provider
/// - Direct 1-tap file launching in Excel / Sheets / PDF viewer via open_file_plus
class ReportDownloadService {
  static final ReportDownloadService _instance = ReportDownloadService._internal();
  factory ReportDownloadService() => _instance;
  ReportDownloadService._internal();

  /// Resolves candidate URLs with smart local fallback for resilience
  List<String> _buildCandidateUrls({
    required String path,
    required String params,
  }) {
    final urls = <String>[];

    // 1. Primary configured URL (Production or Local)
    urls.add('${AppConstants.apiUrl}/manager/reports/$path?$params');

    // 2. Android emulator local fallback
    if (!kIsWeb && Platform.isAndroid) {
      final emuUrl = 'http://10.0.2.2:5000/api/manager/reports/$path?$params';
      if (!urls.contains(emuUrl)) urls.add(emuUrl);
    }

    // 3. Desktop / Web local fallback
    final localHostUrl = 'http://127.0.0.1:5000/api/manager/reports/$path?$params';
    if (!urls.contains(localHostUrl)) urls.add(localHostUrl);

    // 4. Production Cloud Render URL
    final renderUrl = 'https://smart-shuttle-backend-2h13.onrender.com/api/manager/reports/$path?$params';
    if (!urls.contains(renderUrl)) urls.add(renderUrl);

    return urls;
  }

  /// Downloads and opens Excel, CSV, or PDF reports with immediate visual feedback
  Future<void> downloadAndOpenReport(
    BuildContext context, {
    required String format, // 'excel', 'xlsx', 'csv', 'pdf', 'html'
    String? busId,
    String? date,
    String? shift,
  }) async {
    final targetDate = date ?? DateTime.now().toIso8601String().split('T')[0];
    final targetShift = shift ?? 'all';
    final safeDate = targetDate.replaceAll(RegExp(r'[^0-9-]'), '');

    String path;
    String queryExtra = '';
    String extension;
    String friendlyName;

    final isExcel = format == 'excel' || format == 'xlsx';
    final isCsv = format == 'csv';
    final isPdf = format == 'pdf';

    if (isExcel) {
      path = 'bus-trip-report/excel';
      extension = 'xlsx';
      friendlyName = 'Excel Workbook (.xlsx)';
    } else if (isCsv) {
      path = 'bus-trip-report';
      queryExtra = '&format=csv';
      extension = 'csv';
      friendlyName = 'CSV Spreadsheet (.csv)';
    } else {
      path = 'bus-trip-report/html';
      queryExtra = isPdf ? '&autoprint=true' : '';
      extension = 'html';
      friendlyName = isPdf ? 'Printable PDF Report' : 'Executive HTML Report';
    }

    final busParam = busId != null ? '&busId=$busId' : '';
    final queryParams = 'date=$targetDate&shift=$targetShift$queryExtra$busParam';
    final candidateUrls = _buildCandidateUrls(path: path, params: queryParams);

    // If PDF/HTML format, launching in browser gives the full print/save dialog experience
    if (isPdf || extension == 'html') {
      _showSnack(context, '📄 Opening $friendlyName in browser...', isError: false);
      for (final urlStr in candidateUrls) {
        try {
          final uri = Uri.parse(urlStr);
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) return;
        } catch (_) {}
      }
      if (context.mounted) {
        _showSnack(context, '⚠️ Could not open $friendlyName in browser', isError: true);
      }
      return;
    }

    // Direct Binary Download for Excel & CSV
    _showSnack(context, '⏳ Downloading $friendlyName...', isError: false, durationSeconds: 6);

    http.Response? successfulResponse;
    String? workingUrl;

    for (final urlStr in candidateUrls) {
      try {
        final uri = Uri.parse(urlStr);
        final res = await http.get(
          uri,
          headers: {
            'Accept': isExcel 
                ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/octet-stream'
                : 'text/csv, text/plain, */*',
          },
        ).timeout(const Duration(seconds: 15));

        // Accept 200 with non-empty content
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          // If response is accidentally an HTML error page, continue to fallback
          final isHtmlError = res.body.startsWith('<!DOCTYPE html>') || res.body.contains('Cannot GET');
          if (!isHtmlError) {
            successfulResponse = res;
            workingUrl = urlStr;
            break;
          }
        }
      } catch (err) {
        debugPrint('⚠️ Candidate URL failed ($urlStr): $err');
      }
    }

    if (successfulResponse == null) {
      // Fallback: try opening primary URL in external browser
      try {
        final fallbackUri = Uri.parse(candidateUrls.first);
        final launched = await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        if (launched) {
          if (context.mounted) {
            _showSnack(context, '🌐 Opened download link in external browser', isError: false);
          }
          return;
        }
      } catch (_) {}

      if (context.mounted) {
        _showSnack(context, '❌ Download failed. Server endpoint unreachable. Check connection.', isError: true);
      }
      return;
    }

    final bytes = successfulResponse.bodyBytes;
    final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
    final fileName = 'sistec_fleet_report_${safeDate}_$targetShift.$extension';

    try {
      // Get device storage directory
      Directory? dir;
      if (!kIsWeb && Platform.isAndroid) {
        // Tries Downloads or Documents directory
        try {
          dir = await getExternalStorageDirectory();
        } catch (_) {}
      }
      dir ??= await getApplicationDocumentsDirectory();

      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      debugPrint('✅ Saved report ($sizeKb KB) to: $filePath from: $workingUrl');

      if (!context.mounted) return;

      // Show success SnackBar with immediate "OPEN FILE" tactile action
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Downloaded: $fileName',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'File saved ($sizeKb KB) • Ready to open',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OPEN',
            textColor: const Color(0xFF34D399),
            onPressed: () async {
              try {
                final result = await OpenFilex.open(filePath);
                if (result.type != ResultType.done && context.mounted) {
                  _showSnack(context, 'Opening file: ${result.message}', isError: false);
                }
              } catch (e) {
                if (context.mounted) {
                  _showSnack(context, 'Could not open file: $e', isError: true);
                }
              }
            },
          ),
        ),
      );

      // Auto-open file for seamless executive user experience
      try {
        await OpenFilex.open(filePath);
      } catch (_) {}

    } catch (e) {
      debugPrint('Error saving file locally: $e');
      if (context.mounted) {
        _showSnack(context, 'File downloaded but could not be saved to disk: $e', isError: true);
      }
    }
  }

  void _showSnack(BuildContext context, String message, {required bool isError, int durationSeconds = 3}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: durationSeconds),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
