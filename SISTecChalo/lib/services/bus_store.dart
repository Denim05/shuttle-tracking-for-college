import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bus_model.dart';
import 'socket_service.dart';
import 'notification_service.dart';

// â”€â”€â”€ Notification Model â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class LiveNotification {
  final String id;
  final String message;
  final String type; // 'info' | 'warning' | 'critical'
  final DateTime timestamp;
  bool isRead;

  LiveNotification({
    required this.id,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
  });

  factory LiveNotification.fromJson(Map<String, dynamic> json) {
    return LiveNotification(
      id        : json['_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      message   : json['message']?.toString() ?? '',
      type      : json['type']?.toString() ?? 'info',
      timestamp : json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

// â”€â”€â”€ Bus Store â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Central real-time bus state for SISTecChalo.
///
/// - Holds `Map<String, Bus>` keyed by bus ID
/// - Listens to socket `busLocationUpdate` events
/// - Merges updates â€” no full-list replacement, zero UI flicker
/// - Auto-purges stale buses (no update > 120s) â†’ marked Offline
/// - Exposes [activeBuses] â€” online buses updated recently
/// - Emits geofence approach events via [approachStream]
/// - Holds live [notifications] list with [unreadCount] badge
class BusStore extends ChangeNotifier {
  final SocketService _socketService;

  BusStore(this._socketService) {
    _initListeners();
    _startStalePurge();
  }

  // â”€â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  final Map<String, Bus> _buses = {};
  final List<LiveNotification> _notifications = [];
  final StreamController<BusApproachEvent> _approachCtrl =
      StreamController<BusApproachEvent>.broadcast();
  Timer?   _purgeTimer;
  DateTime _lastUpdateTime = DateTime.now();

  static const int _staleSecs = 120;
  static const int _maxNotifications = 100;

  // â”€â”€â”€ Public Getters â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<Bus> get allBuses => _buses.values.toList();

  List<Bus> get activeBuses {
    final cutoff = DateTime.now().subtract(const Duration(seconds: _staleSecs));
    return _buses.values
        .where((b) => b.status != 'Offline' && b.lastUpdated.isAfter(cutoff))
        .toList();
  }

  DateTime get lastUpdateTime => _lastUpdateTime;

  Stream<BusApproachEvent> get approachStream => _approachCtrl.stream;

  Bus? busById(String id) => _buses[id];

  /// Live notification feed, newest first, filtered to show only notifications from the last 24 hours (1 day).
  List<LiveNotification> get notifications {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return List.unmodifiable(
      _notifications.where((n) => n.timestamp.isAfter(cutoff)),
    );
  }

  /// Number of unread notifications for badge display (within the last 24 hours).
  int get unreadCount {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return _notifications
        .where((n) => !n.isRead && n.timestamp.isAfter(cutoff))
        .length;
  }

  /// Seed historical notifications loaded from the API.
  void seedNotifications(List<dynamic> json) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    for (final item in json) {
      try {
        final n = LiveNotification.fromJson(item as Map<String, dynamic>);
        // Skip seeding notifications older than 24 hours
        if (n.timestamp.isBefore(cutoff)) continue;
        // Avoid duplicates
        if (!_notifications.any((x) => x.id == n.id)) {
          _notifications.add(n);
        }
      } catch (_) {}
    }
    // Sort newest first
    _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();
  }

  /// Mark all notifications as read (clears badge).
  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  // â”€â”€â”€ Seeding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void seedBuses(List<dynamic> json) {
    for (final item in json) {
      try {
        final bus = Bus.fromJson(item as Map<String, dynamic>);
        _buses[bus.id] = bus;
      } catch (_) {}
    }
    notifyListeners();
  }

  // â”€â”€â”€ Socket Listeners â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _initListeners() {
    _socketService.listenToBusUpdates(_onBusUpdate);
    _socketService.listenToBusApproach(_onBusApproach);
    _socketService.listenToNotifications(_onNotification);
  }

  void _onBusUpdate(dynamic data) {
    try {
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);

      final bus = Bus.fromJson(json);
      _buses[bus.id] = bus;
      _lastUpdateTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('BusStore._onBusUpdate error: $e');
    }
  }

  void _onBusApproach(dynamic data) {
    try {
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);

      _approachCtrl.add(BusApproachEvent(
        busId    : json['busId']?.toString() ?? '',
        stopName : json['stopName']?.toString() ?? 'a stop',
        distance : (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
        eta      : (json['etaMinutes'] as num?)?.toInt() ?? 1,
        routeName: json['routeName']?.toString() ?? '',
        routeId  : json['routeId']?.toString() ?? '',
      ));
    } catch (e) {
      debugPrint('BusStore._onBusApproach error: $e');
    }
  }

  void _onNotification(dynamic data) {
    try {
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);

      final n = LiveNotification.fromJson(json);

      // Avoid duplicates from re-seed
      if (_notifications.any((x) => x.id == n.id)) return;

      _notifications.insert(0, n); // newest first

      // Cap the list
      if (_notifications.length > _maxNotifications) {
        _notifications.removeRange(_maxNotifications, _notifications.length);
      }
      
      // ðŸš¨ Trigger local notification for broadcast message
      NotificationService().showNotification(
        title: 'New Update',
        body: n.message,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('BusStore._onNotification error: $e');
    }
  }

  // â”€â”€â”€ Stale Purge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _startStalePurge() {
    _purgeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final cutoff = DateTime.now()
          .subtract(const Duration(seconds: _staleSecs));
      final stale = _buses.entries
          .where((e) => e.value.lastUpdated.isBefore(cutoff))
          .map((e) => e.key)
          .toList();

      if (stale.isNotEmpty) {
        for (final id in stale) {
          final b = _buses[id]!;
          _buses[id] = Bus(
            id         : b.id,
            routeId    : b.routeId,
            routeName  : b.routeName,
            routeColor : b.routeColor,
            currentLat : b.currentLat,
            currentLng : b.currentLng,
            heading    : b.heading,
            speed      : 0,
            status     : 'Offline',
            driverId   : b.driverId,
            occupancy  : b.occupancy,
            etas       : const [],
            lastUpdated: b.lastUpdated,
          );
        }
        notifyListeners();
        debugPrint('BusStore: ${stale.length} bus(es) marked Offline (stale)');
      }
    });
  }

  // â”€â”€â”€ Cleanup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  void dispose() {
    _purgeTimer?.cancel();
    _approachCtrl.close();
    super.dispose();
  }
}

// â”€â”€â”€ Approach Event â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class BusApproachEvent {
  final String   busId;
  final String   stopName;
  final double   distance;
  final int      eta;
  final String   routeName;
  final String   routeId;
  final DateTime timestamp;

  BusApproachEvent({
    required this.busId,
    required this.stopName,
    required this.distance,
    required this.eta,
    required this.routeName,
    required this.routeId,
  }) : timestamp = DateTime.now();
}


