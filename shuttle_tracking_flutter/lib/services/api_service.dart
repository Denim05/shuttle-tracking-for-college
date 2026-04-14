import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/constants.dart';

/// A robust HTTP client wrapper handling token-based authorization and standard JSON parsing
/// for executing requests against the primary backend API.
class ApiService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, String>> _getHeaders() async {
    String? token = await _storage.read(key: 'auth_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Executes an HTTP GET request to the specified [endpoint].
  /// Injects bearer token automatically.
  Future<dynamic> get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.apiUrl}/$endpoint'),
        headers: await _getHeaders(),
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Connection Error: $e');
    }
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConstants.apiUrl}/$endpoint'),
        headers: await _getHeaders(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      return _processResponse(response);
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Server connection timed out. The cloud might be waking up...');
      }
      throw Exception('Connection failed. Please check your internet or ensure backend changes are pushed to GitHub.');
    }
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    try {
       final response = await http.put(
        Uri.parse('${AppConstants.apiUrl}/$endpoint'),
        headers: await _getHeaders(),
        body: jsonEncode(body),
      );
      return _processResponse(response);
    } catch (e) {
       throw Exception('Failed to connect to server');
    }
  }

  Future<dynamic> delete(String endpoint) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConstants.apiUrl}/$endpoint'),
        headers: await _getHeaders(),
      );
      return _processResponse(response);
    } catch (e) {
      throw Exception('Failed to connect to server');
    }
  }

  dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return jsonDecode(response.body);
      } catch (e) {
        throw Exception('Server returned invalid data (not JSON). Check your backend status.');
      }
    } else {
      var error = 'Server Error (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        error = body['error'] ?? body['message'] ?? error;
      } catch (_) {
        error = 'Network Error: Ensure your backend is running on port 5000.';
      }
      throw Exception(error);
    }
  }
}
