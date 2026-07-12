import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/design_tokens.dart';
import 'services/auth_service.dart';
import 'services/recognition_service.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/audio_service.dart';
import 'screens/face_scan_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const CognitiveAssistApp());
}

class CognitiveAssistApp extends StatelessWidget {
  const CognitiveAssistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => RecognitionService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => AudioService()),
      ],
      child: MaterialApp(
        title: 'Cognitive Assist',
        theme: DesignTokens.lightTheme(),
        darkTheme: DesignTokens.darkTheme(),
        debugShowCheckedModeBanner: false,
        home: const FaceScanScreen(),
      ),
    );
  }
}

