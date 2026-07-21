import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
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
    final permission = await Permission.microphone.request();
    return permission.isGranted;
  }

  Future<bool> startRecording() async {
    if (kIsWeb) return false;
    if (!await ensurePermission() || _recording) return false;

    final tempPath = '/tmp/cognitive_assist_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: tempPath);
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

    final request = http.MultipartRequest('POST', Uri.parse('${ApiClient.baseUrl}/conversations/summarize/'));
    request.headers['Authorization'] = 'Bearer $sessionToken';
    request.fields['known_person_id'] = knownPersonId.toString();
    request.fields['patient_id'] = patientId.toString();
    request.files.add(await http.MultipartFile.fromPath('audio', path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 201 || response.statusCode == 200) {
      lastSummaryMessage = 'Conversation saved successfully.';
      notifyListeners();
      return true;
    }

    lastSummaryMessage = 'Failed to save conversation.';
    notifyListeners();
    return false;
  }
}
