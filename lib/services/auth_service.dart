import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/constants.dart';
import '../models/user_model.dart';
import 'notification_service.dart';
import 'api_service.dart';
import '../main.dart';

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

  AuthService() {
    // Hook automatic session expiry handler from ApiService
    ApiService.onUnauthorized = () {
      debugPrint('🔒 [AuthService] Session expired (401). Triggering automatic clean logout.');
      logout();
    };
  }

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
        ApiService.cachedToken = _token;
        
        // Mirror credentials across both secure storage and SharedPreferences for bulletproof resilience
        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', _token!);
          await prefs.setString('user_data', jsonEncode(_currentUser!.toJson()));
        } catch (_) {}
        
        // Background FCM Token Upload
        _uploadFcmToken();
        
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
        throw Exception(AppConstants.isProduction
            ? 'Connection timed out. Please check your internet connection or try again in a moment.'
            : 'Connection timed out. Ensure your phone and laptop are on the same Wi-Fi and the IP in constants.dart is correct.');
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
    ApiService.cachedToken = null;
    
    await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
    await _storage.delete(key: 'auth_token');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(_currentUser!.toJson()));
      await prefs.remove('auth_token');
    } catch (_) {}
    
    _isAuthenticating = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _isAuthenticated = false;
    _isAuthenticating = false;
    ApiService.cachedToken = null;
    ApiService.clearCache();

    // 1. Purge Secure Storage with individual fallback
    try {
      await _storage.deleteAll();
    } catch (e) {
      debugPrint('⚠️ Secure storage deleteAll notice: $e');
      try {
        await _storage.delete(key: 'auth_token');
        await _storage.delete(key: 'user_data');
        await _storage.delete(key: 'last_selected_route_id');
      } catch (_) {}
    }

    // 2. Purge SharedPreferences cached sessions and user routes
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('user_data');
      final keys = prefs.getKeys().where((k) => k.startsWith('api_cache_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (e) {
      debugPrint('⚠️ SharedPreferences clear notice: $e');
    }

    notifyListeners();

    // 3. Cleanly reset global navigation back to AuthWrapper
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    });
  }

  Future<void> tryAutoLogin() async {
    try {
      String? token;
      String? userDataStr;

      try {
        token = await _storage.read(key: 'auth_token');
        userDataStr = await _storage.read(key: 'user_data');
      } catch (e) {
        debugPrint('⚠️ SecureStorage read failed, falling back to SharedPreferences: $e');
      }

      if (token == null || userDataStr == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          token ??= prefs.getString('auth_token');
          userDataStr ??= prefs.getString('user_data');
        } catch (_) {}
      }

      if (token != null && userDataStr != null) {
        _token = token;
        final userMap = jsonDecode(userDataStr);
        final prefs = await SharedPreferences.getInstance();
        final localSkipped = prefs.getBool('commute_configured_${userMap['_id'] ?? userMap['id']}') ?? false;
        
        _currentUser = User.fromJson(userMap);
        if (localSkipped || (_currentUser!.routeId != null && _currentUser!.pickupPoint != null)) {
          _currentUser = _currentUser!.copyWith(isCommuteConfigured: true);
        }
        _isAuthenticated = true;
        ApiService.cachedToken = token;

        // Background FCM Token Upload
        _uploadFcmToken();
      } else {
        _token = null;
        _currentUser = null;
        _isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('⚠️ Error during tryAutoLogin: $e');
      _token = null;
      _currentUser = null;
      _isAuthenticated = false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  Future<void> updateProximityAlerts(bool enabled) async {
    if (_currentUser == null || _token == null) return;

    // Optimistic memory & local storage update
    _currentUser = _currentUser!.copyWith(proximityAlertsEnabled: enabled);
    notifyListeners();
    await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.apiUrl}/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'proximityAlertsEnabled': enabled}),
      ).timeout(const Duration(seconds: 8));

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

  Future<void> updateProximityRadius(double radius) async {
    if (_currentUser == null || _token == null) return;

    final clamped = radius.clamp(0.5, 3.0);
    // Optimistic memory & local storage update
    _currentUser = _currentUser!.copyWith(proximityRadiusKm: clamped);
    notifyListeners();
    await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));

    try {
      final response = await http.put(
        Uri.parse('${AppConstants.apiUrl}/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'proximityRadiusKm': clamped}),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentUser = User.fromJson(data);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating proximity radius: $e');
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

  Future<bool> forceChangePassword(String oldPassword, String newPassword) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.post(
        Uri.parse('${AppConstants.apiUrl}/auth/force-change-password'),
        headers: headers,
        body: jsonEncode({
          'username': _currentUser?.username,
          'currentPassword': oldPassword.trim(),
          'oldPassword': oldPassword.trim(),
          'newPassword': newPassword.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (data['token'] != null) {
          _token = data['token'];
          await _storage.write(key: 'auth_token', value: _token);
        }
        if (data['user'] != null) {
          _currentUser = User.fromJson(data['user']);
          await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        }
        notifyListeners();
        return true;
      } else {
        throw Exception(data['error'] ?? 'Failed to update password');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> updateCommuteSetup({
    required String routeId,
    required String pickupPoint,
    String? localAddress,
    String? name,
  }) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (_token != null) {
        headers['Authorization'] = 'Bearer $_token';
      }

      final response = await http.put(
        Uri.parse('${AppConstants.apiUrl}/users/profile'),
        headers: headers,
        body: jsonEncode({
          'routeId': routeId,
          'pickupPoint': pickupPoint,
          if (name != null && name.trim().isNotEmpty)
            'name': name.trim(),
          if (localAddress != null && localAddress.trim().isNotEmpty)
            'localAddress': localAddress.trim(),
          'isCommuteConfigured': true,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _currentUser = User.fromJson(data);
        await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', jsonEncode(_currentUser!.toJson()));
          await prefs.setBool('commute_configured_${_currentUser!.id}', true);
        } catch (_) {}
        notifyListeners();
        return true;
      } else {
        throw Exception(data['error'] ?? 'Failed to save commute setup');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Mark commute preferences as skipped so students can reach the dashboard immediately
  Future<void> skipCommuteSetup() async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(isCommuteConfigured: true);
    await _storage.write(key: 'user_data', value: jsonEncode(_currentUser!.toJson()));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', jsonEncode(_currentUser!.toJson()));
      await prefs.setBool('commute_configured_${_currentUser!.id}', true);
    } catch (_) {}
    notifyListeners();

    // Persist to backend asynchronously
    if (_token != null) {
      try {
        http.put(
          Uri.parse('${AppConstants.apiUrl}/users/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          body: jsonEncode({'isCommuteConfigured': true}),
        ).timeout(const Duration(seconds: 8)).then((_) {}).catchError((_) {});
      } catch (_) {}
    }
  }

  Future<void> _uploadFcmToken() async {
    if (_token == null) return;
    try {
      final fcmToken = await NotificationService().getDeviceToken();
      if (fcmToken == null) return;

      final response = await http.post(
        Uri.parse('${AppConstants.apiUrl}/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'token': fcmToken}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        debugPrint('🔑 [FCM] Token uploaded successfully.');
      } else {
        debugPrint('⚠️ [FCM] Failed to upload Token: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ [FCM] Error uploading Token: $e');
    }
  }
}


