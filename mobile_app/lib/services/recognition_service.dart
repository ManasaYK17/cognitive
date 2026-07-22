import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../services/api_client.dart';

class RecognitionService extends ChangeNotifier {
  String? sessionToken;
  int? patientId;
  Map<String, dynamic>? recognizedPerson;

  Future<bool> performRecognition() async {
    if (kIsWeb) {
      return false;
    }
    final cameraPermission = await Permission.camera.request();
    if (!cameraPermission.isGranted) {
      return false;
    }

    final imagePath = await _captureImage();
    if (imagePath == null) {
      return false;
    }

    final result = await attemptRecognition(imagePath, 'phone_camera');
    if (result != null) {
      sessionToken = result['session_token'] as String?;
      patientId = result['patient_id'] as int?;
      recognizedPerson = result;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> performPatientRecognition() async {
    if (kIsWeb) {
      return null;
    }

    final cameraPermission = await Permission.camera.request();
    if (!cameraPermission.isGranted) {
      return null;
    }

    final imagePath = await _captureImage();
    if (imagePath == null) {
      return null;
    }

    final result = await attemptPatientRecognition(imagePath, 'phone_camera');
    if (result != null) {
      sessionToken = result['patient_session_token'] as String? ?? result['session_token'] as String?;
      patientId = result['patient_id'] as int?;
      recognizedPerson = result;
      notifyListeners();
      return result;
    }

    sessionToken = null;
    patientId = null;
    recognizedPerson = null;
    notifyListeners();
    return null;
  }

  Future<Map<String, dynamic>?> attemptRecognitionFromBytes(Uint8List bytes, String filename, String source, {String? sessionTokenOverride}) async {
    try {
      final token = sessionTokenOverride ?? sessionToken;
      if (token == null || token.isEmpty) {
        return null;
      }

      final uri = Uri.parse('${ApiClient.baseUrl}/recognition/identify-known-person/');
      final request = http.MultipartRequest('POST', uri);
      request.fields['source'] = source;
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return null;
      final payload = json.decode(response.body) as Map<String, dynamic>;
      final match = payload['match'] == true;
      if (match) {
        sessionToken = token;
        patientId = payload['patient_id'] as int?;
        recognizedPerson = payload;
      } else {
        recognizedPerson = null;
      }
      notifyListeners();
      return payload;
    } catch (_) {
      return null;
    }
  }

  void clearRecognizedPerson() {
    recognizedPerson = null;
    notifyListeners();
  }

  /// Attempt to recognize a patient using raw image bytes. Useful on web where
  /// a file path is not available.
  Future<Map<String, dynamic>?> attemptPatientRecognitionFromBytes(Uint8List bytes, String filename, String source) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/recognition/identify-patient/');
      debugPrint('[recognition_service] posting patient recognition bytes=${bytes.length} filename=$filename source=$source to $uri');
      final request = http.MultipartRequest('POST', uri);
      request.fields['source'] = source;
      request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      debugPrint('[recognition_service] response status=${response.statusCode} body=${response.body}');
      if (response.statusCode != 200) return null;
      final payload = json.decode(response.body) as Map<String, dynamic>;
      // populate local state so callers can rely on RecognitionService state
      sessionToken = payload['patient_session_token'] as String? ?? payload['session_token'] as String?;
      patientId = payload['patient_id'] as int?;
      recognizedPerson = payload;
      notifyListeners();
      return payload;
    } catch (error, stackTrace) {
      debugPrint('[recognition_service] recognition upload failed: $error');
      debugPrint(stackTrace.toString());
      return null;
    }
  }

  Future<String?> _captureImage() async {
    try {
      if (kIsWeb) {
        return null;
      }
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        return null;
      }

      final image = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
      return image?.path;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> attemptRecognition(String imagePath, String source) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/recognition/identify-known-person/');
      final request = http.MultipartRequest('POST', uri);
      request.fields['source'] = source;
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        return null;
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      return payload;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> attemptPatientRecognition(String imagePath, String source) async {
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/recognition/identify-patient/');
      final request = http.MultipartRequest('POST', uri);
      request.fields['source'] = source;
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        return null;
      }
      final payload = json.decode(response.body) as Map<String, dynamic>;
      return payload;
    } catch (_) {
      return null;
    }
  }
}
