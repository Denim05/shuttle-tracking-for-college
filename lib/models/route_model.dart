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

  static const Map<String, Map<String, double>> _verifiedStopCoords = {
    'katara hospital': {'lat': 23.18920, 'lng': 77.49520},
    'katara dastoor hostel': {'lat': 23.19460, 'lng': 77.49120},
    'lahar pur': {'lat': 23.19720, 'lng': 77.48360},
    'bagsewaniya ojes hospital': {'lat': 23.20120, 'lng': 77.47420},
    'saket nagar': {'lat': 23.21220, 'lng': 77.45220},
    'aiims': {'lat': 23.20860, 'lng': 77.45820},
    'alkapuri': {'lat': 23.20660, 'lng': 77.46420},
    'durga mandir': {'lat': 23.21820, 'lng': 77.47120},
    'durgamandir': {'lat': 23.21820, 'lng': 77.47120},
    'barkheda pathani': {'lat': 23.22160, 'lng': 77.48320},
    'awadhpuri thana': {'lat': 23.23092, 'lng': 77.49502},
    'aadharshila chowk': {'lat': 23.23560, 'lng': 77.48660},
    'aadhar sila chaowk': {'lat': 23.23560, 'lng': 77.48660},
    'durga chowk': {'lat': 23.23860, 'lng': 77.47920},
    'awadhpuri tiraha': {'lat': 23.24260, 'lng': 77.47160},
    'mahatma gandhi chauraha': {'lat': 23.24820, 'lng': 77.44220},
    'red cross': {'lat': 23.22860, 'lng': 77.42120},
    'panchsheel nagar': {'lat': 23.22560, 'lng': 77.39820},
    'panchsil nagar': {'lat': 23.22560, 'lng': 77.39820},
    'ratibad campus': {'lat': 23.180302, 'lng': 77.302695},
  };

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
              ?.map<Map<String, dynamic>>((s) {
                final name = (s['name'] ?? '').toString();
                double sLat = (s['lat'] is num) ? (s['lat'] as num).toDouble() : (double.tryParse('${s['lat']}') ?? 0.0);
                double sLng = (s['lng'] is num) ? (s['lng'] as num).toDouble() : (double.tryParse('${s['lng']}') ?? 0.0);

                final cleanName = name.trim().toLowerCase();
                final bool isCampus = cleanName.contains('ratibad') || cleanName.contains('campus');
                final bool isDefaultCampusCoords = (sLat - 23.180302).abs() < 0.001 && (sLng - 77.302695).abs() < 0.001;

                if ((sLat == 0.0 || sLng == 0.0 || (isDefaultCampusCoords && !isCampus)) && _verifiedStopCoords.containsKey(cleanName)) {
                  sLat = _verifiedStopCoords[cleanName]!['lat']!;
                  sLng = _verifiedStopCoords[cleanName]!['lng']!;
                }

                return {
                  'name': name,
                  'lat': sLat,
                  'lng': sLng,
                };
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

