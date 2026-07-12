import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api_client.dart';

class LocationService extends ChangeNotifier {
  bool permissionGranted = false;
  bool permissionDenied = false;
  bool permissionPermanentlyDenied = false;
  bool isReporting = false;

  final ApiClient _api = ApiClient();
  Timer? _reportTimer;

  Future<void> initialize() async {
    final permission = await Geolocator.checkPermission();
    _updatePermissionFlags(permission);
  }

  Future<void> requestPermission() async {
    final permission = await Geolocator.requestPermission();
    _updatePermissionFlags(permission);
    if (permissionGranted) {
      notifyListeners();
    }
  }

  void _updatePermissionFlags(LocationPermission permission) {
    permissionGranted = permission == LocationPermission.always;
    permissionDenied = permission == LocationPermission.denied;
    permissionPermanentlyDenied = permission == LocationPermission.deniedForever;
    notifyListeners();
  }

  Future<void> startReporting(int patientId, String sessionToken, {Duration interval = const Duration(minutes: 3)}) async {
    if (!permissionGranted || isReporting) return;
    isReporting = true;
    _reportTimer?.cancel();
    await _sendLocation(patientId, sessionToken);
    _reportTimer = Timer.periodic(interval, (_) => _sendLocation(patientId, sessionToken));
    notifyListeners();
  }

  void stopReporting() {
    isReporting = false;
    _reportTimer?.cancel();
    _reportTimer = null;
    notifyListeners();
  }

  Future<void> _sendLocation(int patientId, String sessionToken) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
