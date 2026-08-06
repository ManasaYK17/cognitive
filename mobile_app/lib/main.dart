import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/design_tokens.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/recognition_service.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/audio_service.dart';
import 'screens/face_scan_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  final authService = AuthService();
  ApiClient.onUnauthorized = authService.forceLogout;
  await authService.loadPersistedToken();
  runApp(CognitiveAssistApp(authService: authService));
}

class CognitiveAssistApp extends StatefulWidget {
  final AuthService authService;

  const CognitiveAssistApp({required this.authService, super.key});

  @override
  State<CognitiveAssistApp> createState() => _CognitiveAssistAppState();
}

class _CognitiveAssistAppState extends State<CognitiveAssistApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleAuthChange);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleAuthChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleAuthChange() {
    if (!widget.authService.sessionExpired) return;
    widget.authService.acknowledgeSessionExpired();

    final navigator = NotificationService.navigatorKey.currentState;
    navigator?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const FaceScanScreen()),
      (route) => false,
    );

    final context = NotificationService.navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your session expired. Please sign in again.')),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The periodic refresh timer in AuthService can be paused by the OS
      // while backgrounded -- catch up immediately on resume rather than
      // waiting for its next scheduled tick.
      widget.authService.refreshAccessToken();
      NotificationService.consumePendingKnownPersonPush();
      NotificationService.consumePendingGeofenceAlert();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.authService),
        ChangeNotifierProvider(create: (_) => RecognitionService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => AudioService()),
      ],
      child: MaterialApp(
        title: 'Cognitive Assist',
        navigatorKey: NotificationService.navigatorKey,
        theme: DesignTokens.darkTheme(),
        darkTheme: DesignTokens.darkTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const FaceScanScreen(),
      ),
    );
  }
}

