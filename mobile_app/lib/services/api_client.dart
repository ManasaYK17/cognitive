import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const timeoutDuration = Duration(seconds: 10);

  static List<String> getCandidateBaseUrls({
    String apiHost = const String.fromEnvironment(
      'API_HOST',
      defaultValue: 'https://cognitive-assist-backend.onrender.com,10.0.2.2:8000,127.0.0.1:8000',
    ),
    String apiHostFallback = const String.fromEnvironment(
      'API_HOST_FALLBACK',
      defaultValue: '192.168.1.8:8000,10.0.2.2:8000',
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

    return _sendWithFallback(
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
  }

  Future<http.Response> get(
    String path, {
    String? token,
    Map<String, String>? params,
  }) async {
    return _sendWithFallback(
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

    return _sendWithFallback(
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
  }

  Future<http.Response> sendMultipart(
    String method,
    String path, {
    String? token,
    Map<String, String>? fields,
    List<http.MultipartFile> files = const [],
  }) async {
    return _sendWithFallback(
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
