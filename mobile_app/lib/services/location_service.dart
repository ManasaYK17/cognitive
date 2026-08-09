import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'background_location_task_handler.dart';

class LocationService extends ChangeNotifier {
  // Shared with the Android background isolate (background_location_task_handler.dart),
  // which has no access to this instance's state and reads these back out of
  // SharedPreferences instead.
  static const prefsPatientIdKey = 'location_reporting_patient_id';
  static const prefsSessionTokenKey = 'location_reporting_session_token';

  bool permissionGranted = false;
  bool permissionDenied = false;
  bool permissionPermanentlyDenied = false;
  bool isReporting = false;

  final ApiClient _api = ApiClient();
  Timer? _reportTimer;
  StreamSubscription<Position>? _positionSubscription;
  DateTime? _lastIosReportAt;

  Future<void> initialize() async {
    final status = await Permission.locationAlways.status;
    _updatePermissionFlags(status);
  }

  /// Background ("always") location can't be granted in a single dialog on
  /// Android 10+ -- the OS only offers it once foreground access is already
  /// granted, so foreground is requested first and background second.
  Future<void> requestPermission() async {
    var status = await Permission.locationWhenInUse.request();
    if (status.isGranted) {
      status = await Permission.locationAlways.request();
    }
    _updatePermissionFlags(status);
    if (!permissionGranted) return;
    notifyListeners();

    if (!kIsWeb && Platform.isAndroid) {
      // Best-effort: OEM battery managers (Xiaomi/Samsung/OnePlus, etc.) can
      // still kill a foreground service despite Android's own
      // stopWithTask=false guarantee -- exempting from battery optimization
      // makes that much less likely. One-time native dialog.
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  void _updatePermissionFlags(PermissionStatus status) {
    permissionGranted = status.isGranted;
    permissionDenied = status.isDenied || status.isRestricted;
    permissionPermanentlyDenied = status.isPermanentlyDenied;
    notifyListeners();
  }

  Future<void> startReporting(int patientId, String sessionToken, {Duration interval = const Duration(minutes: 3)}) async {
    if (!permissionGranted || isReporting) return;
    isReporting = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsPatientIdKey, patientId);
    await prefs.setString(prefsSessionTokenKey, sessionToken);

    if (!kIsWeb && Platform.isAndroid) {
      await _startAndroidForegroundReporting(interval);
    } else if (!kIsWeb && Platform.isIOS) {
      await _sendLocation(patientId, sessionToken);
      _startIosBackgroundReporting(patientId, sessionToken, interval);
    } else {
      // Dev/desktop/web targets have no real background-execution story --
      // keep the original best-effort in-process timer for these.
      await _sendLocation(patientId, sessionToken);
      _reportTimer = Timer.periodic(interval, (_) => _sendLocation(patientId, sessionToken));
    }

    notifyListeners();
  }

  Future<void> _startAndroidForegroundReporting(Duration interval) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_reporting_channel',
        channelName: 'Location sharing',
        channelDescription: "Shares this patient's location with their caregiver while patient mode is active.",
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(interval.inMilliseconds),
        // The service + GPS reads are enough to keep this reliable without
        // holding a full wake lock, which would keep the CPU running
        // between reads too -- heavier than this needs.
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'Location sharing active',
      notificationText: "Cognitive Assist is sharing this patient's location with the caregiver.",
      callback: startLocationReportingCallback,
    );
  }

  void _startIosBackgroundReporting(int patientId, String sessionToken, Duration interval) {
    _positionSubscription?.cancel();
    _lastIosReportAt = DateTime.now();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: AppleSettings(
        accuracy: LocationAccuracy.high,
        // Apple requires distanceFilter to be unset/0 for background
        // updates to keep flowing (iOS 16.4+).
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
    ).listen((position) {
      final now = DateTime.now();
      if (_lastIosReportAt != null && now.difference(_lastIosReportAt!) < interval) return;
      _lastIosReportAt = now;
      _postLocation(patientId, sessionToken, position);
    });
  }

  Future<void> stopReporting() async {
    if (!isReporting) return;
    isReporting = false;

    if (!kIsWeb && Platform.isAndroid) {
      await FlutterForegroundTask.stopService();
    }
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _reportTimer?.cancel();
    _reportTimer = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsPatientIdKey);
    await prefs.remove(prefsSessionTokenKey);

    notifyListeners();
  }

  Future<void> _sendLocation(int patientId, String sessionToken) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _postLocation(patientId, sessionToken, position);
    } catch (err) {
      debugPrint('Location report error: $err');
    }
  }

  Future<void> _postLocation(int patientId, String sessionToken, Position position) async {
    try {
      final response = await _api.post(
        '/patients/$patientId/location/',
        body: {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        token: sessionToken,
      );
      if (response.statusCode != 200) {
        debugPrint('Location report failed: ${response.statusCode}');
      }
    } catch (err) {
      debugPrint('Location report error: $err');
    }
  }
}
