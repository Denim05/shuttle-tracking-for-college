import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/constants.dart';

// ─── Custom Exception ─────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int    statusCode;
  final String message;
  final bool   isNetwork;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.isNetwork = false,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden    => statusCode == 403;
  bool get isNotFound     => statusCode == 404;
  bool get isServerError  => statusCode >= 500;
}

// ─── API Service ──────────────────────────────────────────────────────────────

/// Robust HTTP client with:
/// - Auto-injected bearer token
/// - Retry logic (3 attempts, exponential backoff: 1s, 2s, 4s)
/// - Typed [ApiException] on all failure paths
/// - Standard CRUD + PATCH methods
class ApiService {
  static const int _maxRetries  = 3;
  static const int _timeoutSecs = 20;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
    webOptions: WebOptions(
      dbName: 'SISTecChalo_db',
      publicKey: 'SISTecChalo_key',
    ),
  );

  // ─── Headers ──────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers({bool requiresAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept'      : 'application/json',
    };
    if (requiresAuth) {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Uri _uri(String endpoint) =>
      Uri.parse('${AppConstants.apiUrl}/$endpoint');

  // ─── Retry Wrapper ────────────────────────────────────────────────────────

  Future<dynamic> _withRetry(Future<http.Response> Function() call) async {
    int attempt = 0;
    while (true) {
      try {
        final response = await call()
            .timeout(const Duration(seconds: _timeoutSecs));
        return _process(response);
      } on ApiException {
        rethrow; // Don't retry 4xx
      } on TimeoutException {
        attempt++;
        if (attempt >= _maxRetries) {
          throw const ApiException(
            statusCode: 0,
            message   : 'Request timed out. Check your network connection.',
            isNetwork : true,
          );
        }
        await Future.delayed(Duration(seconds: 1 << attempt));
      } catch (e) {
        attempt++;
        if (attempt >= _maxRetries) {
          throw ApiException(
            statusCode: 0,
            message   : 'Network error: ${e.toString()}',
            isNetwork : true,
          );
        }
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }

  // ─── Response Processor ───────────────────────────────────────────────────

  dynamic _process(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (_) {
        throw const ApiException(
          statusCode: 0,
          message   : 'Server returned malformed JSON.',
        );
      }
    }

    String message = 'Server error (${response.statusCode})';
    try {
      final body = jsonDecode(response.body);
      message = (body['error'] ?? body['message'] ?? message).toString();
    } catch (_) {}

    throw ApiException(statusCode: response.statusCode, message: message);
  }

  // ─── Public Methods ───────────────────────────────────────────────────────

  Future<dynamic> get(String endpoint, {bool requiresAuth = true}) =>
      _withRetry(() async => http.get(
            _uri(endpoint),
            headers: await _headers(requiresAuth: requiresAuth),
          ));

  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
          {bool requiresAuth = true}) =>
      _withRetry(() async => http.post(
            _uri(endpoint),
            headers: await _headers(requiresAuth: requiresAuth),
            body   : jsonEncode(body),
          ));

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) =>
      _withRetry(() async => http.put(
            _uri(endpoint),
            headers: await _headers(),
            body   : jsonEncode(body),
          ));

  Future<dynamic> patch(String endpoint, Map<String, dynamic> body) =>
      _withRetry(() async => http.patch(
            _uri(endpoint),
            headers: await _headers(),
            body   : jsonEncode(body),
          ));

  Future<dynamic> delete(String endpoint) =>
      _withRetry(() async => http.delete(
            _uri(endpoint),
            headers: await _headers(),
          ));
}


