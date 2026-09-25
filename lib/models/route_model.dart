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
              ?.map<Map<String, double>>((c) {
                final lat = c['latitude'] ?? c['lat'] ?? 0.0;
                final lng = c['longitude'] ?? c['lng'] ?? 0.0;
                final latVal = (lat is num) ? lat.toDouble() : double.tryParse('$lat') ?? 0.0;
                final lngVal = (lng is num) ? lng.toDouble() : double.tryParse('$lng') ?? 0.0;
                return {
                  'latitude': latVal,
                  'longitude': lngVal,
                };
              })
              .where((c) => c['latitude'] != 0.0 && c['longitude'] != 0.0)
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

