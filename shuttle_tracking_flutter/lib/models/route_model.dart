class RouteModel {
  final String id;
  final String name;
  final String color;
  final List<Map<String, double>> coordinates;
  final List<Map<String, dynamic>> stops;

  RouteModel({
    required this.id,
    required this.name,
    required this.color,
    required this.coordinates,
    required this.stops,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      color: json['color'] ?? '#000000',
      coordinates: (json['coordinates'] as List<dynamic>?)
              ?.map<Map<String, double>>((c) => {
                    'latitude': (c['latitude'] ?? 0.0).toDouble(),
                    'longitude': (c['longitude'] ?? 0.0).toDouble(),
                  })
              .toList() ??
          [],
      stops: (json['stops'] as List<dynamic>?)
              ?.map<Map<String, dynamic>>((s) => {
                    'name': s['name'] ?? '',
                    'lat': (s['lat'] ?? 0.0).toDouble(),
                    'lng': (s['lng'] ?? 0.0).toDouble(),
                  })
              .toList() ??
          [],
    );
  }
}
