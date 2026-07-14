import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  String? _accessToken;
  String? _patientSessionToken;

  String? get accessToken => _accessToken;
  String? get patientSessionToken => _patientSessionToken;
  String? _lastError;
  String? get lastError => _lastError;

  final ApiClient _client = ApiClient();

  void setPatientSessionToken(String token) {
    _patientSessionToken = token;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final response = await _client.post('/accounts/login/', body: {
        'email': email,
        'password': password,
      });
      if (response.statusCode == 200) {
        final payload = json.decode(response.body) as Map<String, dynamic>;
        _accessToken = payload['access'] as String?;
        _lastError = null;
        await _registerDeviceToken();
        notifyListeners();
        return true;
      }
      try {
        final err = json.decode(response.body);
        if (err is Map) {
          _lastError = err['detail']?.toString() ??
              err['non_field_errors']?.join(' ')?.toString() ??
              err.toString();
        } else {
          _lastError = err.toString();
        }
      } catch (_) {
        _lastError = 'Login failed. Please check your credentials and try again.';
      }
      return false;
    } catch (error) {
      debugPrint('AuthService.login error: $error');
      _lastError = 'Unable to reach the backend. Please verify the server is running.';
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    try {
      // split full name into first/last for the API
      final parts = name.trim().split(RegExp(r"\s+"));
      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      final response = await _client.post('/accounts/register/', body: {
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'password': password,
        'password_confirm': password,
      });
      if (response.statusCode == 201 || response.statusCode == 200) {
        final payload = json.decode(response.body) as Map<String, dynamic>;
        _accessToken = payload['access'] as String?;
        _lastError = null;
        notifyListeners();
        return true;
      }
      // capture backend error message if available
      try {
        final err = json.decode(response.body);
        _lastError = err is Map ? (err['detail'] ?? err.toString()) : err.toString();
      } catch (_) {
        _lastError = response.body;
      }
      return false;
    } catch (error) {
      debugPrint('AuthService.register error: $error');
      _lastError = error.toString();
      return false;
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _patientSessionToken = null;
    notifyListeners();
  }

  Future<void> _registerDeviceToken() async {
    if (kIsWeb) return;
    final firebaseToken = await FirebaseMessaging.instance.getToken();
    if (firebaseToken == null || _accessToken == null) return;
    await _client.post('/accounts/register-device-token/',
        body: {'device_token': firebaseToken}, token: _accessToken);
  }
}
