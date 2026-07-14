import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const timeoutDuration = Duration(seconds: 10);
  // Use localhost for device builds and adb reverse forwarding to the host machine.
  // Override with --dart-define=API_HOST=10.0.2.2:8000 for emulator builds.
  static String get baseUrl {
    const apiHost = String.fromEnvironment('API_HOST', defaultValue: '127.0.0.1:8000');
    final normalizedHost = apiHost.startsWith('http://') || apiHost.startsWith('https://')
        ? apiHost
        : 'http://$apiHost';
    return '$normalizedHost/api';
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
    try {
      return await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: headers,
            body: json.encode(body ?? {}),
          )
          .timeout(timeoutDuration);
    } on TimeoutException {
      if (kDebugMode) debugPrint('ApiClient.post timeout: $path');
      rethrow;
    }
  }

  Future<http.Response> get(String path, {String? token, Map<String, String>? params}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: params);
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    return await http.get(uri, headers: headers).timeout(timeoutDuration);
  }

  Future<http.Response> put(String path, {Map<String, dynamic>? body, String? token}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return await http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: headers,
          body: json.encode(body ?? {}),
        )
        .timeout(timeoutDuration);
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
