import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'notification_service.dart';

class AuthService extends ChangeNotifier {
  static const _accessTokenPrefsKey = 'caregiver_access_token';
  static const _refreshTokenPrefsKey = 'caregiver_refresh_token';

  // Refresh proactively well before the access token's actual lifetime
  // (SIMPLE_JWT.ACCESS_TOKEN_LIFETIME in settings.py, currently 15 minutes)
  // so the session stays alive through normal use instead of requests
  // silently failing once it goes stale.
  static const _proactiveRefreshInterval = Duration(minutes: 12);

  String? _accessToken;
  String? _refreshToken;
  String? _patientSessionToken;
  Timer? _refreshTimer;

  String? get accessToken => _accessToken;
  String? get patientSessionToken => _patientSessionToken;
  String? _lastError;
  String? get lastError => _lastError;

  // Set when a request comes back 401 with a token attached (or the refresh
  // token itself is rejected) -- the app shell listens for this and
  // navigates back to the login flow, since a silently-cleared session
  // otherwise just leaves every screen re-fetching into empty states.
  bool sessionExpired = false;
  bool _forcingLogout = false;

  final ApiClient _client = ApiClient();

  AuthService() {
    if (!kIsWeb) {
      // Whenever FCM rotates the device's token, re-register it for
      // whichever patient session is currently active.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _registerPatientDeviceToken(firebaseToken: newToken);
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void setPatientSessionToken(String token) {
    _patientSessionToken = token;
    notifyListeners();
    _registerPatientDeviceToken();
    NotificationService.consumePendingKnownPersonPush();
  }

  // Exits patient kiosk mode without touching the caregiver's own
  // access/refresh tokens -- unlike logout(), a caregiver who was already
  // signed in should land back on their dashboard, not be signed out too.
  void clearPatientSessionToken() {
    _patientSessionToken = null;
    notifyListeners();
  }

  // Restores a caregiver session saved by a previous run -- without this,
  // _accessToken (in-memory only otherwise) resets to null on every app
  // restart, silently dropping the Authorization header on every request
  // until the caregiver logs in again. Call once at startup, before the
  // widget tree that reads accessToken is built.
  Future<void> loadPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenPrefsKey);
    _refreshToken = prefs.getString(_refreshTokenPrefsKey);
    if (_refreshToken != null) {
      // The persisted access token may already be stale by the time the app
      // restarts (its lifetime is short -- 15 minutes) -- get a live one
      // immediately instead of waiting for the first request to fail.
      await refreshAccessToken();
      _startProactiveRefresh();
    }
  }

  Future<void> _persistTokens({String? access, String? refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    if (access == null) {
      await prefs.remove(_accessTokenPrefsKey);
    } else {
      await prefs.setString(_accessTokenPrefsKey, access);
    }
    if (refresh == null) {
      await prefs.remove(_refreshTokenPrefsKey);
    } else {
      await prefs.setString(_refreshTokenPrefsKey, refresh);
    }
  }

  void _startProactiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_proactiveRefreshInterval, (_) => refreshAccessToken());
  }

  // Exchanges the stored refresh token for a new access token
  // (POST /accounts/token/refresh/, backed by CaregiverTokenRefreshView).
  // Only forces a logout when the server actively rejects the refresh
  // token (401 -- expired past its own 7-day lifetime, or invalid); a
  // transport failure (server down/restarting, no network) just fails this
  // attempt and leaves the existing session alone, so the next proactive
  // tick or app restart can retry once the server's back -- this is what
  // previously forced a manual logout/login after simply restarting the
  // backend during development.
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final response = await _client.post('/accounts/token/refresh/', body: {'refresh': _refreshToken});
      if (response.statusCode == 200) {
        final payload = json.decode(response.body) as Map<String, dynamic>;
        final newAccess = payload['access'] as String?;
        if (newAccess != null) {
          _accessToken = newAccess;
          await _persistTokens(access: _accessToken, refresh: _refreshToken);
          notifyListeners();
          return true;
        }
      } else if (response.statusCode == 401) {
        await forceLogout();
      }
      return false;
    } catch (error) {
      debugPrint('AuthService.refreshAccessToken error: $error');
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final response = await _client.post(
        '/accounts/login/',
        body: {
          'email': email,
          'password': password,
        },
      );
      if (response.statusCode == 200) {
        final payload = json.decode(response.body) as Map<String, dynamic>;
        _accessToken = payload['access'] as String?;
        _refreshToken = payload['refresh'] as String?;
        _lastError = null;
        await _persistTokens(access: _accessToken, refresh: _refreshToken);
        if (_refreshToken != null) _startProactiveRefresh();
        await _registerDeviceToken();
        notifyListeners();
        NotificationService.consumePendingGeofenceAlert();
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
    } catch (error, stackTrace) {
      debugPrint('AuthService.login error (${error.runtimeType}): $error');
      debugPrint('AuthService.login stack trace: $stackTrace');
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
        _refreshToken = payload['refresh'] as String?;
        _lastError = null;
        await _persistTokens(access: _accessToken, refresh: _refreshToken);
        if (_refreshToken != null) _startProactiveRefresh();
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
    _refreshTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    _patientSessionToken = null;
    await _persistTokens(access: null, refresh: null);
    notifyListeners();
  }

  // Called when the backend rejects a request as unauthorized -- expired or
  // cleared token -- rather than the user tapping "Log out" themselves.
  // Clears the session and flips `sessionExpired` so the app shell can
  // navigate back to the login flow and let the user know why.
  Future<void> forceLogout() async {
    if (_forcingLogout) return;
    if (_accessToken == null && _refreshToken == null && _patientSessionToken == null) return;
    _forcingLogout = true;
    await logout();
    sessionExpired = true;
    notifyListeners();
    _forcingLogout = false;
  }

  void acknowledgeSessionExpired() {
    sessionExpired = false;
  }

  Future<void> _registerDeviceToken() async {
    if (kIsWeb) return;
    final firebaseToken = await FirebaseMessaging.instance.getToken();
    if (firebaseToken == null || _accessToken == null) return;
    await _client.post('/accounts/register-device-token/',
        body: {'device_token': firebaseToken}, token: _accessToken);
  }

  Future<void> _registerPatientDeviceToken({String? firebaseToken}) async {
    if (kIsWeb) return;
    final token = firebaseToken ?? await FirebaseMessaging.instance.getToken();
    if (token == null || _patientSessionToken == null) return;
    try {
      await _client.post('/recognition/register-patient-device-token/',
          body: {'device_token': token}, token: _patientSessionToken);
    } catch (error) {
      debugPrint('AuthService._registerPatientDeviceToken error: $error');
    }
  }
}
