import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const timeoutDuration = Duration(seconds: 10);
  static const int defaultRetryAttempts = 1;
  static const Duration defaultRetryDelay = Duration(seconds: 1);
  static const List<String> fallbackHosts = [
    '127.0.0.1:8000',
    '172.20.10.2:8000',
    '192.168.43.1:8000',
    '10.0.2.2:8000',
    '10.0.3.2:8000',
  ];

  static String get baseUrl {
    const localHost = '127.0.0.1:8000';
    const tunnelHost = 'https://legal-carrots-fall.loca.lt';
    final configuredHost = const String.fromEnvironment('API_HOST', defaultValue: '').trim();
    final candidates = <String>[];

    if (configuredHost.isNotEmpty &&
        !configuredHost.contains('localhost') &&
        !configuredHost.contains('127.0.0.1')) {
      candidates.add(configuredHost);
    }

    candidates.add(localHost);
    candidates.add(tunnelHost);
    candidates.addAll(fallbackHosts);

    final apiHost = candidates.firstWhere(
      (host) => host.isNotEmpty,
      orElse: () => tunnelHost,
    );
    final normalizedHost = apiHost.startsWith('http://') || apiHost.startsWith('https://')
        ? apiHost
        : 'http://$apiHost';
    return '$normalizedHost/api';
  }

  bool _isRetryableError(Object error) {
    return error is SocketException || error is http.ClientException || error is TimeoutException;
  }

  Future<T> _retryRequest<T>(
    Future<T> Function() operation, {
    required String path,
    int maxRetries = defaultRetryAttempts,
    Duration delay = defaultRetryDelay,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        final retryable = _isRetryableError(error);
        if (!retryable || attempt >= maxRetries) {
          if (kDebugMode) {
            debugPrint('ApiClient._retryRequest[$path] final failure (${error.runtimeType}): $error');
            debugPrint(stackTrace.toString());
          }
          rethrow;
        }
        if (kDebugMode) {
          debugPrint('ApiClient._retryRequest[$path] network error (${error.runtimeType}): $error');
          debugPrint('ApiClient._retryRequest[$path] retrying in ${delay.inSeconds}s (attempt ${attempt + 1} of ${maxRetries + 1})');
        }
        attempt += 1;
        await Future.delayed(delay);
      }
    }
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
    Duration? timeout,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return await _retryRequest(
      () async {
        final client = http.Client();
        try {
          return await client
              .post(
                Uri.parse('$baseUrl$path'),
                headers: headers,
                body: json.encode(body ?? {}),
              )
              .timeout(timeout ?? timeoutDuration);
        } finally {
          client.close();
        }
      },
      path: path,
    );
  }

  Future<http.Response> get(String path, {String? token, Map<String, String>? params, Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    return await _retryRequest(
      () async {
        final client = http.Client();
        try {
          return await client.get(uri, headers: headers).timeout(timeout ?? timeoutDuration);
        } finally {
          client.close();
        }
      },
      path: path,
    );
  }

  Future<http.Response> put(String path, {Map<String, dynamic>? body, String? token, Duration? timeout}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return await _retryRequest(
      () async {
        final client = http.Client();
        try {
          return await client
              .put(
                Uri.parse('$baseUrl$path'),
                headers: headers,
                body: json.encode(body ?? {}),
              )
              .timeout(timeout ?? timeoutDuration);
        } finally {
          client.close();
        }
      },
      path: path,
    );
  }

  http.MultipartRequest multipartRequest(String method, String path, {String? token}) {
    final uri = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest(method, uri);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }
}
