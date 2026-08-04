import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../services/recognition_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/face_scan_camera.dart';
import 'caregiver_login_screen.dart';
import 'patient_history_screen.dart';
import 'patient_recognition_result_screen.dart';

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

  @override
  void initState() {
    super.initState();
    final recognitionService = Provider.of<RecognitionService>(context, listen: false);
    recognitionService.clearRecognizedPerson();
    _loadRecentMemories();
    unawaited(_initializeTts());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareLocationReporting();
    });
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

    final result = await navigator.push<FaceScanCaptureResult>(
      MaterialPageRoute(builder: (_) => const FaceScanCamera()),
    );

    if (!mounted) return;
    setState(() => _scanning = false);

    if (result == null || result.cancelled || result.image == null) {
      if (result?.message != null) {
        messenger.showSnackBar(SnackBar(content: Text(result!.message!)));
      }
      return;
    }

    final bytes = await result.image!.readAsBytes();
    final payload = await recognitionService.attemptRecognitionFromBytes(
      bytes,
      result.image!.name,
      'phone_auto_capture',
      sessionTokenOverride: widget.sessionToken,
    );
    if (payload == null || payload['id'] == null) {
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
    final shouldOpenResult = payload['match'] == true || knownPersonId != 0;
    if (shouldOpenResult) {
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              Text(statusText, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              const SizedBox(height: 16),
              Expanded(child: Center(child: _buildScanCard())),
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
