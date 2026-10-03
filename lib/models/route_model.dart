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

  /// Extracts bus number label from route name (e.g. "Bus 01", "Bus T-4", "Bus MP04 PA 1886")
  String get busNumber {
    final match = RegExp(r'^(Bus\s*[^-\:]+)', caseSensitive: false).firstMatch(name);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return '';
  }

  /// Extracts pure corridor name without bus number prefix
  String get corridorName {
    final match = RegExp(r'^Bus\s*[^-\:]+[\-\:]\s*(.+)$', caseSensitive: false).firstMatch(name);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return name;
  }

  /// Check if query matches bus number or corridor
  bool matches(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase().trim();
    final cleanBus = busNumber.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanQ = q.replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    if (cleanBus.isNotEmpty && (cleanBus.contains(cleanQ) || cleanQ.contains(cleanBus))) {
      return true;
    }
    if (name.toLowerCase().contains(q)) return true;
    if (corridorName.toLowerCase().contains(q)) return true;
    for (final s in stops) {
      if ((s['name'] ?? '').toString().toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

