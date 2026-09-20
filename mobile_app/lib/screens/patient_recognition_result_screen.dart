import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import '../services/app_language.dart';
import '../services/audio_service.dart';

class PatientRecognitionResultScreen extends StatefulWidget {
  final int patientId;
  final int knownPersonId;
  final String knownPersonName;
  final String? knownPersonRelationship;
  final String sessionToken;
  final String? initialLastSummary;
  final bool recordFromPhone;

  const PatientRecognitionResultScreen({
    required this.patientId,
    required this.knownPersonId,
    required this.knownPersonName,
    this.knownPersonRelationship,
    required this.sessionToken,
    this.initialLastSummary,
    this.recordFromPhone = true,
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
  static const _languageKey = 'patient_selected_conversation_language';
  static const List<String> _supportedLanguages = ['English', 'Kannada', 'Telugu', 'Tamil', 'Hindi'];
  String _selectedLanguage = 'English';

  @override
  void initState() {
    super.initState();
    _lastSummary = widget.initialLastSummary?.trim().isNotEmpty == true ? widget.initialLastSummary : null;
    _loadSelectedLanguage();
    _initializeTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAndCapture());
  }

  Future<void> _loadSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_languageKey) ?? 'English';
    if (!mounted) return;
    setState(() {
      _selectedLanguage = _supportedLanguages.contains(stored) ? stored : 'English';
    });
  }

  Future<void> _saveSelectedLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language);
    final appLanguage = Provider.of<AppLanguage>(context, listen: false);
    await appLanguage.setLanguage(language);
    if (mounted) setState(() => _selectedLanguage = language);
  }

  Future<void> _initializeTts() async {
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _loadAndCapture() async {
    final appLanguage = Provider.of<AppLanguage>(context, listen: false);
    try {
      await _fetchLastSummary();
      if (!mounted) return;
      await _speakSummary();
      if (!mounted) return;
      if (_readyToStart && widget.recordFromPhone) {
        await _startRecording(autoStarted: true);
      } else if (_readyToStart) {
        // Detection came from the specs hardware, which is already
        // recording the conversation itself -- the phone should only
        // surface the last summary here, not start a second recording.
        setState(() {
          _loading = false;
          _readyToStart = false;
          _statusMessage = 'Your glasses are capturing this conversation.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Unable to start conversation capture: $error';
        _statusMessage = '${appLanguage.translate('start_conversation')}';
      });
    }
  }

  Future<void> _fetchLastSummary() async {
    if (_lastSummary != null) return;
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
    final appLanguage = Provider.of<AppLanguage>(context, listen: false);
    final relationshipLabel = widget.knownPersonRelationship?.trim().isNotEmpty == true
        ? ' your ${widget.knownPersonRelationship}'
        : '';
    final speakText = _lastSummary?.trim().isNotEmpty == true
        ? 'Recognized ${widget.knownPersonName}$relationshipLabel. Last summary: ${_lastSummary!}. Please speak when ready and the app will capture your conversation.'
        : 'Recognized ${widget.knownPersonName}$relationshipLabel. Please speak when ready and the app will capture your conversation.';

    setState(() {
      _statusMessage = appLanguage.translate('speaking_last_summary');
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
      _statusMessage = appLanguage.translate('ready_to_capture');
    });
  }

  Future<void> _startRecording({bool autoStarted = false}) async {
    if (_recording || _sending) return;
    final appLanguage = Provider.of<AppLanguage>(context, listen: false);
    final audioService = Provider.of<AudioService>(context, listen: false);
    setState(() {
      _loading = false;
      _errorMessage = null;
      _statusMessage = appLanguage.translate('starting_recording');
    });

    final started = await audioService.startRecording();
    if (!mounted) return;

    if (!started) {
      setState(() {
        _errorMessage = appLanguage.translate('microphone_required');
        _statusMessage = appLanguage.translate('recording_not_started');
      });
      return;
    }

    setState(() {
      _recording = true;
      _statusMessage = appLanguage.translate('capturing_conversation');
      _readyToStart = false;
    });

    _startListeningMonitoring();
    if (!autoStarted) {
      _scheduleSilenceTimeout();
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    final appLanguage = Provider.of<AppLanguage>(context, listen: false);
    _cancelSilenceMonitoring();

    setState(() {
      _recording = false;
      _sending = true;
      _statusMessage = appLanguage.translate('saving');
      _errorMessage = null;
    });

    final audioService = Provider.of<AudioService>(context, listen: false);
    final success = await audioService.stopRecordingAndSend(
      widget.patientId,
      widget.knownPersonId,
      widget.sessionToken,
      language: _selectedLanguage,
    );
    if (!mounted) return;

    setState(() {
      _sending = false;
      _statusMessage = success ? appLanguage.translate('conversation_saved_success') : appLanguage.translate('conversation_save_failed');
      if (!success) {
        // Surface the detailed message from AudioService (parsed server
        // response or upload error) to the UI so users see why save failed.
        _errorMessage = audioService.lastSummaryMessage ?? appLanguage.translate('conversation_save_failed');
      }
    });

    if (success) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _scheduleSilenceTimeout() {
    final appLanguage = Provider.of<AppLanguage>(context, listen: false);
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 5), () {
      if (_recording) {
        setState(() {
          _statusMessage = appLanguage.translate('no_speech_detected');
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
    final appLanguage = Provider.of<AppLanguage>(context);
    final languageMenuButton = PopupMenuButton<String>(
      tooltip: 'Select language',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (value) async {
        await _saveSelectedLanguage(value);
      },
      itemBuilder: (context) => _supportedLanguages
          .map((language) => PopupMenuItem<String>(
                value: language,
                child: Text(
                  language,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: language == _selectedLanguage ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ))
          .toList(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Recognized: ${widget.knownPersonName}'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: const Color(0xFF212121),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.knownPersonName,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                          ),
                          if (widget.knownPersonRelationship?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Relationship: ${widget.knownPersonRelationship}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            widget.recordFromPhone ? 'Conversation capture is active.' : 'Your glasses are recording this conversation.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          if (_lastSummary != null) ...[
                            Text(
                              'Last conversation',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(_lastSummary!, style: const TextStyle(fontSize: 15, color: Colors.white70)),
                          ] else ...[
                            const Text('No previous conversation found.', style: TextStyle(fontSize: 15, color: Colors.white70)),
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
                    LinearProgressIndicator(value: _volumeLevel.clamp(0.0, 1.0), minHeight: 10),
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
                  else if (widget.recordFromPhone)
                    ElevatedButton.icon(
                      onPressed: _readyToStart ? () => _startRecording(autoStarted: false) : null,
                      icon: const Icon(Icons.mic),
                      label: const Text('Start Conversation'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      child: const Text('Back to Home'),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  languageMenuButton,
                  const SizedBox(width: 6),
                  Text(
                    _selectedLanguage,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
