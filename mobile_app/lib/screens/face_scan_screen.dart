import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/recognition_service.dart';
import 'caregiver_dashboard_screen.dart';
import 'caregiver_login_screen.dart';
import 'patient_mode_screen.dart';
import '../widgets/face_scan_camera.dart';

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen> {
  bool _scanning = false;
  String _statusMessage = 'Checking who\'s here...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _statusMessage = 'Scanning for a known patient...';
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    final captureResult = await Navigator.of(context).push<FaceScanCaptureResult>(
      MaterialPageRoute(builder: (_) => const FaceScanCamera(timeoutSeconds: 18)),
    );

    if (!mounted) return;

    if (captureResult == null || captureResult.cancelled || captureResult.image == null) {
      setState(() {
        _scanning = false;
        _statusMessage = captureResult?.message ?? 'No face detected';
      });
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => authService.accessToken != null ? const CaregiverDashboardScreen() : const CaregiverLoginScreen(),
        ),
      );
      return;
    }

    final recognitionService = Provider.of<RecognitionService>(context, listen: false);
    final bytes = await captureResult.image!.readAsBytes();
    debugPrint('[face_scan_screen] captured image bytes=${bytes.length} name=${captureResult.image!.name}');
    final result = await recognitionService.attemptPatientRecognitionFromBytes(bytes, captureResult.image!.name, 'phone_auto_capture');
    debugPrint('[face_scan_screen] recognition result: $result');

    if (!mounted) return;

    if (result != null && result['match'] == true && recognitionService.sessionToken != null) {
      authService.setPatientSessionToken(recognitionService.sessionToken!);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PatientModeScreen()),
      );
      return;
    }

    setState(() {
      _scanning = false;
      _statusMessage = 'No matching patient found';
    });
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => authService.accessToken != null ? const CaregiverDashboardScreen() : const CaregiverLoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(64), width: 8),
                ),
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary.withAlpha(38),
                    ),
                    child: const Center(child: Icon(Icons.face_retouching_natural, size: 40)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_scanning)
                const CircularProgressIndicator()
              else
                const SizedBox(height: 24),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
