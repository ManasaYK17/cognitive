import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class SafeZoneScreen extends StatefulWidget {
  final int patientId;

  const SafeZoneScreen({required this.patientId, super.key});

  @override
  State<SafeZoneScreen> createState() => _SafeZoneScreenState();
}

class _SafeZoneScreenState extends State<SafeZoneScreen> {
  final ApiClient _api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'Home');
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '500');
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSafeZone();
  }

  Future<void> _loadSafeZone() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/patients/${widget.patientId}/safe-zone/', token: token);
    if (response.statusCode == 200) {
      final data = response.body.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(response.body) as Map) : <String, dynamic>{};
      _nameController.text = data['name'] as String? ?? 'Home';
      _latitudeController.text = data['center_latitude']?.toString() ?? '';
      _longitudeController.text = data['center_longitude']?.toString() ?? '';
      _radiusController.text = data['radius_meters']?.toString() ?? '500';
    }
    setState(() => _loading = false);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loading = true);
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showError('Location services are disabled. Please enable them to use current location.');
      setState(() => _loading = false);
      return;
    }
    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _latitudeController.text = position.latitude.toStringAsFixed(6);
    _longitudeController.text = position.longitude.toStringAsFixed(6);
    setState(() => _loading = false);
  }

  Future<void> _saveSafeZone() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final radius = double.tryParse(_radiusController.text.trim());
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (radius == null || latitude == null || longitude == null) {
      _showError('Latitude, longitude, and radius must be numeric.');
      setState(() => _saving = false);
      return;
    }

    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null || token.isEmpty) {
      _showError('Please sign in again before saving a safe zone.');
      setState(() => _saving = false);
      return;
    }

    final response = await _api.put(
      '/patients/${widget.patientId}/safe-zone/',
      body: {
        'name': _nameController.text.trim(),
        'center_latitude': latitude,
        'center_longitude': longitude,
        'radius_meters': radius,
      },
      token: token,
    );

    setState(() => _saving = false);
    if (response.statusCode == 200) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    _showError('Unable to save safe zone.');
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Limit')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Safe zone settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: 'Safe zone name'),
                          validator: (value) => value?.trim().isEmpty == true ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _latitudeController,
                          decoration: const InputDecoration(labelText: 'Center latitude'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) => value?.trim().isEmpty == true ? 'Latitude is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _longitudeController,
                          decoration: const InputDecoration(labelText: 'Center longitude'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) => value?.trim().isEmpty == true ? 'Longitude is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _radiusController,
                          decoration: const InputDecoration(labelText: 'Radius (meters)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value?.trim().isEmpty == true) return 'Radius is required';
                            final parsed = double.tryParse(value!.trim());
                            if (parsed == null || parsed <= 0) return 'Enter a valid radius';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _useCurrentLocation,
                          child: const Text('Use current location'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _saving ? null : _saveSafeZone,
                          child: Text(_saving ? 'Saving…' : 'Save limit'),
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
