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
  });

  bool get isDropoff => tripType == 'dropoff';
  String get directionLabel => isDropoff ? 'College ➔ Stop' : 'Stop ➔ College';

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
    List<BusETA>? etas,
    DateTime? lastUpdated,
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
      etas: etas ?? this.etas,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? json['busId']?.toString() ?? '',
      busNumber: json['busNumber']?.toString() ?? json['busNo']?.toString() ?? json['vehicleNo']?.toString() ?? json['plateNumber']?.toString(),
      name: json['name']?.toString() ?? json['busName']?.toString(),
      shift: json['shift']?.toString(),
      routeId: json['routeId']?.toString() ?? '',
      routeName: json['routeName'] ?? 'Unknown Route',
      routeColor: json['routeColor'] ?? '#2D5BFF',
      currentLat: (json['currentLat'] ?? json['latitude'] ?? 0.0).toDouble(),
      currentLng: (json['currentLng'] ?? json['longitude'] ?? 0.0).toDouble(),
      heading: (json['heading'] ?? 0.0).toDouble(),
      speed: (json['speed'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'Offline',
      driverId: json['driverId']?.toString(),
      occupancy: json['occupancy'] ?? 'Low',
      tripType: json['tripType'] ?? 'pickup',
      reachedStops: (json['reachedStops'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      completedStops: (json['completedStops'] ?? (json['reachedStops'] as List?)?.length ?? 0) as int,
      nextStop: json['nextStop']?.toString(),
      distanceToNextStopMeters: (json['distanceToNextStopMeters'] as num?)?.toInt(),
      etas: (json['etas'] as List? ?? [])
          .map((e) => BusETA.fromJson(e))
          .toList(),
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.parse(json['lastUpdated'].toString())
          : DateTime.now(),
    );
  }
}

class BusETA {
  final String stopName;
  final int minutes;

  BusETA({required this.stopName, required this.minutes});

  factory BusETA.fromJson(Map<String, dynamic> json) {
    return BusETA(
      stopName: json['stopName'] ?? '',
      minutes: (json['minutes'] ?? 0).toInt(),
    );
  }
}

