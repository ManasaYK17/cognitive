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
  double _radiusMeters = 500;
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
      _radiusMeters = (data['radius_meters'] as num?)?.toDouble() ?? double.tryParse(_radiusController.text) ?? 500;
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
    final radius = _radiusMeters;
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) {
      _showError('Latitude and longitude must be numeric.');
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
                  const Text('Set Limit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Visual preview area
                        Container(
                          height: 220,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const GridPaper(
                                color: Color.fromRGBO(128, 128, 128, 0.12),
                                divisions: 4,
                                interval: 20,
                                subdivisions: 1,
                              ),
                              // Circle representing radius
                              LayoutBuilder(builder: (context, constraints) {
                                const maxVisual = 140.0; // max radius in pixels
                                const maxMeters = 2000.0; // map max meters scale
                                final normalized = (_radiusMeters.clamp(1, maxMeters)) / maxMeters;
                                final radiusPx = 24.0 + normalized * maxVisual;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: radiusPx * 2,
                                      height: radiusPx * 2,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha((0.6 * 255).round()), width: 2),
                                      ),
                                    ),
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Radius slider
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Radius:'),
                          Text('${_radiusMeters.toStringAsFixed(0)} m'),
                        ]),
                        Slider(
                          min: 50,
                          max: 2000,
                          divisions: 39,
                          value: _radiusMeters.clamp(50, 2000),
                          label: '${_radiusMeters.toStringAsFixed(0)} m',
                          onChanged: (v) => setState(() => _radiusMeters = v.roundToDouble()),
                        ),
                        const SizedBox(height: 8),
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
                        ElevatedButton(
                          onPressed: _useCurrentLocation,
                          child: const Text('Use current location'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _saving ? null : _saveSafeZone,
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: Text(_saving ? 'Saving…' : 'Save'),
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
