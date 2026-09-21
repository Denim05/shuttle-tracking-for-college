class User {
  final String id;
  final String? name;
  final String username;
  final String email;
  final String role; // 'user', 'driver', 'admin', 'manager', 'guest'
  final String status;
  final String? userId; // Renamed from studentId
  final String? routeId;
  final String? pickupPoint;
  final String? localAddress;
  final bool isCommuteConfigured;
  final bool proximityAlertsEnabled;
  final double proximityRadiusKm;
  final List<String> accessRights;
  final bool mustChangePassword;

  User({
    required this.id,
    this.name,
    required this.username,
    required this.email,
    required this.role,
    this.status = 'Active',
    this.userId,
    this.routeId,
    this.pickupPoint,
    this.localAddress,
    this.isCommuteConfigured = false,
    this.proximityAlertsEnabled = true,
    this.proximityRadiusKm = 1.0,
    this.accessRights = const [],
    this.mustChangePassword = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? json['username'],
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      status: json['status'] ?? 'Active',
      userId: json['userId'] ?? json['studentId'] ?? json['roll'],
      routeId: json['routeId'],
      pickupPoint: json['pickupPoint'],
      localAddress: json['localAddress'],
      isCommuteConfigured: json['isCommuteConfigured'] == true,
      proximityAlertsEnabled: json['proximityAlertsEnabled'] ?? true,
      proximityRadiusKm: (json['proximityRadiusKm'] as num?)?.toDouble() ?? 1.0,
      accessRights: List<String>.from(json['accessRights'] ?? []),
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name ?? username,
      'username': username,
      'email': email,
      'role': role,
      'status': status,
      'userId': userId,
      'routeId': routeId,
      'pickupPoint': pickupPoint,
      'localAddress': localAddress,
      'isCommuteConfigured': isCommuteConfigured,
      'proximityAlertsEnabled': proximityAlertsEnabled,
      'proximityRadiusKm': proximityRadiusKm,
      'accessRights': accessRights,
      'mustChangePassword': mustChangePassword,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? username,
    String? email,
    String? role,
    String? status,
    String? userId,
    String? routeId,
    String? pickupPoint,
    String? localAddress,
    bool? isCommuteConfigured,
    bool? proximityAlertsEnabled,
    double? proximityRadiusKm,
    List<String>? accessRights,
    bool? mustChangePassword,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      userId: userId ?? this.userId,
      routeId: routeId ?? this.routeId,
      pickupPoint: pickupPoint ?? this.pickupPoint,
      localAddress: localAddress ?? this.localAddress,
      isCommuteConfigured: isCommuteConfigured ?? this.isCommuteConfigured,
      proximityAlertsEnabled: proximityAlertsEnabled ?? this.proximityAlertsEnabled,
      proximityRadiusKm: proximityRadiusKm ?? this.proximityRadiusKm,
      accessRights: accessRights ?? this.accessRights,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }
}

