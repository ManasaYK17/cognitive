import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';

class AudioService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? lastSummaryMessage;

  bool get recording => _recording;

  Future<bool> ensurePermission() async {
    if (kIsWeb) return false;
    return await _recorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (kIsWeb) return;
    if (await _recorder.hasPermission() && !_recording) {
      final tempPath = '/tmp/cognitive_assist_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: tempPath);
      _recording = true;
      notifyListeners();
    }
  }

  Future<void> stopRecordingAndSend(int patientId, int knownPersonId, String sessionToken) async {
    if (kIsWeb) {
      lastSummaryMessage = 'Audio recording not available on web.';
      notifyListeners();
      return;
    }
    if (!_recording) return;
    final path = await _recorder.stop();
    _recording = false;
    notifyListeners();

    if (path == null) {
      lastSummaryMessage = 'No audio recorded.';
      notifyListeners();
      return;
    }

    final request = http.MultipartRequest('POST', Uri.parse('${ApiClient.baseUrl}/conversations/summarize/'));
    request.headers['Authorization'] = 'Bearer $sessionToken';
    request.fields['known_person_id'] = knownPersonId.toString();
    request.fields['patient_id'] = patientId.toString();
    request.files.add(await http.MultipartFile.fromPath('audio_file', path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 201 || response.statusCode == 200) {
      lastSummaryMessage = 'Conversation saved successfully';
    } else {
      lastSummaryMessage = 'Failed to save conversation';
    }
    notifyListeners();
  }
}
