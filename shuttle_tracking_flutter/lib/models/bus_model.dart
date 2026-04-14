class Bus {
  final String id;
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
  final List<BusETA> etas;
  final DateTime lastUpdated;

  Bus({
    required this.id,
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
    this.etas = const [],
    required this.lastUpdated,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json['_id'] ?? '',
      routeId: json['routeId'] ?? '',
      routeName: json['routeName'] ?? '',
      routeColor: json['routeColor'] ?? '#000000',
      currentLat: (json['currentLat'] ?? 0.0).toDouble(),
      currentLng: (json['currentLng'] ?? 0.0).toDouble(),
      heading: (json['heading'] ?? 0.0).toDouble(),
      speed: (json['speed'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'Offline',
      driverId: json['driverId'],
      occupancy: json['occupancy'] ?? 'Low',
      etas: (json['etas'] as List? ?? [])
          .map((e) => BusETA.fromJson(e))
          .toList(),
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.parse(json['lastUpdated']) 
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
