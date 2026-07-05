import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/constants.dart';

// ─── Connection Status Enum ───────────────────────────────────────────────────

enum SocketStatus { connecting, connected, disconnected, error }

// ─── Socket Service ───────────────────────────────────────────────────────────

/// ChangeNotifier-backed Socket.io wrapper for SISTecChalo.
///
/// - [status]           enum for richer UI reactions
/// - [connectionStatus] ValueNotifier for backward compatibility
/// - [lastDataReceived] ValueNotifier for pulse animation
/// - [lastSOSAlert]     ValueNotifier — any widget can react to SOS
/// - [lastPingMs]       ValueNotifier — real-time latency display
/// - [connectionQuality] derived string: Excellent / Good / Poor / Offline
/// - SOS listener is permanent (set up in initSocket, not replaceable)
/// - [pingServer] emits custom ping and measures pong round-trip
class SocketService with ChangeNotifier {
  io.Socket? _socket;
  SocketStatus _status = SocketStatus.disconnected;

  // ─── Public ValueNotifiers ───────────────────────────────────────────────

  final ValueNotifier<bool>                  connectionStatus = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?>             lastDataReceived = ValueNotifier<DateTime?>(null);
  final ValueNotifier<Map<String, dynamic>?> lastSOSAlert     = ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<int?>                  lastPingMs       = ValueNotifier<int?>(null);

  // ─── Internal ────────────────────────────────────────────────────────────

  int _pingStartMs = 0;
  final List<Function(dynamic)> _sosCallbacks = [];

  // ─── Getters ─────────────────────────────────────────────────────────────

  SocketStatus get status      => _status;
  bool         get isConnected => _status == SocketStatus.connected;
  io.Socket?   get socket      => _socket;

  String get connectionQuality {
    if (!isConnected) return 'Offline';
    final ping = lastPingMs.value;
    if (ping == null) return 'Unknown';
    if (ping < 100)   return 'Excellent';
    if (ping < 300)   return 'Good';
    return 'Poor';
  }

  Color get connectionQualityColor {
    switch (connectionQuality) {
      case 'Excellent': return const Color(0xFF00F0FF);
      case 'Good':      return const Color(0xFF38EF7D);
      case 'Poor':      return const Color(0xFFF59E0B);
      default:          return const Color(0xFFFF2E63);
    }
  }

  // ─── Init ────────────────────────────────────────────────────────────────

  void initSocket() {
    if (_socket != null && _socket!.connected) {
      debugPrint('⚠️ Socket already connected — reusing.');
      return;
    }

    _setStatus(SocketStatus.connecting);
    debugPrint('🔌 SISTecChalo: connecting to ${AppConstants.baseUrl}');

    _socket = io.io(AppConstants.baseUrl, <String, dynamic>{
      'transports'           : ['websocket', 'polling'],
      'autoConnect'          : true,
      'forceNew'             : false,
      'reconnection'         : true,
      'reconnectionAttempts' : 15,
      'reconnectionDelay'    : 2000,
      'reconnectionDelayMax' : 8000,
      'timeout'              : 20000,
    });

    _socket!
      ..on('connect',           _onConnect)
      ..on('reconnect',         _onReconnect)
      ..on('disconnect',        _onDisconnect)
      ..on('connect_error',     _onConnectError)
      ..on('reconnect_attempt', (_) => _setStatus(SocketStatus.connecting))
      ..on('error',  (data) => debugPrint('❌ Socket error: $data'))
      // ── Permanent SOS listener — not replaceable ──────────────────────
      ..on('sosAlert', _onSOSAlertInternal)
      // ── Pong for latency measurement ──────────────────────────────────
      ..on('pong', (_) {
          lastPingMs.value = DateTime.now().millisecondsSinceEpoch - _pingStartMs;
          debugPrint('🏓 Ping: ${lastPingMs.value} ms');
        });
  }

  // ─── SOS Internal Handler ────────────────────────────────────────────────

  void _onSOSAlertInternal(dynamic data) {
    try {
      final Map<String, dynamic> parsed = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
      lastSOSAlert.value = parsed;
      debugPrint('🆘 SOS Alert received: $parsed');
      for (final cb in _sosCallbacks) {
        cb(parsed);
      }
    } catch (e) {
      debugPrint('SOS parse error: $e');
    }
  }

