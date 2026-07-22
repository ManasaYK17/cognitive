import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/recognition_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/face_scan_camera.dart';
import 'patient_mode_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final int? patientId;

  const PatientDetailScreen({this.patientId, super.key});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = false;
  bool _hasPatient = false;
  int? _patientId;
  List<dynamic> _knownPeople = [];
  int _conversationsThisWeek = 0;
  List<XFile> _faceImages = [];
  List<Uint8List> _faceImageBytes = [];

  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _loadPatient();
  }

  Future<void> _loadPatient() async {
    setState(() => _loading = true);
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/patients/', token: token);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      _patientId = data['id'] as int?;
      _nameController.text = data['name'] as String? ?? '';
      _ageController.text = (data['age'] ?? '').toString();
      _notesController.text = data['medical_notes'] as String? ?? '';
      _hasPatient = true;
      await _loadKnownPeople(token);
      await _loadConversationCounts(token);
    } else {
      _hasPatient = false;
      _patientId = null;
      _knownPeople = [];
      _conversationsThisWeek = 0;
    }
    setState(() => _loading = false);
  }

  Future<void> _loadKnownPeople(String? token) async {
    if (token == null || _patientId == null) return;
    final resp = await _api.get('/known-people/', token: token, params: {'patient': _patientId.toString()});
    if (resp.statusCode == 200) {
      _knownPeople = json.decode(resp.body) as List<dynamic>;
    }
  }

  Future<void> _loadConversationCounts(String? token) async {
    if (token == null || _patientId == null) return;
    final resp = await _api.get('/history/', token: token, params: {'patient': _patientId.toString()});
    if (resp.statusCode == 200) {
      final all = json.decode(resp.body) as List<dynamic>;
      _conversationsThisWeek = all.length;
    }
  }

  Future<void> _pickFaceImage() async {
    try {
      if (kIsWeb) {
        final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
        if (image == null) return;
        final bytes = await image.readAsBytes();
        setState(() {
          _faceImages = [image];
          _faceImageBytes = [bytes];
        });
        return;
      }

      final result = await Navigator.of(context).push<FaceScanCaptureResult>(
        MaterialPageRoute(builder: (_) => const FaceScanCamera()),
      );
      if (result == null || result.cancelled || result.image == null) {
        if (result?.message != null) {
          _showError(result!.message!);
        }
        return;
      }
      final bytes = await result.image!.readAsBytes();
      setState(() {
        _faceImages = [result.image!];
        _faceImageBytes = [bytes];
      });
    } catch (_) {
      _showError('Unable to capture or pick a patient image.');
    }
  }

  Future<bool> _uploadFaceImage(int patientId, String? token) async {
    if (token == null || _faceImages.isEmpty) return true;
    final request = _api.multipartRequest('POST', '/patients/$patientId/face-images/', token: token);
    for (final image in _faceImages) {
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('files', bytes, filename: image.name));
    }
    final streamed = await request.send();
    return streamed.statusCode == 201 || streamed.statusCode == 200;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final age = _ageController.text.trim().isEmpty ? null : int.tryParse(_ageController.text.trim());
    final data = {
      'name': _nameController.text.trim(),
      'age': age,
      'medical_notes': _notesController.text.trim(),
    };

    late final int patientId;
    if (!_hasPatient) {
      final response = await _api.post('/patients/', body: data, token: token);
      if (response.statusCode != 201) {
        _showError('Unable to create patient.');
        setState(() => _loading = false);
        return;
      }
      patientId = (json.decode(response.body) as Map<String, dynamic>)['id'] as int;
      _patientId = patientId;
      _hasPatient = true;
    } else {
      final response = await _api.put('/patients/', body: data, token: token);
      if (response.statusCode != 200) {
        _showError('Unable to save patient.');
        setState(() => _loading = false);
        return;
      }
      patientId = _patientId!;
    }

    if (_faceImages.isNotEmpty) {
      final uploaded = await _uploadFaceImage(patientId, token);
      if (!uploaded) {
        _showError('Patient saved, but the face scan upload failed.');
      } else if (_faceImageBytes.isNotEmpty) {
        try {
          final auth = Provider.of<AuthService>(context, listen: false); // ignore: use_build_context_synchronously
          final response = await _api.post(
            '/recognition/issue-patient-session-token/',
            body: {'patient_id': patientId, 'device_id': 'patient-profile-save'},
            token: token,
          );
          if (response.statusCode == 200) {
            final payload = json.decode(response.body) as Map<String, dynamic>;
            final String? finalToken = payload['patient_session_token'] as String?;
            if (finalToken != null && finalToken.isNotEmpty) {
              // Store patient session token for future recognition flows, but do not navigate
              auth.setPatientSessionToken(finalToken);
            }
          }
        } catch (_) {
          // ignore recognition errors here, user can retry via normal scan
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: DesignTokens.lightSurface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.caregiverCardRadius), side: const BorderSide(width: 0.5, color: DesignTokens.subtleBorder)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_nameController.text.isEmpty ? 'Patient profile' : _nameController.text, style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            '${_knownPeople.length} known people · $_conversationsThisWeek conversations this week',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: DesignTokens.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Capture a patient face reference here so the app can recognise the patient at sign-in and switch into patient mode.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (value) => value?.trim().isEmpty == true ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ageController,
                          decoration: const InputDecoration(labelText: 'Age'),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(labelText: 'Medical notes'),
                          minLines: 3,
                          maxLines: 5,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _pickFaceImage,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Capture patient face'),
                        ),
                        const SizedBox(height: 10),
                        if (_faceImages.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(
                              _faceImages.length,
                              (index) => Image.memory(
                                _faceImageBytes[index],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: _save,
                          child: const Text('Save patient profile'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

}
