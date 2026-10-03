import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Professional, resilient back-navigation handler for root screens and dashboards.
///
/// Prevents accidental app exit and eliminates Android 13/14/15 window freeze issues.
/// Supports hierarchical back actions (e.g., returning to the first tab, retracting sheets)
/// before offering a smooth 2-second double-tap-to-exit confirmation.
class DashboardBackScope extends StatefulWidget {
  final Widget child;
  final bool Function()? onWillHandleBack;
  final String exitMessage;

  const DashboardBackScope({
    super.key,
    required this.child,
    this.onWillHandleBack,
    this.exitMessage = 'Press back again to exit',
  });

  @override
  State<DashboardBackScope> createState() => _DashboardBackScopeState();
}

class _DashboardBackScopeState extends State<DashboardBackScope> {
  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 1. If any nested Navigator or dialog can pop, pop it first
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }

        // 2. Allow dashboard to handle internal hierarchical back (e.g., tabs, sheets)
        if (widget.onWillHandleBack != null) {
          final handled = widget.onWillHandleBack!();
          if (handled) return;
        }

        // 3. Double-tap to exit confirmation (2-second window)
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    widget.exitMessage,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            ),
          );
          return;
        }

        // Cleanly and gracefully minimize/exit the app without freezing the process
        SystemNavigator.pop();
      },
      child: widget.child,
    );
  }
}
