import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/constants.dart';
import 'package:flutter/foundation.dart';

class SocketService {
  late io.Socket _socket;

  io.Socket? get socket => _socket;

  /// Initializes the Socket.io connection to the backend server.
  /// Configures websocket transport and registers basic connection listeners.
  void initSocket() {
    _socket = io.io(AppConstants.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket.connect();
    
    _socket.onConnect((_) {
      debugPrint('Connected to Socket Server');
    });

    _socket.onDisconnect((_) => debugPrint('Disconnected from Socket Server'));
  }

  /// Listens to broadcasted 'busLocationUpdate' events from the server.
  /// Executes the provided [callback] whenever new location data arrives.
  void listenToBusUpdates(Function(dynamic) callback) {
    _socket.on('busLocationUpdate', (data) {
      callback(data);
    });
  }

  /// Emits a 'locationUpdate' event containing current GPS/Speed data to the server.
  void emitLocationUpdate(Map<String, dynamic> data) {
    _socket.emit('locationUpdate', data);
  }

  void dispose() {
    _socket.disconnect();
  }
}
