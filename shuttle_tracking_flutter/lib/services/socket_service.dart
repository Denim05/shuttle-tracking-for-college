import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/constants.dart';
import 'package:flutter/foundation.dart';

class SocketService {
  io.Socket? _socket;

  io.Socket? get socket => _socket;

  /// Initializes the Socket.io connection to the backend server.
  /// Configures websocket transport and registers basic connection listeners.
  void initSocket() {
    debugPrint('Connecting to socket: ${AppConstants.baseUrl}');
    _socket = io.io(AppConstants.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 10, // Increased attempts
      'reconnectionDelay': 1000,   // Faster initial retry
      'reconnectionDelayMax': 5000,
      'timeout': 20000,
    });
    
    _socket!.on('connect', (_) {
      debugPrint('✅ Connected to Socket Server');
    });

    _socket!.on('reconnect', (_) => debugPrint('♻️ Socket Reconnected'));
    _socket!.on('reconnectAttempt', (attempt) => debugPrint('🔄 Socket Reconnect Attempt: $attempt'));
    _socket!.on('connect_error', (data) => debugPrint('❌ Socket Connect Error: $data'));
    _socket!.on('error', (data) => debugPrint('❌ Socket Error: $data'));
    _socket!.on('disconnect', (_) => debugPrint('⚠️ Disconnected from Socket Server'));
  }

  void reconnect() {
    if (_socket?.disconnected ?? true) {
      _socket?.connect();
    }
  }

  /// Listens to broadcasted 'busLocationUpdate' events from the server.
  /// Executes the provided [callback] whenever new location data arrives.
  void listenToBusUpdates(Function(dynamic) callback) {
    _socket?.on('busLocationUpdate', (data) {
      callback(data);
    });
  }

  /// Listens to system alerts and notifications sent from the server.
  void listenToSystemAlerts(Function(dynamic) callback) {
    _socket?.on('systemAlert', (data) {
      callback(data);
    });
  }

  /// Emits a 'locationUpdate' event containing current GPS/Speed data to the server.
  void emitLocationUpdate(Map<String, dynamic> data) {
    _socket?.emit('locationUpdate', data);
  }

  /// Listens for high-priority emergency SOS alerts from the server.
  void listenToSOSAlerts(Function(dynamic) callback) {
    _socket?.on('sosAlert', (data) {
      callback(data);
    });
  }

  /// Listens for geofence proximity alerts from the server.
  void listenToBusApproach(Function(dynamic) callback) {
    _socket?.on('busApproachingStop', (data) {
      callback(data);
    });
  }

  /// Emits a critical 'triggerSOS' event containing user, role, and location data.
  void emitSOSAlert(Map<String, dynamic> data) {
    _socket?.emit('triggerSOS', data);
  }

  void dispose() {
    _socket?.disconnect();
  }
}
