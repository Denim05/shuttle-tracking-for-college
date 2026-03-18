class User {
  final String id;
  final String username;
  final String email;
  final String role; // 'user', 'driver', 'admin', 'manager'
  final String status;
  final List<String> accessRights;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.status = 'Active',
    this.accessRights = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      status: json['status'] ?? 'Active',
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
      'accessRights': accessRights,
    };
  }
}
