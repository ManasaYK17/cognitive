import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/patient_recognition_result_screen.dart';
import 'auth_service.dart';
import 'recognition_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Lets this static service navigate and read Provider state without a
  /// BuildContext of its own. Assigned to MaterialApp(navigatorKey: ...).
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const _pendingKnownPersonIdKey = 'pending_known_person_id';
  static const _pendingKnownPersonNameKey = 'pending_known_person_name';
  static const _pendingKnownPersonRelationshipKey = 'pending_known_person_relationship';
  static const _pendingKnownPersonSummaryKey = 'pending_known_person_summary';

  static Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

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
      },
    );

    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        _showNotification(message.notification!.title, message.notification!.body);
      }
      _handleForegroundKnownPersonPush(message.data);
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  }

  static void _handleForegroundKnownPersonPush(Map<String, dynamic> data) {
    final knownPersonId = int.tryParse(data['known_person_id']?.toString() ?? '');
    if (knownPersonId == null) return;

    _navigateToKnownPersonResult(
      knownPersonId: knownPersonId,
      name: data['name'] as String?,
      relationship: data['relationship'] as String?,
      lastSummary: data['last_summary'] as String?,
    );
  }

  /// Attempts to navigate straight to the recognition result screen for a
  /// known-person push. Requires an active patient session (sessionToken +
  /// patientId) and a live navigator; if either is missing, does nothing.
  /// Returns true if navigation happened.
  static bool _navigateToKnownPersonResult({
    required int knownPersonId,
    required String? name,
    required String? relationship,
    required String? lastSummary,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return false;

    final sessionToken = Provider.of<AuthService>(context, listen: false).patientSessionToken;
    final patientId = Provider.of<RecognitionService>(context, listen: false).patientId;
    if (sessionToken == null || patientId == null) return false;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PatientRecognitionResultScreen(
          patientId: patientId,
          knownPersonId: knownPersonId,
          knownPersonName: name ?? 'Person',
          knownPersonRelationship: relationship,
          sessionToken: sessionToken,
          initialLastSummary: lastSummary,
        ),
      ),
    );
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    if (message.notification != null) {
      await _showNotification(message.notification!.title, message.notification!.body);
    }
    await _persistPendingKnownPersonPush(message.data);
  }

  /// The background isolate has no navigatorKey/Provider tree, so a
  /// known-person push received while backgrounded or killed is stashed
  /// here instead of navigated to directly. consumePendingKnownPersonPush()
  /// picks it back up once the app has a live patient session again.
  static Future<void> _persistPendingKnownPersonPush(Map<String, dynamic> data) async {
    final knownPersonId = int.tryParse(data['known_person_id']?.toString() ?? '');
    if (knownPersonId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pendingKnownPersonIdKey, knownPersonId);
    await _setOrRemove(prefs, _pendingKnownPersonNameKey, data['name'] as String?);
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

    final navigated = _navigateToKnownPersonResult(
      knownPersonId: knownPersonId,
      name: prefs.getString(_pendingKnownPersonNameKey),
      relationship: prefs.getString(_pendingKnownPersonRelationshipKey),
      lastSummary: prefs.getString(_pendingKnownPersonSummaryKey),
    );
    if (!navigated) return;

    await prefs.remove(_pendingKnownPersonIdKey);
    await prefs.remove(_pendingKnownPersonNameKey);
    await prefs.remove(_pendingKnownPersonRelationshipKey);
    await prefs.remove(_pendingKnownPersonSummaryKey);
  }

  static Future<void> _showNotification(String? title, String? body) async {
    const androidDetails = AndroidNotificationDetails(
      'cognitive_assist_channel',
      'Cognitive Assist Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iOSDetails = DarwinNotificationDetails();
    await _localNotifications.show(0, title, body, const NotificationDetails(android: androidDetails, iOS: iOSDetails));
  }
}
