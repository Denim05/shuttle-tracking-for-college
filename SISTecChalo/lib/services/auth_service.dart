import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/constants.dart';
import '../models/user_model.dart';

class AuthService with ChangeNotifier {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
    webOptions: WebOptions(
      dbName: 'SISTecChalo_db',
      publicKey: 'SISTecChalo_key',
    ),
  );

  User? _currentUser;
  bool _isAuthenticated = false;
  String? _token;
  bool _isAuthenticating = true; // Start in "loading" state

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;
  bool get isAuthenticating => _isAuthenticating;
  bool get isGuest => _currentUser?.role == 'guest';

  Future<bool> login(String username, String password, String role) async {
    _isAuthenticating = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiUrl}/auth/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username.trim(), 
          'password': password, 
          'role': role
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (e) {
          throw Exception('Server returned invalid data (not JSON). Check your backend status.');
        }
        _token = data['token'];
        _currentUser = User.fromJson(data['user']);
        _isAuthenticated = true;
        
        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        
        _isAuthenticating = false;
        notifyListeners();
        return true;
      } else {
        String errorMessage = 'Login failed';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? errorData['message'] ?? errorMessage;
        } catch (_) {
          errorMessage = 'Server error (${response.statusCode}). Check if backend is running.';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      _isAuthenticating = false;
      notifyListeners();
      if (e is TimeoutException) {
        throw Exception('Connection timed out. Ensure your phone and laptop are on the same Wi-Fi and the IP in constants.dart is correct.');
      }
      rethrow;
    }
  }

  Future<void> loginAsGuest() async {
    _isAuthenticating = true;
    notifyListeners();
    
    // Guest is a special client-side role for public tracking
    _currentUser = User(
      id: 'guest_id',
      username: 'Guest User',
      email: 'guest@example.com',
      role: 'guest'
    );
    _isAuthenticated = true;
    _token = null; // No token for guest
    
    await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
    await _storage.delete(key: 'auth_token');
    
    _isAuthenticating = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _isAuthenticated = false;
    _isAuthenticating = false;
    await _storage.deleteAll();
    notifyListeners();
  }

  Future<void> tryAutoLogin() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final userDataStr = await _storage.read(key: 'user_data');
      
      if (token != null && userDataStr != null) {
        _token = token;
        _currentUser = User.fromJson(jsonDecode(userDataStr));
        _isAuthenticated = true;
      }
    } catch (e) {
      // Ignored
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  Future<void> updateProximityAlerts(bool enabled) async {
    if (_currentUser == null || _token == null) return;

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.apiUrl}/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'proximityAlertsEnabled': enabled}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentUser = User.fromJson(data);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating proximity alerts: $e');
    }
  }

  /// Changes the authenticated user's password.
  /// Throws an [Exception] with a user-facing message on failure.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    if (_token == null) throw Exception('Not authenticated.');
    final response = await http.put(
      Uri.parse('${AppConstants.apiUrl}/users/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      String msg = 'Failed to change password.';
      try { msg = jsonDecode(response.body)['error'] ?? msg; } catch (_) {}
      throw Exception(msg);
    }
  }
}


