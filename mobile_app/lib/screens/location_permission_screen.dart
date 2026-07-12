import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  Future<void> _requestPermission() async {
    if (kIsWeb) {
      if (!mounted) return;
      Navigator.of(context).pop(false);
      return;
    }
    final status = await Permission.locationAlways.request();
    if (!mounted) return;
    if (status.isGranted) {
      Navigator.of(context).pop(true);
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      appBar: AppBar(
        title: const Text('Location Permission'),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Background location access helps caregivers know when the patient is safe and when help may be needed.',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 24),
            const Text(
              'This permission is requested once during setup and is only used to report the patient’s location to the caregiver dashboard when the app is active.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(60),
              ),
              onPressed: _requestPermission,
              child: const Text('Allow Location Access'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(60),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Maybe Later'),
            ),
          ],
        ),
      ),
    );
  }
}
