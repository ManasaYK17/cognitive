import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/audio_service.dart';
import '../theme/design_tokens.dart';

class PatientRecognitionResultScreen extends StatefulWidget {
  final int patientId;
  final int knownPersonId;
  final String knownPersonName;
  final String? knownPersonRelationship;
  final String sessionToken;

  const PatientRecognitionResultScreen({
    required this.patientId,
    required this.knownPersonId,
    required this.knownPersonName,
    this.knownPersonRelationship,
    required this.sessionToken,
    super.key,
  });

  @override
  State<PatientRecognitionResultScreen> createState() => _PatientRecognitionResultScreenState();
}

class _PatientRecognitionResultScreenState extends State<PatientRecognitionResultScreen> {
  final ApiClient _api = ApiClient();
  final FlutterTts _flutterTts = FlutterTts();
  bool _loading = true;
  bool _recording = false;
  bool _sending = false;
  String? _lastSummary;
  String? _statusMessage;
  String? _errorMessage;
  Timer? _autoStopTimer;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAndCapture());
  }

  Future<void> _initializeTts() async {
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _loadAndCapture() async {
    await _fetchLastSummary();
    if (!mounted) return;
    await _speakSummary();
    if (!mounted) return;
    await _startRecording();
  }

  Future<void> _fetchLastSummary() async {
    final response = await _api.get(
      '/history/patient-view/',
      token: widget.sessionToken,
      params: {'known_person_id': widget.knownPersonId.toString()},
    );

    if (response.statusCode == 200) {
      final items = json.decode(response.body) as List<dynamic>;
      if (items.isNotEmpty) {
        _lastSummary = items.first['last_summary'] as String? ?? items.first['summary'] as String?;
      }
    }
  }

  Future<void> _speakSummary() async {
    final relationshipLabel = widget.knownPersonRelationship?.trim().isNotEmpty == true
        ? ' your ${widget.knownPersonRelationship}'
        : '';
    final speakText = _lastSummary?.trim().isNotEmpty == true
        ? 'Recognized ${widget.knownPersonName}$relationshipLabel. Last summary: ${_lastSummary!}. Please speak when ready and the app will capture your conversation.'
        : 'Recognized ${widget.knownPersonName}$relationshipLabel. Please speak when ready and the app will capture your conversation.';

    setState(() {
      _statusMessage = 'Speaking last summary...';
      _errorMessage = null;
    });

    try {
      final completer = Completer<void>();
      _flutterTts.setCompletionHandler(() {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      _flutterTts.setErrorHandler((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await _flutterTts.speak(speakText);
      await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    } catch (_) {
      // If speech fails, continue to recording anyway.
    }

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Preparing to record your conversation...';
    });
  }

  Future<void> _startRecording() async {
    final audioService = Provider.of<AudioService>(context, listen: false);
    setState(() {
      _loading = false;
      _statusMessage = 'Starting recording...';
      _errorMessage = null;
    });

    final started = await audioService.startRecording();
    if (!mounted) return;

    if (!started) {
      setState(() {
        _errorMessage = 'Microphone permission is required to record your conversation.';
        _statusMessage = 'Recording not started.';
      });
      return;
    }

    setState(() {
      _recording = true;
      _statusMessage = 'Recording conversation. Tap stop when finished.';
    });

    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 25), _stopRecording);
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _autoStopTimer?.cancel();

    setState(() {
      _recording = false;
      _sending = true;
      _statusMessage = 'Saving conversation...';
    });

    final audioService = Provider.of<AudioService>(context, listen: false);
    final success = await audioService.stopRecordingAndSend(widget.patientId, widget.knownPersonId, widget.sessionToken);
    if (!mounted) return;

    setState(() {
      _sending = false;
      _statusMessage = success ? 'Conversation saved successfully. Returning home...' : 'Failed to save conversation. You can try again from home.';
    });

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recognized: ${widget.knownPersonName}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: DesignTokens.lightSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.knownPersonName, style: Theme.of(context).textTheme.titleLarge),
                      if (widget.knownPersonRelationship?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text('Relationship: ${widget.knownPersonRelationship}', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 8),
                      Text('Conversation capture is active.', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      if (_lastSummary != null) ...[
                        const Text('Last conversation', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_lastSummary!, style: const TextStyle(fontSize: 15, color: Colors.black87)),
                      ] else ...[
                        const Text('No previous conversation found.', style: TextStyle(fontSize: 15, color: Colors.black87)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_statusMessage != null)
                Text(_statusMessage!, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
              if (_loading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
              const Spacer(),
              if (_recording)
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop recording'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: Colors.red),
                )
              else if (!_loading && !_sending)
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: const Text('Back to home'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
