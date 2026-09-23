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

// ─── Cache Entry ────────────────────────────────────────────────────────────

class _CacheEntry {
  final dynamic data;
  final DateTime expiry;
  _CacheEntry(this.data, this.expiry);
  bool get isExpired => DateTime.now().isAfter(expiry);
}

// ─── API Service ──────────────────────────────────────────────────────────────

/// High-performance HTTP client with:
/// - In-memory token caching to eliminate platform-channel storage reads on every request
/// - Short-lived in-memory response cache for read endpoints (routes, buses, etc.)
/// - Retry logic with exponential backoff
/// - Typed [ApiException] on all failure paths
class ApiService {
  static const int _maxRetries  = 3;
  static const int _timeoutSecs = 15;

  /// Global in-memory cached bearer token to avoid repeated platform-channel IPC reads
  static String? cachedToken;

  /// In-memory response cache for read queries
  static final Map<String, _CacheEntry> _cache = {};

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
    webOptions: WebOptions(
      dbName: 'SISTecChalo_db',
      publicKey: 'SISTecChalo_key',
    ),
  );

  /// Clears in-memory API response cache
  static void clearCache([String? endpointPrefix]) {
    if (endpointPrefix == null) {
      _cache.clear();
    } else {
      _cache.removeWhere((key, _) => key.startsWith(endpointPrefix));
    }
  }

  // ─── Headers ──────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers({bool requiresAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept'      : 'application/json',
    };
    if (requiresAuth) {
      String? token = cachedToken;
      if (token == null || token.isEmpty) {
        token = await _storage.read(key: 'auth_token');
        cachedToken = token;
      }
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Uri _uri(String endpoint) =>
      Uri.parse('${AppConstants.apiUrl}/$endpoint');

  // ─── Retry Wrapper ────────────────────────────────────────────────────────

  Future<dynamic> _withRetry(Future<http.Response> Function() call, {bool canRetry = true}) async {
    int attempt = 0;
    while (true) {
      try {
        final response = await call()
            .timeout(const Duration(seconds: _timeoutSecs));
        return _process(response);
      } on ApiException {
        rethrow; // Don't retry 4xx
      } on TimeoutException {
        if (!canRetry) {
          throw const ApiException(
            statusCode: 0,
            message   : 'Request timed out. Check your network connection.',
            isNetwork : true,
          );
        }
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
        if (!canRetry) {
          throw ApiException(
            statusCode: 0,
            message   : 'Network error: ${e.toString()}',
            isNetwork : true,
          );
        }
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

  Future<dynamic> get(
    String endpoint, {
    bool requiresAuth = true,
    bool useCache = false,
    Duration cacheDuration = const Duration(seconds: 30),
  }) async {
    if (useCache) {
      final cached = _cache[endpoint];
      if (cached != null && !cached.isExpired) {
        return cached.data;
      }
    }

    final data = await _withRetry(
      () async => http.get(
        _uri(endpoint),
        headers: await _headers(requiresAuth: requiresAuth),
      ),
      canRetry: true,
    );

    if (useCache && data != null) {
      _cache[endpoint] = _CacheEntry(data, DateTime.now().add(cacheDuration));
    }

    return data;
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {bool requiresAuth = true}) async {
    _cache.clear(); // Invalidate cache on mutations
    return _withRetry(() async => http.post(
          _uri(endpoint),
          headers: await _headers(requiresAuth: requiresAuth),
          body   : jsonEncode(body),
        ), canRetry: false);
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    _cache.clear(); // Invalidate cache on mutations
    return _withRetry(() async => http.put(
          _uri(endpoint),
          headers: await _headers(),
          body   : jsonEncode(body),
        ), canRetry: false);
  }

  Future<dynamic> patch(String endpoint, Map<String, dynamic> body) async {
    _cache.clear(); // Invalidate cache on mutations
    return _withRetry(() async => http.patch(
          _uri(endpoint),
          headers: await _headers(),
          body   : jsonEncode(body),
        ), canRetry: false);
  }

  Future<dynamic> delete(String endpoint) async {
    _cache.clear(); // Invalidate cache on mutations
    return _withRetry(() async => http.delete(
          _uri(endpoint),
          headers: await _headers(),
        ), canRetry: false);
  }
}


