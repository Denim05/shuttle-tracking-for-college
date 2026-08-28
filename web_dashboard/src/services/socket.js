import { io } from 'socket.io-client';

const SOCKET_URL = import.meta.env.VITE_SOCKET_URL || 'http://localhost:5000';

class SocketService {
  constructor() {
    this.socket = null;
    this.connected = false;
  }

  connect() {
    if (this.socket && this.socket.connected) return;

    this.socket = io(SOCKET_URL, {
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionAttempts: 10,
      reconnectionDelay: 1000,
    });

    this.socket.on('connect', () => {
      console.log('⚡ Socket Connected to Backend:', this.socket.id);
      this.connected = true;
    });

    this.socket.on('disconnect', () => {
      console.log('🔌 Socket Disconnected');
      this.connected = false;
    });
  }

  disconnect() {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
      this.connected = false;
    }
  }

  onLocationUpdate(callback) {
    if (!this.socket) this.connect();
    this.socket.on('locationUpdate', callback);
  }

  onSOSAlert(callback) {
    if (!this.socket) this.connect();
    this.socket.on('sosAlert', callback);
  }

  onBroadcastStats(callback) {
    if (!this.socket) this.connect();
    this.socket.on('broadcastStats', callback);
  }

  off(eventName, callback) {
    if (this.socket) {
      this.socket.off(eventName, callback);
    }
  }
}

export const socketService = new SocketService();
export default socketService;
