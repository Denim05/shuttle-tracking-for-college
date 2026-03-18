import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/constants.dart';
import '../models/user_model.dart';

class AuthService with ChangeNotifier {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username, 
          'password': password, 
          'role': role
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _currentUser = User.fromJson(data['user']);
        _isAuthenticated = true;
        
        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        
        _isAuthenticating = false;
        notifyListeners();
        return true;
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Login failed');
      }
    } catch (e) {
      _isAuthenticating = false;
      notifyListeners();
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
}
