import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bus_model.dart';
import 'socket_service.dart';
import 'notification_service.dart';

// ─── Notification Model ──────────────────────────────────────────────────────

class LiveNotification {
  final String id;
  final String message;
  final String type; // 'info' | 'warning' | 'critical'
  final String targetAudience; // 'All' | 'Users' | 'Drivers' | 'Admins'
  final DateTime timestamp;
  bool isRead;

  LiveNotification({
    required this.id,
    required this.message,
    required this.type,
    this.targetAudience = 'All',
    required this.timestamp,
    this.isRead = false,
  });

  factory LiveNotification.fromJson(Map<String, dynamic> json) {
    return LiveNotification(
      id            : json['_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      message       : json['message']?.toString() ?? '',
      type          : json['type']?.toString() ?? 'info',
      targetAudience: json['targetAudience']?.toString() ?? 'All',
      timestamp     : json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

// ─── Bus Store ───────────────────────────────────────────────────────────────

/// Central real-time bus state for SISTecChalo.
///
/// - Holds `Map<String, Bus>` keyed by bus ID
/// - Listens to socket `busLocationUpdate` events
/// - Merges updates — no full-list replacement, zero UI flicker
/// - Auto-purges stale buses (no update > 120s) → marked Offline
/// - Exposes [activeBuses] — online buses updated recently
/// - Emits geofence approach events via [approachStream]
/// - Holds live [notifications] list with [unreadCount] badge
class BusStore extends ChangeNotifier {
  final SocketService _socketService;

  BusStore(this._socketService) {
    _initListeners();
    _startStalePurge();
  }

  // ─── State ──────────────────────────────────────────────────────────────

  final Map<String, Bus> _buses = {};
  final List<LiveNotification> _notifications = [];
  final StreamController<BusApproachEvent> _approachCtrl =
      StreamController<BusApproachEvent>.broadcast();
  Timer?   _purgeTimer;
  DateTime _lastUpdateTime = DateTime.now();

  static const int _staleSecs = 120;
  static const int _maxNotifications = 100;

  List<Bus>? _cachedSortedBuses;

  static final RegExp _busNoRegex = RegExp(r'Bus\s+no:\s*([A-Za-z0-9\-]+)', caseSensitive: false);
  static final RegExp _busRegex = RegExp(r'Bus\s+([A-Za-z0-9\-]+)', caseSensitive: false);
  static final RegExp _isNumRegex = RegExp(r'^\d+$');
  static final RegExp _isTRegex = RegExp(r'^T-\d+$', caseSensitive: false);
  static final RegExp _digitsRegex = RegExp(r'\D');

  // ─── Public Getters ─────────────────────────────────────────────────────

  List<Bus> get allBuses {
    if (_cachedSortedBuses != null) return _cachedSortedBuses!;

    final list = _buses.values.toList();
    list.sort((a, b) {
      String getBusKey(Bus bus) {
        final match = _busNoRegex.firstMatch(bus.routeName);
        if (match != null) return match.group(1)!;
        final match2 = _busRegex.firstMatch(bus.routeName);
        if (match2 != null) return match2.group(1)!;
        return bus.routeName;
      }

      final aKey = getBusKey(a);
      final bKey = getBusKey(b);

      final aIsNum = _isNumRegex.hasMatch(aKey);
      final bIsNum = _isNumRegex.hasMatch(bKey);

      if (aIsNum && bIsNum) {
        final aInt = int.tryParse(aKey) ?? 0;
        final bInt = int.tryParse(bKey) ?? 0;
        if (aInt != bInt) return aInt.compareTo(bInt);
      } else if (aIsNum) {
        return -1;
      } else if (bIsNum) {
        return 1;
      }

      final aIsT = _isTRegex.hasMatch(aKey);
      final bIsT = _isTRegex.hasMatch(bKey);
      if (aIsT && bIsT) {
        final aInt = int.tryParse(aKey.replaceAll(_digitsRegex, '')) ?? 0;
        final bInt = int.tryParse(bKey.replaceAll(_digitsRegex, '')) ?? 0;
        if (aInt != bInt) return aInt.compareTo(bInt);
      } else if (aIsT) {
        return -1;
      } else if (bIsT) {
        return 1;
      }

      return aKey.compareTo(bKey);
    });

    _cachedSortedBuses = list;
    return list;
  }

  /// Alias for allBuses
  List<Bus> get buses => allBuses;

  List<Bus> get activeBuses {
    final cutoff = DateTime.now().subtract(const Duration(seconds: _staleSecs));
    return _buses.values
        .where((b) => b.status.toLowerCase() != 'offline' && b.lastUpdated.isAfter(cutoff))
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

  /// Remove a specific notification by ID.
  void removeNotification(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  /// Clear all notifications.
  void clearAllNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  // ─── Seeding ────────────────────────────────────────────────────────────

  void seedBuses(List<dynamic> json) {
    for (final item in json) {
      try {
        final bus = Bus.fromJson(item as Map<String, dynamic>);
        _buses[bus.id] = bus;
      } catch (_) {}
    }
    _cachedSortedBuses = null;
    notifyListeners();
  }

  // ─── Socket Listeners ────────────────────────────────────────────────────

  void _initListeners() {
    _socketService.listenToBusUpdates(_onBusUpdate);
    _socketService.listenToLocationUpdates(_onBusUpdate);
    _socketService.listenToBusCreated(_onBusUpdate);
    _socketService.listenToBusUpdated(_onBusUpdate);
    _socketService.listenToBusDeleted(_onBusDeleted);
    _socketService.listenToBusApproach(_onBusApproach);
    _socketService.listenToNotifications(_onNotification);
    _socketService.listenToNotificationDeleted(_onNotificationDeleted);
  }

  void _onBusDeleted(dynamic data) {
    try {
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
      final String? id = json['id']?.toString() ?? json['_id']?.toString();
      if (id != null) {
        _buses.remove(id);
        _cachedSortedBuses = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('BusStore._onBusDeleted error: $e');
    }
  }

  void _onNotificationDeleted(dynamic data) {
    try {
      final Map<String, dynamic> json = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);
      final String? id = json['id']?.toString();
      if (id != null) {
        removeNotification(id);
      }
    } catch (e) {
      debugPrint('BusStore._onNotificationDeleted error: $e');
    }
  }

  void _onBusUpdate(dynamic data) {
    try {
      final incoming = Bus.fromJson(data);
      if (incoming.id.isEmpty) return;

      final now = DateTime.now();
      final existing = _buses[incoming.id];
      if (existing != null) {
        _buses[incoming.id] = existing.copyWith(
          busNumber: (incoming.busNumber != null && incoming.busNumber!.isNotEmpty && incoming.busNumber != 'N/A')
              ? incoming.busNumber
              : existing.busNumber,
          name: (incoming.name != null && incoming.name!.isNotEmpty) ? incoming.name : existing.name,
          shift: (incoming.shift != null && incoming.shift!.isNotEmpty) ? incoming.shift : existing.shift,
          routeId: incoming.routeId.isNotEmpty ? incoming.routeId : existing.routeId,
          routeName: (incoming.routeName.isNotEmpty && incoming.routeName != 'Unknown Route') ? incoming.routeName : existing.routeName,
          routeColor: (incoming.routeColor.isNotEmpty && incoming.routeColor != '#2D5BFF') ? incoming.routeColor : existing.routeColor,
          currentLat: incoming.currentLat != 0.0 ? incoming.currentLat : existing.currentLat,
          currentLng: incoming.currentLng != 0.0 ? incoming.currentLng : existing.currentLng,
          heading: incoming.heading,
          speed: incoming.speed,
          status: incoming.status,
          driverId: incoming.driverId ?? existing.driverId,
          occupancy: incoming.occupancy,
          tripType: incoming.tripType,
          reachedStops: incoming.reachedStops.isNotEmpty ? incoming.reachedStops : existing.reachedStops,
          completedStops: incoming.completedStops > 0 ? incoming.completedStops : existing.completedStops,
          nextStop: incoming.nextStop ?? existing.nextStop,
          distanceToNextStopMeters: incoming.distanceToNextStopMeters ?? existing.distanceToNextStopMeters,
          etas: incoming.etas.isNotEmpty ? incoming.etas : existing.etas,
          lastUpdated: now,
        );
      } else {
        _buses[incoming.id] = incoming.copyWith(lastUpdated: now);
      }
      _cachedSortedBuses = null; // Invalidate cache so all getters return fresh state immediately
      _lastUpdateTime = now;
      debugPrint('🚌 BusStore: live update applied for ${incoming.busNumber ?? incoming.id} (${incoming.status}, ${incoming.speed.toInt()} km/h, pos: ${incoming.currentLat.toStringAsFixed(4)}, ${incoming.currentLng.toStringAsFixed(4)})');
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
      
      // 🚨 Trigger local notification for broadcast message
      NotificationService().showNotification(
        title: 'New Update',
        body: n.message,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('BusStore._onNotification error: $e');
    }
  }

  // ─── Stale Purge ────────────────────────────────────────────────────────

  void _startStalePurge() {
    _purgeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final cutoff = DateTime.now()
          .subtract(const Duration(seconds: _staleSecs));
      final stale = _buses.entries
          .where((e) => e.value.status.toLowerCase() != 'offline' && e.value.lastUpdated.isBefore(cutoff))
          .map((e) => e.key)
          .toList();

      if (stale.isNotEmpty) {
        for (final id in stale) {
          final b = _buses[id]!;
          _buses[id] = b.copyWith(
            status: 'Offline',
            speed: 0,
            etas: const [],
            lastUpdated: DateTime.now(),
          );
        }
        _cachedSortedBuses = null;
        notifyListeners();
        debugPrint('BusStore: ${stale.length} bus(es) marked Offline (stale)');
      }
    });
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _purgeTimer?.cancel();
    _approachCtrl.close();
    super.dispose();
  }
}

// ─── Approach Event ──────────────────────────────────────────────────────────

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


