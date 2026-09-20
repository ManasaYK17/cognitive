import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/patient_location_screen.dart';
import '../screens/patient_recognition_result_screen.dart';
import 'auth_service.dart';
import 'recognition_service.dart';
import 'api_client.dart';
import 'realtime_event.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Lets this static service navigate and read Provider state without a
  /// BuildContext of its own. Assigned to MaterialApp(navigatorKey: ...).
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final StreamController<RealtimeEvent> _eventController = StreamController<RealtimeEvent>.broadcast();
  static final StreamController<void> _resumeController = StreamController<void>.broadcast();
  static final Set<String> _receivedEventIds = <String>{};
  static Stream<RealtimeEvent> get events => _eventController.stream;
  static Stream<void> get resumeEvents => _resumeController.stream;
  static void notifyResumed() {
    debugPrint('REALTIME_RECONNECT syncing REST-backed screens');
    _resumeController.add(null);
  }

  static const _pendingKnownPersonIdKey = 'pending_known_person_id';
  static const _pendingKnownPersonNameKey = 'pending_known_person_name';
  static const _pendingKnownPersonRelationshipKey = 'pending_known_person_relationship';
  static const _pendingKnownPersonSummaryKey = 'pending_known_person_summary';
  static const _pendingKnownPersonPatientIdKey = 'pending_known_person_patient_id';

  static const _pendingGeofencePatientIdKey = 'pending_geofence_patient_id';
  static const _pendingGeofencePatientNameKey = 'pending_geofence_patient_name';
  static const _pendingGeofenceLatKey = 'pending_geofence_lat';
  static const _pendingGeofenceLngKey = 'pending_geofence_lng';
  static const _pendingRealtimeEventsKey = 'pending_realtime_events';

  static Future<bool> openKnownPersonMatch(
    Map<String, dynamic> data, {
    String? sessionTokenOverride,
  }) async {
    if (data['match']?.toString().toLowerCase() != 'true') return false;
    final knownPersonId = int.tryParse(
      (data['known_person_id'] ?? data['id'])?.toString() ?? '',
    );
    if (knownPersonId == null) return false;
    final navigated = await _navigateToKnownPersonResult(
      knownPersonId: knownPersonId,
      patientId: int.tryParse(data['patient_id']?.toString() ?? ''),
      name: data['name'] as String?,
      relationship: data['relationship'] as String?,
      lastSummary: data['last_summary'] as String?,
      sessionTokenOverride: sessionTokenOverride,
    );
    if (!navigated) await _persistPendingKnownPersonPush(data);
    return navigated;
  }

  static Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    // Required on Android 13+ (POST_NOTIFICATIONS) and iOS for any
    // notification -- local or FCM -- to actually be shown to the user.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (response) async {
        // Local (tap-based) notifications are only ever shown for the
        // geofencing alert today; the known-person recognition push is
        // data-only and is handled via FirebaseMessaging.onMessage below
        // (foreground) and consumePendingKnownPersonPush (background/
        // killed), since it never produces a system notification to tap.
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = json.decode(payload) as Map<String, dynamic>;
          if (data['type'] == 'geofence_alert' && data['target_role'] != 'patient') {
            await _handleGeofenceAlertTap(data);
          }
        } catch (_) {}
      },
    );

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null && message.data['type'] != 'LOCATION_UPDATED' && message.data['type'] != 'geofence_alert') {
        _showNotification(
          message.notification!.title,
          message.notification!.body,
          payload: message.data.isNotEmpty ? json.encode(message.data) : null,
        );
      }
      _handleForegroundKnownPersonPush(message.data);
      _publishRealtimeEvent(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      openKnownPersonMatch(message.data);
      _publishRealtimeEvent(message.data);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await openKnownPersonMatch(initialMessage.data);
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  }

  static Future<void> _persistRealtimeEvent(Map<String, dynamic> data) async {
    final event = RealtimeEvent.fromMap(data);
    if (event.id.isEmpty || event.type.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingRealtimeEventsKey) ?? <String>[];
    if (!pending.any((item) => item.contains('"event_id":"${event.id}"'))) {
      pending.add(json.encode(data));
      await prefs.setStringList(_pendingRealtimeEventsKey, pending.length > 100 ? pending.sublist(pending.length - 100) : pending);
    }
  }

  static Future<void> consumePendingRealtimeEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingRealtimeEventsKey) ?? <String>[];
    if (pending.isEmpty) return;
    for (final encoded in pending) {
      try { _publishRealtimeEvent(json.decode(encoded) as Map<String, dynamic>); } catch (_) {}
    }
    await prefs.remove(_pendingRealtimeEventsKey);
  }

  static void _publishRealtimeEvent(Map<String, dynamic> data) {
    final event = RealtimeEvent.fromMap(data);
    if (event.id.isEmpty || event.type.isEmpty || _receivedEventIds.contains(event.id)) return;
    final context = navigatorKey.currentContext;
    final auth = context == null ? null : Provider.of<AuthService>(context, listen: false);
    final activeRole = auth?.patientSessionToken != null ? 'patient' : auth?.accessToken != null ? 'caregiver' : '';
    if (activeRole.isEmpty || event.targetRole != activeRole) return;
    _receivedEventIds.add(event.id);
    if (_receivedEventIds.length > 500) _receivedEventIds.remove(_receivedEventIds.first);
    debugPrint('REALTIME_EVENT_RECEIVED event_id=${event.id} type=${event.type} patient_id=${event.patientId} target_role=$activeRole');
    _eventController.add(event);
  }

  static Future<void> _handleForegroundKnownPersonPush(Map<String, dynamic> data) async {
    if (data['match']?.toString().toLowerCase() != 'true') return;
    final knownPersonId = int.tryParse(data['known_person_id']?.toString() ?? '');
    if (knownPersonId == null) return;
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty || name.toLowerCase().startsWith('unnamed') ||
        {'unknown', 'unknown person', 'person'}.contains(name.toLowerCase())) {
      return;
    }

    var navigated = await _navigateToKnownPersonResult(
      knownPersonId: knownPersonId,
      patientId: int.tryParse(data['patient_id']?.toString() ?? ''),
      name: name,
      relationship: data['relationship'] as String?,
      lastSummary: data['last_summary'] as String?,
    );
    if (!navigated) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      navigated = await _navigateToKnownPersonResult(
        knownPersonId: knownPersonId,
        patientId: int.tryParse(data['patient_id']?.toString() ?? ''),
        name: name,
        relationship: data['relationship'] as String?,
        lastSummary: data['last_summary'] as String?,
      );
    }
    if (!navigated) {
      await _persistPendingKnownPersonPush(data);
    }
  }

  /// Attempts to navigate straight to the recognition result screen for a
  /// known-person push. Requires an active patient session (sessionToken +
  /// patientId) and a live navigator; if either is missing, does nothing.
  /// Returns true if navigation happened.
  static Future<bool> _navigateToKnownPersonResult({
    required int knownPersonId,
    int? patientId,
    required String? name,
    required String? relationship,
    required String? lastSummary,
    String? sessionTokenOverride,
  }) async {
    final normalizedName = name?.trim().toLowerCase() ?? '';
    if (normalizedName.isEmpty || normalizedName.startsWith('unnamed') ||
        {'unknown', 'unknown person', 'person'}.contains(normalizedName)) {
      return false;
    }
    final context = navigatorKey.currentContext;
    if (context == null) return false;

    final authService = Provider.of<AuthService>(context, listen: false);
    final recognitionService = Provider.of<RecognitionService>(context, listen: false);
    var sessionToken = sessionTokenOverride ?? authService.patientSessionToken;
    var resolvedPatientId = recognitionService.patientId ?? patientId;
    if (sessionToken == null && resolvedPatientId != null) {
      final response = await ApiClient().post(
        '/recognition/issue-patient-session-token/',
        body: {'patient_id': resolvedPatientId, 'device_id': 'phone_push'},
      );
      if (response.statusCode == 200) {
        final payload = json.decode(response.body) as Map<String, dynamic>;
        sessionToken = payload['patient_session_token'] as String?;
        resolvedPatientId = payload['patient_id'] as int? ?? resolvedPatientId;
        if (sessionToken != null) {
          authService.setPatientSessionToken(sessionToken);
        }
      }
    }
    final activeSessionToken = sessionToken;
    final activePatientId = resolvedPatientId;
    final activeName = name;
    if (activeSessionToken == null || activePatientId == null || activeName == null || activeName.trim().isEmpty) return false;
    recognitionService.patientId = activePatientId;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PatientRecognitionResultScreen(
          patientId: activePatientId,
          knownPersonId: knownPersonId,
          knownPersonName: activeName,
          knownPersonRelationship: relationship,
          sessionToken: activeSessionToken,
          initialLastSummary: lastSummary,
          // Hardware recognition already records the conversation; the
          // phone should only show the result page.
          recordFromPhone: false,
        ),
      ),
    );
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    await _persistRealtimeEvent(message.data);
    if (message.notification != null) {
      await _showNotification(
        message.notification!.title,
        message.notification!.body,
        payload: message.data.isNotEmpty ? json.encode(message.data) : null,
      );
    }
    await _persistPendingKnownPersonPush(message.data);
  }

  /// Handles a tap on a geofence-breach local notification: navigates
  /// straight to the patient's live location if the app already has a
  /// live navigator + logged-in caregiver, otherwise stashes the payload
  /// for consumePendingGeofenceAlert() to pick up once it does (mirrors
  /// the known-person pending-push pattern above).
  static Future<void> _handleGeofenceAlertTap(Map<String, dynamic> data) async {
    final patientId = int.tryParse(data['patient_id']?.toString() ?? '');
    if (patientId == null) return;

    final navigated = _navigateToPatientLocation(
      patientId: patientId,
      patientName: data['patient_name'] as String?,
      latitude: double.tryParse(data['latitude']?.toString() ?? ''),
      longitude: double.tryParse(data['longitude']?.toString() ?? ''),
    );
    if (!navigated) {
      await _persistPendingGeofenceAlert(data);
    }
  }

  static bool _navigateToPatientLocation({
    required int patientId,
    required String? patientName,
    required double? latitude,
    required double? longitude,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return false;

    final auth = Provider.of<AuthService>(context, listen: false);
    if (auth.accessToken == null || auth.patientSessionToken != null) return false;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PatientLocationScreen(
          patientId: patientId,
          patientName: patientName ?? 'Patient',
          initialLatitude: latitude,
          initialLongitude: longitude,
        ),
      ),
    );
    return true;
  }

  static Future<void> _persistPendingGeofenceAlert(Map<String, dynamic> data) async {
    final patientId = int.tryParse(data['patient_id']?.toString() ?? '');
    if (patientId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingGeofencePatientIdKey, patientId);
    await _setOrRemove(prefs, _pendingGeofencePatientNameKey, data['patient_name'] as String?);
    await _setOrRemove(prefs, _pendingGeofenceLatKey, data['latitude'] as String?);
    await _setOrRemove(prefs, _pendingGeofenceLngKey, data['longitude'] as String?);
  }

  /// Call whenever the app regains a live caregiver session (resumed from
  /// background, or a fresh caregiver login just completed) to consume and
  /// act on any geofence alert tap received while the app couldn't
  /// navigate directly.
  static Future<void> consumePendingGeofenceAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt(_pendingGeofencePatientIdKey);
    if (patientId == null) return;

    final navigated = _navigateToPatientLocation(
      patientId: patientId,
      patientName: prefs.getString(_pendingGeofencePatientNameKey),
      latitude: double.tryParse(prefs.getString(_pendingGeofenceLatKey) ?? ''),
      longitude: double.tryParse(prefs.getString(_pendingGeofenceLngKey) ?? ''),
    );
    if (!navigated) return;

    await prefs.remove(_pendingGeofencePatientIdKey);
    await prefs.remove(_pendingGeofencePatientNameKey);
    await prefs.remove(_pendingGeofenceLatKey);
    await prefs.remove(_pendingGeofenceLngKey);
  }

  /// The background isolate has no navigatorKey/Provider tree, so a
  /// known-person push received while backgrounded or killed is stashed
  /// here instead of navigated to directly. consumePendingKnownPersonPush()
  /// picks it back up once the app has a live patient session again.
  static Future<void> _persistPendingKnownPersonPush(Map<String, dynamic> data) async {
    if (data['match']?.toString().toLowerCase() != 'true') return;
    final knownPersonId = int.tryParse(data['known_person_id']?.toString() ?? '');
    if (knownPersonId == null) return;
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty || name.toLowerCase().startsWith('unnamed') ||
        {'unknown', 'unknown person', 'person'}.contains(name.toLowerCase())) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingKnownPersonIdKey, knownPersonId);
    final patientId = int.tryParse(data['patient_id']?.toString() ?? '');
    if (patientId != null) await prefs.setInt(_pendingKnownPersonPatientIdKey, patientId);
    await _setOrRemove(prefs, _pendingKnownPersonNameKey, name);
    await _setOrRemove(prefs, _pendingKnownPersonRelationshipKey, data['relationship'] as String?);
    await _setOrRemove(prefs, _pendingKnownPersonSummaryKey, data['last_summary'] as String?);
  }

  static Future<void> _setOrRemove(SharedPreferences prefs, String key, String? value) {
    return value == null ? prefs.remove(key) : prefs.setString(key, value);
  }

  /// Call whenever the app regains a live patient session (resumed from
  /// background, or a fresh patient session was just established) to
  /// consume and act on any known-person push received while the app
  /// couldn't navigate directly.
  static Future<void> consumePendingKnownPersonPush() async {
    final prefs = await SharedPreferences.getInstance();
    final knownPersonId = prefs.getInt(_pendingKnownPersonIdKey);
    if (knownPersonId == null) return;

    final navigated = await _navigateToKnownPersonResult(
      knownPersonId: knownPersonId,
      patientId: prefs.getInt(_pendingKnownPersonPatientIdKey),
      name: prefs.getString(_pendingKnownPersonNameKey),
      relationship: prefs.getString(_pendingKnownPersonRelationshipKey),
      lastSummary: prefs.getString(_pendingKnownPersonSummaryKey),
    );
    if (!navigated) return;

    await prefs.remove(_pendingKnownPersonIdKey);
    await prefs.remove(_pendingKnownPersonNameKey);
    await prefs.remove(_pendingKnownPersonRelationshipKey);
    await prefs.remove(_pendingKnownPersonSummaryKey);
    await prefs.remove(_pendingKnownPersonPatientIdKey);
  }

  static Future<void> _showNotification(String? title, String? body, {String? payload}) async {
    const androidDetails = AndroidNotificationDetails(
      'cognitive_assist_channel',
      'Cognitive Assist Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iOSDetails = DarwinNotificationDetails();
    await _localNotifications.show(
      0,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iOSDetails),
      payload: payload,
    );
  }
}
