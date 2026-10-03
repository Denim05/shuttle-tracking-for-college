import '../utils/timetable_resolver.dart';

class Bus {
  final String id;
  final String? busNumber;
  final String? name;
  final String? shift;
  final String routeId;
  final String routeName;
  final String routeColor;
  final double currentLat;
  final double currentLng;
  final double heading;
  final double speed;
  final String status; // 'On-time', 'Delayed', 'Offline'
  final String? driverId;
  final String occupancy; // 'Low', 'Medium', 'High'
  final String tripType; // 'pickup' (Stop -> College) or 'dropoff' (College -> Stop)
  final List<String> reachedStops;
  final int completedStops;
  final String? nextStop;
  final int? distanceToNextStopMeters;
  final List<BusETA> etas;
  final DateTime lastUpdated;
  final int? distanceToFinalStopMeters;
  final double? gpsAccuracy;

  Bus({
    required this.id,
    this.busNumber,
    this.name,
    this.shift,
    required this.routeId,
    required this.routeName,
    required this.routeColor,
    required this.currentLat,
    required this.currentLng,
    required this.heading,
    required this.speed,
    required this.status,
    this.driverId,
    this.occupancy = 'Low',
    this.tripType = 'pickup',
    this.reachedStops = const [],
    this.completedStops = 0,
    this.nextStop,
    this.distanceToNextStopMeters,
    this.etas = const [],
    required this.lastUpdated,
    this.distanceToFinalStopMeters,
    this.gpsAccuracy,
  });

  bool get isDropoff => tripType == 'dropoff';
  String get directionLabel => isDropoff ? 'College ➔ Stop' : 'Stop ➔ College';

  /// Returns true ONLY if the driver is actively broadcasting live telemetry
  /// within the last 30 seconds and status is not Offline.
  bool get isBroadcastingLive {
    if (status.toLowerCase().trim() == 'offline') return false;
    final diffSeconds = DateTime.now().difference(lastUpdated).inSeconds;
    return diffSeconds <= 30;
  }

  /// Returns the manager-assigned Bus Number (e.g. "BUS 02", "BUS 19", "BUS T-4")
  /// Permanently guaranteed NEVER to return a raw hex ID substring.
  String get displayBusNumber {
    return TimetableResolver.resolveAssignedBusNumber(
      explicitBusNumber: busNumber,
      busName: name,
      routeName: routeName,
      shift: shift,
    );
  }

  /// Calculates shift label based on manager route config or time of day
  String get shiftLabel {
    return TimetableResolver.resolveShiftLabel(
      explicitShift: shift,
      routeName: routeName,
      currentHour: DateTime.now().hour,
    );
  }

  /// Official Timetable Entry from SISTec Ratibad institutional roster
  TimetableRouteEntry? get timetableEntry {
    return TimetableResolver.lookupEntry(
      busNumber: busNumber,
      busName: name,
      routeName: routeName,
    );
  }

  /// Official Vehicle Registration (e.g. "MP04 PA 3496")
  String get officialVehicleNo {
    return timetableEntry?.vehicleNo ?? (busNumber?.toUpperCase() ?? 'MP04 PA ----');
  }

  /// Official Assigned Driver Name from roster
  String get assignedDriverName {
    return timetableEntry?.driverName ?? 'Assigned Driver';
  }

  /// Official Assigned Driver Phone Number
  String? get assignedDriverPhone {
    return timetableEntry?.driverPhone;
  }

