class Bus {
  final String id;
  final String routeId;
  final String routeName;
  final String routeColor;
  final double currentLat;
  final double currentLng;
  final double heading;
  final double speed;
  final String status;
  final String? driverId;
  final String occupancy;
  final List<dynamic>? etas;

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
    this.etas,
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
      etas: json['etas'],
    );
  }
}
