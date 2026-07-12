class User {
  final String id;
  final String username;
  final String email;
  final String role; // 'user', 'driver', 'admin', 'manager', 'guest'
  final String status;
  final String? userId; // Renamed from studentId
  final String? routeId;
  final String? pickupPoint;
  final bool proximityAlertsEnabled;
  final double proximityRadiusKm;
  final List<String> accessRights;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.status = 'Active',
    this.userId,
    this.routeId,
    this.pickupPoint,
    this.proximityAlertsEnabled = true,
    this.proximityRadiusKm = 1.0,
    this.accessRights = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      status: json['status'] ?? 'Active',
      userId: json['userId'] ?? json['studentId'] ?? json['roll'],
      routeId: json['routeId'],
      pickupPoint: json['pickupPoint'],
      proximityAlertsEnabled: json['proximityAlertsEnabled'] ?? true,
      proximityRadiusKm: (json['proximityRadiusKm'] as num?)?.toDouble() ?? 1.0,
      accessRights: List<String>.from(json['accessRights'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'username': username,
      'email': email,
      'role': role,
      'status': status,
      'userId': userId,
      'routeId': routeId,
      'pickupPoint': pickupPoint,
      'proximityAlertsEnabled': proximityAlertsEnabled,
      'proximityRadiusKm': proximityRadiusKm,
      'accessRights': accessRights,
    };
  }
}