  Bus copyWith({
    String? id,
    String? busNumber,
    String? name,
    String? shift,
    String? routeId,
    String? routeName,
    String? routeColor,
    double? currentLat,
    double? currentLng,
    double? heading,
    double? speed,
    String? status,
    String? driverId,
    String? occupancy,
    String? tripType,
    List<String>? reachedStops,
    int? completedStops,
    String? nextStop,
    int? distanceToNextStopMeters,
    int? distanceToFinalStopMeters,
    List<BusETA>? etas,
    DateTime? lastUpdated,
    double? gpsAccuracy,
  }) {
    return Bus(
      id: id ?? this.id,
      busNumber: busNumber ?? this.busNumber,
      name: name ?? this.name,
      shift: shift ?? this.shift,
      routeId: (routeId != null && routeId.isNotEmpty) ? routeId : this.routeId,
      routeName: (routeName != null && routeName.isNotEmpty && routeName != 'Unknown Route') ? routeName : this.routeName,
      routeColor: (routeColor != null && routeColor.isNotEmpty) ? routeColor : this.routeColor,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      status: status ?? this.status,
      driverId: driverId ?? this.driverId,
      occupancy: occupancy ?? this.occupancy,
      tripType: tripType ?? this.tripType,
      reachedStops: reachedStops ?? this.reachedStops,
      completedStops: completedStops ?? this.completedStops,
      nextStop: nextStop ?? this.nextStop,
      distanceToNextStopMeters: distanceToNextStopMeters ?? this.distanceToNextStopMeters,
      distanceToFinalStopMeters: distanceToFinalStopMeters ?? this.distanceToFinalStopMeters,
      etas: etas ?? this.etas,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
    );
  }

  factory Bus.fromJson(dynamic raw) {
    final Map<dynamic, dynamic> json = raw is Map ? raw : <dynamic, dynamic>{};

    double parseDouble(dynamic v, [double fallback = 0.0]) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    int parseInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v.toLocal();
      return DateTime.tryParse(v.toString())?.toLocal() ?? DateTime.now();
    }

    return Bus(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? json['busId']?.toString() ?? '',
      busNumber: json['busNumber']?.toString() ?? json['busNo']?.toString() ?? json['vehicleNo']?.toString() ?? json['plateNumber']?.toString(),
      name: json['name']?.toString() ?? json['busName']?.toString(),
      shift: json['shift']?.toString(),
      routeId: json['routeId']?.toString() ?? '',
      routeName: json['routeName']?.toString() ?? 'Unknown Route',
      routeColor: json['routeColor']?.toString() ?? '#2D5BFF',
      currentLat: parseDouble(json['currentLat'] ?? json['latitude']),
      currentLng: parseDouble(json['currentLng'] ?? json['longitude']),
      heading: parseDouble(json['heading']),
      speed: parseDouble(json['speed']),
      status: json['status']?.toString() ?? 'Offline',
      driverId: json['driverId']?.toString(),
      occupancy: json['occupancy']?.toString() ?? 'Low',
      tripType: json['tripType']?.toString() ?? 'pickup',
      reachedStops: (json['reachedStops'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      completedStops: parseInt(json['completedStops'], (json['reachedStops'] as List?)?.length ?? 0),
      nextStop: json['nextStop']?.toString(),
      distanceToNextStopMeters: json['distanceToNextStopMeters'] != null ? parseInt(json['distanceToNextStopMeters']) : null,
      etas: (json['etas'] as List? ?? [])
          .map((e) => BusETA.fromJson(e))
          .toList(),
      lastUpdated: parseDate(json['lastUpdated']),
      distanceToFinalStopMeters: json['distanceToFinalStopMeters'] != null ? parseInt(json['distanceToFinalStopMeters']) : null,
      gpsAccuracy: parseDouble(json['gpsAccuracy']),
    );
  }
}

class BusETA {
  final String stopName;
  final int minutes;

  BusETA({required this.stopName, required this.minutes});

  factory BusETA.fromJson(dynamic raw) {
    if (raw is! Map) return BusETA(stopName: '', minutes: 0);
    final mins = raw['minutes'];
    final minsInt = (mins is num) ? mins.toInt() : (int.tryParse('$mins') ?? 0);
    return BusETA(
      stopName: raw['stopName']?.toString() ?? '',
      minutes: minsInt,
    );
  }
}

