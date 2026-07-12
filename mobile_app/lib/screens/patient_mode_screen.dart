import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/recognition_service.dart';
import '../services/location_service.dart';
import '../services/audio_service.dart';
import 'patient_home_screen.dart';

class PatientModeScreen extends StatelessWidget {
  const PatientModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final recognitionService = Provider.of<RecognitionService>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final sessionToken = authService.patientSessionToken;
    final patientId = recognitionService.patientId ?? 0;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: Provider.of<LocationService>(context, listen: false)),
        ChangeNotifierProvider.value(value: Provider.of<AudioService>(context, listen: false)),
      ],
      child: PatientHomeScreen(
        sessionToken: sessionToken ?? '',
        patientId: patientId,
      ),
    );
  }
}
