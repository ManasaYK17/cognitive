import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const timeoutDuration = Duration(seconds: 10);
  static const int maxRequestAttempts = 3;
  static const Duration requestRetryDelay = Duration(seconds: 1);
  static const List<String> fallbackHosts = [
    '127.0.0.1:8000',     // Localhost via ADB forwarding (PRIMARY)
    '10.0.2.2:8000',      // Android emulator host access (fallback)
    '192.168.43.1:8000',  // Hotspot gateway (fallback)
    '10.0.3.2:8000',      // Alternative Android host access (fallback)
    '172.20.10.2:8000',   // PC LAN (fallback - usually unreachable on hotspot)
  ];

  static const String _tunnelHost = 'https://cognitive-assist-api.loca.lt';

  static List<String> get _candidateHosts {
    final configuredHost = const String.fromEnvironment('API_HOST', defaultValue: '').trim();
    final candidates = <String>[];

    if (configuredHost.isNotEmpty &&
        !configuredHost.contains('localhost') &&
        !configuredHost.contains('127.0.0.1')) {
      candidates.add(configuredHost);
    }

    candidates.addAll(fallbackHosts);
    candidates.add(_tunnelHost);
    return candidates;
  }

  static String get baseUrl {
    final host = _candidateHosts.first;
    final normalizedHost = host.startsWith('http://') || host.startsWith('https://')
        ? host
        : 'http://$host';
    return '$normalizedHost/api';
  }

  static Uri _buildUri(String host, String path, [Map<String, String>? params]) {
    final normalizedHost = host.startsWith('http://') || host.startsWith('https://')
        ? host
        : 'http://$host';
    final uri = Uri.parse('$normalizedHost/api$path');
    return params == null || params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  static Iterable<Uri> _candidateUris(String path, [Map<String, String>? params]) {
    return _candidateHosts.map((host) => _buildUri(host, path, params));
  }

  bool _isRetryableException(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException ||
        error is OSError;
  }

  Future<http.Response> _sendWithFallback(
    Future<http.Response> Function(http.Client client, Uri uri) requestFn,
    String path, {
    Map<String, String>? params,
    Duration timeout = timeoutDuration,
  }) async {
    final uris = _candidateUris(path, params);
    Exception? lastException;

    for (final uri in uris) {
      for (var attempt = 1; attempt <= maxRequestAttempts; attempt++) {
        final client = http.Client();
        try {
          if (kDebugMode) {
            debugPrint('ApiClient attempting ($attempt/$maxRequestAttempts): $uri');
          }
          final response = await requestFn(client, uri).timeout(timeout);
          return response;
        } on TimeoutException catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient timeout: $path at $uri ($attempt)');
        } on SocketException catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient socket error: $e at $uri ($attempt)');
        } on http.ClientException catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient client error: $e at $uri ($attempt)');
        } on OSError catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient OS error: $e at $uri ($attempt)');
        } catch (e) {
          if (e is Exception) {
            lastException = e;
          }
          if (kDebugMode) debugPrint('ApiClient unexpected error: $e at $uri ($attempt)');
        } finally {
          client.close();
        }

        if (attempt < maxRequestAttempts && _isRetryableException(lastException!)) {
          if (kDebugMode) debugPrint('ApiClient retrying after network error on $uri');
          await Future.delayed(requestRetryDelay);
          continue;
        }
        break;
      }
    }

    if (lastException != null) {
      throw lastException;
    }
    throw StateError('No valid API host was available for $path');
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
    Duration timeout = timeoutDuration,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return await _sendWithFallback(
      (client, uri) => client.post(uri, headers: headers, body: json.encode(body ?? {})),
      path,
      timeout: timeout,
    );
  }

  Future<http.Response> get(String path, {String? token, Map<String, String>? params, Duration timeout = timeoutDuration}) async {
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    return await _sendWithFallback(
      (client, uri) => client.get(uri, headers: headers),
      path,
      params: params,
      timeout: timeout,
    );
  }

  Future<http.Response> put(String path, {Map<String, dynamic>? body, String? token, Duration timeout = timeoutDuration}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return await _sendWithFallback(
      (client, uri) => client.put(uri, headers: headers, body: json.encode(body ?? {})),
      path,
      timeout: timeout,
    );
  }

  Future<http.Response> multipartPost(
    String path, {
    String? token,
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
    Duration timeout = timeoutDuration,
  }) async {
    Exception? lastException;

    for (final uri in _candidateUris(path)) {
      for (var attempt = 1; attempt <= maxRequestAttempts; attempt++) {
        final request = http.MultipartRequest('POST', uri);
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        if (fields != null) {
          request.fields.addAll(fields);
        }
        if (files != null) {
          request.files.addAll(files);
        }

        try {
          if (kDebugMode) {
            debugPrint('ApiClient attempting multipart ($attempt/$maxRequestAttempts): $uri');
          }
          final streamed = await request.send().timeout(timeout);
          final response = await http.Response.fromStream(streamed);
          return response;
        } on TimeoutException catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient multipart timeout: $path at $uri ($attempt)');
        } on SocketException catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient multipart socket error: $e at $uri ($attempt)');
        } on http.ClientException catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient multipart client error: $e at $uri ($attempt)');
        } on OSError catch (e) {
          lastException = e;
          if (kDebugMode) debugPrint('ApiClient multipart OS error: $e at $uri ($attempt)');
        } catch (e) {
          if (e is Exception) {
            lastException = e;
          }
          if (kDebugMode) debugPrint('ApiClient multipart unexpected error: $e at $uri ($attempt)');
        }

        if (attempt < maxRequestAttempts && lastException != null && _isRetryableException(lastException)) {
          if (kDebugMode) debugPrint('ApiClient multipart retrying after network error on $uri');
          await Future.delayed(requestRetryDelay);
          continue;
        }
        break;
      }
    }

    if (lastException != null) {
      throw lastException;
    }
    throw StateError('No valid API host was available for multipart $path');
  }

  http.MultipartRequest multipartRequest(String method, String path, {String? token}) {
    final uri = _buildUri(_candidateHosts.first, path);
    final request = http.MultipartRequest(method, uri);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }
}
