import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import 'audio_path.dart';

class AudioService extends ChangeNotifier {
  // Transcription + LLM summarization on the backend routinely takes longer
  // than ApiClient's default 10s (fine for quick JSON/image calls, too
  // short here) -- give this one room without leaving the request unbounded.
  static const _uploadTimeout = Duration(seconds: 60);

  final ApiClient _api = ApiClient();
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? lastSummaryMessage;

  bool get recording => _recording;

  Future<bool> ensurePermission() async {
    if (kIsWeb) return false;
    final permission = await Permission.microphone.request();
    return permission.isGranted;
  }

  Future<bool> startRecording() async {
    if (kIsWeb) return false;
    if (!await ensurePermission() || _recording) return false;

    final tempDir = Directory(systemTempPath);
    if (!tempDir.existsSync()) {
      tempDir.createSync(recursive: true);
    }

    final tempPath = '$systemTempPath$pathSeparator' 'cognitive_assist_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      await _recorder.start(const RecordConfig(), path: tempPath);
    } catch (error) {
      lastSummaryMessage = 'Unable to start recording: $error';
      notifyListeners();
      return false;
    }

    _recording = true;
    lastSummaryMessage = null;
    notifyListeners();
    return true;
  }

  Future<bool> stopRecordingAndSend(int patientId, int knownPersonId, String sessionToken) async {
    if (kIsWeb) {
      lastSummaryMessage = 'Audio recording not available on web.';
      notifyListeners();
      return false;
    }
    if (!_recording) return false;

    final path = await _recorder.stop();
    _recording = false;
    notifyListeners();

    if (path == null || path.isEmpty) {
      lastSummaryMessage = 'No audio recorded.';
      notifyListeners();
      return false;
    }

    try {
      final response = await _api.sendMultipart(
        'POST',
        '/conversations/summarize/',
        token: sessionToken,
        fields: {
          'known_person_id': knownPersonId.toString(),
          'patient_id': patientId.toString(),
        },
        files: [await http.MultipartFile.fromPath('audio', path)],
        timeout: _uploadTimeout,
      );
      if (response.statusCode == 201 || response.statusCode == 200 || response.statusCode == 207) {
        lastSummaryMessage = 'Conversation saved successfully.';
        notifyListeners();
        return true;
      }
    } catch (error) {
      debugPrint('AudioService.stopRecordingAndSend error: $error');
    }

    lastSummaryMessage = 'Failed to save conversation.';
    notifyListeners();
    return false;
  }

  Future<double?> getCurrentAmplitude() async {
    if (!_recording) return null;
    try {
      final amplitude = await _recorder.getAmplitude();
      return amplitude.current;
    } catch (_) {
      return null;
    }
  }
}
