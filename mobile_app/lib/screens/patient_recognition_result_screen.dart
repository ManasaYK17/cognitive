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
  bool _readyToStart = false;
  String? _lastSummary;
  String? _statusMessage;
  String? _errorMessage;
  double _volumeLevel = 0.0;
  Timer? _silenceTimer;
  Timer? _amplitudeMonitorTimer;

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
    try {
      await _fetchLastSummary();
      if (!mounted) return;
      await _speakSummary();
      if (!mounted) return;
      if (_readyToStart) {
        await _startRecording(autoStarted: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Unable to start conversation capture: $error';
        _statusMessage = 'Please tap Start Conversation to try again.';
      });
    }
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
      _readyToStart = true;
      _statusMessage = 'Ready to capture your conversation.';
    });
  }

  Future<void> _startRecording({bool autoStarted = false}) async {
    if (_recording || _sending) return;
    final audioService = Provider.of<AudioService>(context, listen: false);
    setState(() {
      _loading = false;
      _errorMessage = null;
      _statusMessage = 'Starting recording...';
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
      _statusMessage = 'Capturing conversation...';
      _readyToStart = false;
    });

    _startListeningMonitoring();
    if (!autoStarted) {
      _scheduleSilenceTimeout();
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _cancelSilenceMonitoring();

    setState(() {
      _recording = false;
      _sending = true;
      _statusMessage = 'Saving conversation...';
      _errorMessage = null;
    });

    final audioService = Provider.of<AudioService>(context, listen: false);
    final success = await audioService.stopRecordingAndSend(widget.patientId, widget.knownPersonId, widget.sessionToken);
    if (!mounted) return;

    setState(() {
      _sending = false;
      _statusMessage = success ? 'Conversation saved successfully. Returning home...' : 'Failed to save conversation. You can try again from home.';
    });

    if (success) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _scheduleSilenceTimeout() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 5), () {
      if (_recording) {
        setState(() {
          _statusMessage = 'No speech detected for 5 seconds. Stopping capture...';
        });
        _stopRecording();
      }
    });
  }

  void _startListeningMonitoring() {
    _amplitudeMonitorTimer?.cancel();
    _amplitudeMonitorTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!_recording) {
        _cancelSilenceMonitoring();
        return;
      }

      final audioService = Provider.of<AudioService>(context, listen: false);
      final amplitude = await audioService.getCurrentAmplitude();
      if (!mounted) return;

      setState(() {
        _volumeLevel = (amplitude ?? 0.0).clamp(0.0, 1.0);
      });

      if (amplitude != null && amplitude > 0.03) {
        _scheduleSilenceTimeout();
      }
    });
    _scheduleSilenceTimeout();
  }

  void _cancelSilenceMonitoring() {
    _silenceTimer?.cancel();
    _amplitudeMonitorTimer?.cancel();
    _volumeLevel = 0.0;
  }

  @override
  void dispose() {
    _cancelSilenceMonitoring();
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_statusMessage!, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
                ),
              if (_loading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_recording) ...[
                const SizedBox(height: 12),
                Text('Capturing conversation...', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _volumeLevel, minHeight: 10),
                const SizedBox(height: 8),
                Text(
                  _volumeLevel > 0.03 ? 'Listening...' : 'Waiting for speech...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
              const Spacer(),
              if (_sending)
                ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: const Text('Saving...'),
                )
              else if (_recording)
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop recording'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: Colors.red),
                )
              else
                ElevatedButton.icon(
                  onPressed: _readyToStart ? () => _startRecording(autoStarted: false) : null,
                  icon: const Icon(Icons.mic),
                  label: const Text('Start Conversation'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
