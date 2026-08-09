import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
void startLocationReportingCallback() {
  FlutterForegroundTask.setTaskHandler(LocationReportingTaskHandler());
}

/// Runs in a background isolate spun up by flutter_foreground_task's Android
/// foreground service, which keeps running (and keeps this isolate alive)
/// even after the Flutter UI/main activity is torn down -- including when
/// the app is swiped away from Recents. It has no access to the main
/// isolate's Provider state, so patientId/session token are read from
/// SharedPreferences (written by LocationService.startReporting) instead.
class LocationReportingTaskHandler extends TaskHandler {
  final ApiClient _api = ApiClient();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _reportLocation();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _reportLocation();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  Future<void> _reportLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getInt(LocationService.prefsPatientIdKey);
      final sessionToken = prefs.getString(LocationService.prefsSessionTokenKey);
      if (patientId == null || sessionToken == null) return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _api.post(
        '/patients/$patientId/location/',
        body: {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        token: sessionToken,
      );
    } catch (_) {
      // Best-effort -- the next scheduled ping (or the next time the app is
      // foregrounded) will retry. Nothing to surface this error to here.
    }
  }
}
