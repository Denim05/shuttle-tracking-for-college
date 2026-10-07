import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';

/// Top floating network resilience banner:
/// Provides immediate, empathetic feedback when socket/internet disconnects or reconnects.
class NetworkStatusBanner extends StatelessWidget {
  const NetworkStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SocketService>(
      builder: (context, socketService, _) {
        final status = socketService.status;
        final quality = socketService.connectionQuality;

        // If completely healthy and connected, don't display
        if (status == SocketStatus.connected && quality != 'Poor') {
          return const SizedBox.shrink();
        }

        final bool isOffline = status == SocketStatus.disconnected || status == SocketStatus.error;
        final bool isConnecting = status == SocketStatus.connecting;

        Color bgColor;
        Color borderColor;
        Color textColor;
        IconData icon;
        String message;

        if (isOffline) {
          bgColor = const Color(0xFF3B1219).withValues(alpha: 0.94);
          borderColor = const Color(0xFFFF2E63).withValues(alpha: 0.4);
          textColor = const Color(0xFFFF6B8B);
          icon = Icons.wifi_off_rounded;
          message = 'No Connection • Showing Cached Data';
        } else if (isConnecting) {
          bgColor = const Color(0xFF2E220D).withValues(alpha: 0.94);
          borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.4);
          textColor = const Color(0xFFFBBF24);
          icon = Icons.sync_rounded;
          message = 'Reconnecting to Transit Fleet...';
        } else {
          // Poor network latency
          bgColor = const Color(0xFF2E220D).withValues(alpha: 0.94);
          borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.4);
          textColor = const Color(0xFFFBBF24);
          icon = Icons.network_check_rounded;
          message = 'Weak Signal • ${socketService.lastPingMs.value ?? 0}ms Latency';
        }

        return Semantics(
          label: 'Network Status: $message',
          liveRegion: true,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: textColor, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isOffline)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      socketService.checkAndReconnect(force: true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        'RETRY',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