  // ─── Event Handlers ──────────────────────────────────────────────────────

  void _onConnect(_) {
    connectionStatus.value = true;
    _setStatus(SocketStatus.connected);
    debugPrint('✅ SISTecChalo: Socket connected (id: ${_socket?.id})');
    pingServer(); // measure initial latency
  }

  void _onReconnect(_) {
    connectionStatus.value = true;
    _setStatus(SocketStatus.connected);
    debugPrint('♻️ SISTecChalo: Socket reconnected');
    pingServer();
  }

  void _onDisconnect(dynamic reason) {
    connectionStatus.value = false;
    _setStatus(SocketStatus.disconnected);
    debugPrint('⚠️ SISTecChalo: Disconnected. Reason: $reason');
  }

  void _onConnectError(dynamic data) {
    connectionStatus.value = false;
    _setStatus(SocketStatus.error);
    debugPrint('❌ SISTecChalo: Connect error: $data');
  }

  void _setStatus(SocketStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  // ─── Manual Reconnect ────────────────────────────────────────────────────

  void reconnect() {
    if (_socket == null) {
      initSocket();
    } else if (_socket!.disconnected) {
      _socket!.connect();
    }
  }

  // ─── Ping / Latency ──────────────────────────────────────────────────────

  void pingServer() {
    if (!isConnected) return;
    _pingStartMs = DateTime.now().millisecondsSinceEpoch;
    _socket?.emit('ping');
  }

  // ─── Listener Registration (idempotent) ─────────────────────────────────

  void _on(String event, Function(dynamic) callback) {
    _socket?.off(event);
    _socket?.on(event, callback);
  }

  void listenToBusUpdates(Function(dynamic) callback) {
    _socket?.off('busLocationUpdate');
    _socket?.on('busLocationUpdate', (data) {
      lastDataReceived.value = DateTime.now();
      callback(data);
    });
  }

  void listenToSystemAlerts(Function(dynamic) callback) =>
      _on('systemAlert', callback);

  /// Registers an additional SOS callback.
  /// The permanent internal SOS listener (which updates [lastSOSAlert])
  /// is always active — this adds a supplementary callback on top.
  void listenToSOSAlerts(Function(dynamic) callback) {
    _sosCallbacks
      ..clear()
      ..add(callback);
  }

  void listenToBusApproach(Function(dynamic) callback) =>
      _on('busApproachingStop', callback);

  void listenToStatsUpdate(Function(dynamic) callback) =>
      _on('statsUpdate', callback);

  void listenToNotifications(Function(dynamic) callback) =>
      _on('notification', callback);

  /// Listens for bus delay events emitted by manager or server.
  void listenToBusDelayed(Function(dynamic) callback) =>
      _on('busDelayed', callback);

  void off(String event) => _socket?.off(event);

  // ─── Emit Methods ────────────────────────────────────────────────────────

  void emitLocationUpdate(Map<String, dynamic> data) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ Cannot emit: Socket not connected');
      reconnect();
      return;
    }
    _socket?.emit('locationUpdate', data);
    debugPrint('📡 BROADCAST: Lat=${data['latitude']}, Lng=${data['longitude']}, Speed=${data['speed']} KM/H');
  }

  void emitSOSAlert(Map<String, dynamic> data) {
    if (!isConnected) { 
      debugPrint('⚠️ SOS Emit failed: Reconnecting...');
      reconnect(); 
      return; 
    }
    _socket?.emitWithAck('triggerSOS', data, ack: (response) {
      debugPrint('🆘 SOS ACK: $response');
    });
  }

  void emitTripEnd(String busId) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ Cannot emit tripEnd: Socket not connected');
      return;
    }
    _socket?.emit('tripEnd', {'busId': busId});
    debugPrint('🏁 Emitted tripEnd for Bus $busId');
  }

  void emitNotification(Map<String, dynamic> data) =>
      _socket?.emit('managerBroadcast', data);

  // ─── Cleanup ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    connectionStatus.dispose();
    lastDataReceived.dispose();
    lastSOSAlert.dispose();
    lastPingMs.dispose();
    _sosCallbacks.clear();
    super.dispose();
  }
}


