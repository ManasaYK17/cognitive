import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const timeoutDuration = Duration(seconds: 10);

  // Set once at startup (see main.dart) to AuthService.forceLogout. Fired
  // whenever an authenticated request comes back 401, since that means the
  // token was rejected -- expired or cleared server-side -- not that this
  // particular call happened to fail.
  static void Function()? onUnauthorized;

  // Auth endpoints legitimately return 401 as part of normal flow (wrong
  // password, refresh token past its own lifetime) and handle it themselves
  // -- routing those through onUnauthorized too would either fire during a
  // failed login attempt or double up with AuthService's own handling.
  static const _unauthorizedExemptPaths = {
    '/accounts/login/',
    '/accounts/register/',
    '/accounts/token/refresh/',
  };

  void _reportIfUnauthorized(String path, String? token, http.Response response) {
    if (response.statusCode != 401) return;
    if (token == null || token.isEmpty) return;
    if (_unauthorizedExemptPaths.contains(path)) return;
    onUnauthorized?.call();
  }

  static List<String> getCandidateBaseUrls({
    String apiHost = const String.fromEnvironment(
      'API_HOST',
      defaultValue: '10.204.67.169:8000,10.0.2.2:8000,127.0.0.1:8000',
    ),
    String apiHostFallback = const String.fromEnvironment(
      'API_HOST_FALLBACK',
      defaultValue: '10.204.67.169:8000,10.0.2.2:8000',
    ),
  }) {
    final candidates = <String>{};
    void addCandidate(String rawHost) {
      final trimmed = rawHost.trim();
      if (trimmed.isEmpty) return;
      final normalized = trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? trimmed
          : 'http://$trimmed';
      final withoutTrailingSlash = normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
      candidates.add(withoutTrailingSlash);
    }

    for (final host in apiHost.split(',')) {
      addCandidate(host);
    }
    for (final host in apiHostFallback.split(',')) {
      addCandidate(host);
    }

    if (candidates.isEmpty) {
      candidates.add('http://127.0.0.1:8000');
    }

    return candidates.toList();
  }

  static String get baseUrl {
    final normalizedHosts = getCandidateBaseUrls();
    return '${normalizedHosts.first}/api';
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _sendWithFallback(
      (String baseUri) async {
        return http
            .post(
              Uri.parse('$baseUri$path'),
              headers: headers,
              body: json.encode(body ?? {}),
            )
            .timeout(timeoutDuration);
      },
      path: path,
      method: 'POST',
    );
    _reportIfUnauthorized(path, token, response);
    return response;
  }

  Future<http.Response> get(
    String path, {
    String? token,
    Map<String, String>? params,
  }) async {
    final response = await _sendWithFallback(
      (String baseUri) async {
        final uri = Uri.parse('$baseUri$path').replace(queryParameters: params);
        final headers = <String, String>{
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        };
        return http.get(uri, headers: headers).timeout(timeoutDuration);
      },
      path: path,
      method: 'GET',
    );
    _reportIfUnauthorized(path, token, response);
    return response;
  }

  Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _sendWithFallback(
      (String baseUri) async {
        return http
            .put(
              Uri.parse('$baseUri$path'),
              headers: headers,
              body: json.encode(body ?? {}),
            )
            .timeout(timeoutDuration);
      },
      path: path,
      method: 'PUT',
    );
    _reportIfUnauthorized(path, token, response);
    return response;
  }

  Future<http.Response> sendMultipart(
    String method,
    String path, {
    String? token,
    Map<String, String>? fields,
    List<http.MultipartFile> files = const [],
  }) async {
    final response = await _sendWithFallback(
      (String baseUri) async {
        final uri = Uri.parse('$baseUri$path');
        final request = http.MultipartRequest(method, uri);
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        if (fields != null) {
          request.fields.addAll(fields);
        }
        for (final file in files) {
          request.files.add(file);
        }
        final streamed = await request.send().timeout(timeoutDuration);
        return http.Response.fromStream(streamed);
      },
      path: path,
      method: method.toUpperCase(),
    );
    _reportIfUnauthorized(path, token, response);
    return response;
  }

  http.MultipartRequest multipartRequest(String method, String path,
      {String? token}) {
    final uri = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest(method, uri);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }

  Future<T> _sendWithFallback<T>(
    Future<T> Function(String baseUri) operation, {
    required String path,
    required String method,
  }) async {
    Object? lastError;
    final hosts = getCandidateBaseUrls();
    for (final host in hosts) {
      final baseUri = '$host/api';
      try {
        return await operation(baseUri);
      } on TimeoutException catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint('ApiClient.$method timeout for $path using $baseUri');
        }
      } on SocketException catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint('ApiClient.$method socket error for $path using $baseUri');
        }
      } on http.ClientException catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint('ApiClient.$method client error for $path using $baseUri');
        }
      }
    }

    if (lastError != null) {
      if (kDebugMode) {
        debugPrint('ApiClient.$method failed for $path after trying ${hosts.length} hosts');
      }
      throw lastError as Exception;
    }

    throw StateError('ApiClient.$method could not complete for $path');
  }
}
