import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/face_scan_camera.dart';

class KnownPersonDetailScreen extends StatefulWidget {
  final int? personId;
  final int patientId;

  const KnownPersonDetailScreen({this.personId, required this.patientId, super.key});

  @override
  State<KnownPersonDetailScreen> createState() => _KnownPersonDetailScreenState();
}

class _KnownPersonDetailScreenState extends State<KnownPersonDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _occupationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = false;
  List<XFile> _images = [];
  List<Uint8List> _imageBytes = [];
  String? _existingFaceUrl;

  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    if (widget.personId != null) {
      _loadKnownPerson();
    }
  }

  Future<void> _loadKnownPerson() async {
    setState(() => _loading = true);
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/known-people/${widget.personId!}/', token: token);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      _nameController.text = data['name'] as String? ?? '';
      _relationshipController.text = data['relationship'] as String? ?? '';
      _occupationController.text = data['occupation'] as String? ?? '';
      _phoneController.text = data['phone_number'] as String? ?? '';
      _addressController.text = data['address'] as String? ?? '';
      _notesController.text = data['notes'] as String? ?? '';
      _existingFaceUrl = data['face_image'] as String?;
    }
    setState(() => _loading = false);
  }

  Future<void> _scanFace() async {
    try {
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
        _images.add(result.image!);
        _imageBytes.add(bytes);
      });
    } catch (_) {
      _showError('Unable to access the camera.');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final data = {
      'name': _nameController.text.trim(),
      'relationship': _relationshipController.text.trim(),
      'occupation': _occupationController.text.trim(),
      'phone_number': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'notes': _notesController.text.trim(),
      'patient': widget.patientId,
    };

    late final int personId;
    if (widget.personId == null) {
      final response = await _api.post('/known-people/', body: data, token: token);
      if (response.statusCode == 201) {
        personId = (json.decode(response.body) as Map<String, dynamic>)['id'] as int;
      } else {
        _showError('Unable to create known person.');
        setState(() => _loading = false);
        return;
      }
    } else {
      final response = await _api.put('/known-people/${widget.personId!}/', body: data, token: token);
      if (response.statusCode == 200) {
        personId = widget.personId!;
      } else {
        _showError('Unable to save known person.');
        setState(() => _loading = false);
        return;
      }
    }

    // For new contacts, require at least one scanned face. For edits, existing face may suffice.
    if (widget.personId == null && _images.isEmpty) {
      _showError('Please scan the person’s face before saving.');
      setState(() => _loading = false);
      return;
    }

    final uploaded = _images.isNotEmpty ? await _uploadImages(personId, token) : true;
    if (!uploaded) {
      _showError('Known person saved, but face upload failed.');
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<bool> _uploadImages(int personId, String? token) async {
    if (token == null) return false;
    final request = _api.multipartRequest('POST', '/known-people/$personId/face-images/', token: token);
    for (final image in _images) {
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('files', bytes, filename: image.name));
    }
    final streamed = await request.send();
    return streamed.statusCode == 201 || streamed.statusCode == 200;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.personId == null ? 'New Contact' : 'Edit Contact')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
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
                      controller: _relationshipController,
                      decoration: const InputDecoration(labelText: 'Relationship'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _occupationController,
                      decoration: const InputDecoration(labelText: 'Occupation'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      minLines: 3,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _scanFace,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Scan face'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_images.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(
                              _images.length,
                              (index) => Image.memory(
                                _imageBytes[index],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${_images.length} scanned face image(s) attached', style: const TextStyle(color: Colors.green)),
                        ],
                      )
                    else if (_existingFaceUrl != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.network(
                            _existingFaceUrl!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                          ),
                          const SizedBox(height: 8),
                          const Text('Existing scanned face attached', style: TextStyle(color: Colors.grey)),
                        ],
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Scan at least one face before saving this contact.', style: TextStyle(color: Colors.grey)),
                      ),
                    const SizedBox(height: 30),
                    ElevatedButton(onPressed: _save, child: const Text('Save Contact')),
                  ],
                ),
              ),
            ),
    );
  }
}
