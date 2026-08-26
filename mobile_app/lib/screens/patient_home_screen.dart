import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/recognition_service.dart';
import '../services/cognitive_features_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/face_scan_camera.dart';
import 'caregiver_dashboard_screen.dart';
import 'caregiver_login_screen.dart';
import 'patient_history_screen.dart';
import 'patient_recognition_result_screen.dart';
import 'cognitive_games_screen.dart';
import 'reminder_alarm_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  final int patientId;
  final String sessionToken;

  const PatientHomeScreen({required this.patientId, required this.sessionToken, super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final ApiClient _api = ApiClient();
  bool _scanning = false;
  bool _loadingMemories = true;
  List<dynamic> _recentMemories = [];
  final FlutterTts _flutterTts = FlutterTts();
  Timer? _recognitionPollTimer;
  String? _lastHardwareRecognitionTimestamp;
  bool _openingHardwareResult = false;
  bool _gameMode = false;
  Timer? _reminderTimer;
  bool _openingReminder = false;
  final CognitiveFeaturesService _features = CognitiveFeaturesService();

  @override
  void initState() {
    super.initState();
    // Deferred to after this build completes -- RecognitionService's
    // provider scope is an ancestor of this screen, and clearing it here
    // notifies listeners synchronously while that ancestor scope (and this
    // widget's own mounting) is still part of the current build pass,
    // which Flutter disallows ("setState() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<RecognitionService>(context, listen: false).clearRecognizedPerson();
    });
    _loadRecentMemories();
    unawaited(_initializeTts());
    // Hardware recognition can finish while the app is transitioning into
    // patient mode. Look back briefly so that match is not lost before the
    // polling timer starts.
    _lastHardwareRecognitionTimestamp = DateTime.now()
      .toUtc()
      .subtract(const Duration(minutes: 2))
      .toIso8601String();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareLocationReporting();
      _startRecognitionPolling();
      _checkReminders();
      _reminderTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkReminders());
    });
  }

  void _startRecognitionPolling() {
    _recognitionPollTimer?.cancel();
    _reminderTimer?.cancel();
    _recognitionPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      final response = await _api.get(
        '/history/patient-recognition/',
        token: widget.sessionToken,
        params: {if (_lastHardwareRecognitionTimestamp != null) 'after': _lastHardwareRecognitionTimestamp!},
      );
      debugPrint('[patient_home] recognition poll status=${response.statusCode} body=${response.body}');
      if (!mounted || response.statusCode != 200) return;
      final payload = json.decode(response.body) as Map<String, dynamic>;
      if (payload['match'] != true) return;
      final timestamp = payload['timestamp'] as String?;
      if (timestamp == null || timestamp == _lastHardwareRecognitionTimestamp) return;
      if (_openingHardwareResult) return;
      _openingHardwareResult = true;
      try {
        debugPrint('[patient_home] hardware match payload=$payload');
        final navigated = await _openHardwareResult(payload);
        if (navigated && mounted) {
          _lastHardwareRecognitionTimestamp = timestamp;
        }
      } catch (error, stackTrace) {
        debugPrint('[patient_home] failed to open hardware result: $error');
        debugPrint(stackTrace.toString());
      } finally {
        _openingHardwareResult = false;
      }
    });
  }

  Future<void> _checkReminders() async {
    if (!mounted || widget.sessionToken.isEmpty || _openingReminder) return;
    _openingReminder = true;
    try {
      final reminders = await _features.getReminders(widget.sessionToken);
      final triggered = reminders.cast<Map<String, dynamic>>().where((item) => item['status'] == 'triggered').toList();
      if (triggered.isNotEmpty && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReminderAlarmScreen(reminder: triggered.first, sessionToken: widget.sessionToken)));
      }
    } catch (_) {} finally { _openingReminder = false; }
  }

  Future<bool> _openHardwareResult(Map<String, dynamic> payload) async {
    final knownPersonId = int.tryParse(payload['known_person_id']?.toString() ?? '');
    final name = payload['name']?.toString().trim() ?? '';
    if (knownPersonId == null || name.isEmpty || !mounted) return false;

    debugPrint('[patient_home] pushing result screen for knownPersonId=$knownPersonId name=$name');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientRecognitionResultScreen(
          patientId: widget.patientId,
          knownPersonId: knownPersonId,
          knownPersonName: name,
          knownPersonRelationship: payload['relationship']?.toString(),
          sessionToken: widget.sessionToken,
          initialLastSummary: payload['last_summary']?.toString(),
          recordFromPhone: false,
        ),
      ),
    );
    return true;
  }

  @override
  void dispose() {
    _recognitionPollTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _initializeTts() async {
    try {
      await _flutterTts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  Future<void> _announceMessage(String message) async {
    if (message.trim().isEmpty) return;
    try {
      await _flutterTts.speak(message);
    } catch (_) {}
  }

  Future<void> _loadRecentMemories() async {
    setState(() => _loadingMemories = true);
    final response = await _api.get('/history/patient-view/', token: widget.sessionToken, params: {'limit': '5'});
    if (response.statusCode == 200) {
      setState(() {
        _recentMemories = json.decode(response.body) as List<dynamic>;
        _loadingMemories = false;
      });
      return;
    }
    setState(() => _loadingMemories = false);
  }

  Future<void> _confirmExitPatientMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exit patient mode?'),
        content: const Text('This closes the patient screen and returns to caregiver sign-in.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Exit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    authService.clearPatientSessionToken();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => authService.accessToken != null ? const CaregiverDashboardScreen() : const CaregiverLoginScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _prepareLocationReporting() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    await locationService.initialize();
    if (!locationService.permissionGranted && !locationService.permissionPermanentlyDenied) {
      await locationService.requestPermission();
    }
    if (locationService.permissionGranted) {
      await locationService.startReporting(widget.patientId, widget.sessionToken);
    }
  }

  Future<void> _attemptRecognition() async {
    if (widget.sessionToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient has not been enrolled yet. Caregiver must save the patient profile first.')),
      );
      return;
    }

    setState(() => _scanning = true);
    final recognitionService = Provider.of<RecognitionService>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    recognitionService.clearRecognizedPerson();

    Map<String, dynamic>? payload;
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = await navigator.push<FaceScanCaptureResult>(
        MaterialPageRoute(builder: (_) => const FaceScanCamera()),
      );
      if (!mounted) return;
      if (result == null || result.cancelled || result.image == null) {
        if (result?.message != null) {
          messenger.showSnackBar(SnackBar(content: Text(result!.message!)));
        }
        setState(() => _scanning = false);
        return;
      }
      final bytes = await result.image!.readAsBytes();
      payload = await recognitionService.attemptRecognitionFromBytes(
        bytes,
        result.image!.name,
        'phone_auto_capture',
        sessionTokenOverride: widget.sessionToken,
      );
      if (payload?['match'] == true) break;
    }
    if (!mounted) return;
    setState(() => _scanning = false);

    if (payload == null || payload['match'] != true) {
      const message = 'Unknown person detected';
      await _announceMessage(message);
      messenger.showSnackBar(
        const SnackBar(content: Text('Unknown person detected. Please try again.')),
      );
      return;
    }

    final knownPersonId = payload['id'] as int? ?? 0;
    final knownPersonName = payload['name'] as String? ?? 'Person';
    final knownPersonRelationship = payload['relationship'] as String?;
    if (knownPersonId != 0 && knownPersonName != 'Person') {
      await _announceMessage('Recognized $knownPersonName');
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PatientRecognitionResultScreen(
            patientId: widget.patientId,
            knownPersonId: knownPersonId,
            knownPersonName: knownPersonName,
            knownPersonRelationship: knownPersonRelationship,
            sessionToken: widget.sessionToken,
          ),
        ),
      );
      return;
    }

    await _announceMessage('Unknown person detected');
    messenger.showSnackBar(
      const SnackBar(content: Text('Unknown person detected. Please try again.')),
    );
  }

  Widget _buildTimeline() {
    if (_recentMemories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text('No recent memories yet.', style: TextStyle(color: Color.fromARGB(255, 200, 46, 46))),
      );
    }

    return Column(
      children: _recentMemories.map((entry) {
        final activity = entry as Map<String, dynamic>;
        final summary = activity['summary'] as String? ?? activity['last_summary'] as String? ?? 'No details available';
        final timestamp = activity['timestamp'] as String? ?? activity['created_at'] as String? ?? '';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(summary, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
          subtitle: Text(timestamp, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        );
      }).toList(),
    );
  }

  Widget _buildScanCard() {
    final recognitionService = Provider.of<RecognitionService>(context);
    final person = recognitionService.recognizedPerson;
    final isMatch = person != null && person['match'] == true;
    final recognizedName = isMatch ? person['name'] as String? : null;
    final hasEnrollmentToken = widget.sessionToken.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: (_scanning || !hasEnrollmentToken) ? null : _attemptRecognition,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: hasEnrollmentToken ? const Color(0xFF1F2937) : const Color(0xFF374151),
              shape: BoxShape.circle,
              border: Border.all(color: hasEnrollmentToken ? DesignTokens.accent : DesignTokens.subtleBorder, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.camera_alt,
                size: 84,
                color: hasEnrollmentToken ? DesignTokens.accent : Colors.white70,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          hasEnrollmentToken ? 'Scan using camera icon' : 'Ask caregiver to save patient profile first',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (_scanning)
          const CircularProgressIndicator(color: DesignTokens.accent)
        else if (person != null)
          Text(
            isMatch ? 'Recognized: $recognizedName' : 'Unknown person detected',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isMatch ? DesignTokens.success : Colors.orangeAccent),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recognitionService = Provider.of<RecognitionService>(context);
    final person = recognitionService.recognizedPerson;
    final statusText = widget.sessionToken.isEmpty
        ? 'Patient not enrolled yet. Caregiver must save profile before scan.'
        : person != null
            ? (person['match'] == true ? 'Recognized: ${person['name']}' : 'Unknown person detected')
            : 'Ready to scan';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _gameMode ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _gameMode = false)) : null,
        title: _gameMode ? const Text('Cognitive Games') : null,
        actions: [
          Row(children: [const Text('Games', style: TextStyle(fontSize: 15)), Switch(value: _gameMode, onChanged: (value) => setState(() => _gameMode = value))]),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            tooltip: 'Exit to caregiver sign-in',
            onPressed: _confirmExitPatientMode,
          ),
        ],
      ),
        body: _gameMode
          ? CognitiveGamesScreen(patientId: widget.patientId, sessionToken: widget.sessionToken)
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              Text(statusText, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              const SizedBox(height: 16),
              _buildScanCard(),
              const SizedBox(height: 20),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientHistoryScreen(sessionToken: widget.sessionToken)));
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: Colors.white, side: const BorderSide(color: DesignTokens.accent)),
                child: const Text('People I’ve talked to'),
              ),
              const SizedBox(height: 20),
              Align(alignment: Alignment.centerLeft, child: Text('Recent memories', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white))),
              const SizedBox(height: 12),
              if (_loadingMemories)
                const Center(child: CircularProgressIndicator())
              else
                _buildTimeline(),
            ],
          ),
        ),
      ),
    );
  }
}
