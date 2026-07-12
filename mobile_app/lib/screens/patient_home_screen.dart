import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/audio_service.dart';
import '../services/location_service.dart';
import '../services/recognition_service.dart';
import '../theme/design_tokens.dart';
import 'patient_history_screen.dart';

class PatientHomeScreen extends StatefulWidget {
  final int patientId;
  final String sessionToken;

  const PatientHomeScreen({required this.patientId, required this.sessionToken, super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final ApiClient _api = ApiClient();
  bool _scanning = false;
  bool _loadingMemories = true;
  List<dynamic> _recentMemories = [];

  @override
  void initState() {
    super.initState();
    _loadRecentMemories();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareLocationReporting();
    });
  }

  Future<void> _loadRecentMemories() async {
    setState(() => _loadingMemories = true);
    final response = await _api.get('/history/patient-view/', token: widget.sessionToken, params: {'limit': '5'});
    if (response.statusCode == 200) {
      setState(() {
        _recentMemories = json.decode(response.body) as List<dynamic>;
        _loadingMemories = false;
      });
      return;
    }
    setState(() => _loadingMemories = false);
  }

  Future<void> _prepareLocationReporting() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    await locationService.initialize();
    if (!locationService.permissionGranted && !locationService.permissionPermanentlyDenied) {
      await locationService.requestPermission();
    }
    if (locationService.permissionGranted) {
      await locationService.startReporting(widget.patientId, widget.sessionToken);
    }
  }

  Future<void> _attemptRecognition() async {
    setState(() => _scanning = true);
    final recognitionService = Provider.of<RecognitionService>(context, listen: false);
    final success = await recognitionService.performRecognition();
    setState(() => _scanning = false);

    if (!success) {
      _showMessage('Recognition failed. Please try again.');
      return;
    }

    _showMessage('Recognition complete.');
  }

  Future<void> _toggleRecording() async {
    final audioService = Provider.of<AudioService>(context, listen: false);
    final recognitionService = Provider.of<RecognitionService>(context, listen: false);
    if (audioService.recording) {
      final knownPersonId = recognitionService.recognizedPerson?['id'] as int? ?? 0;
      await audioService.stopRecordingAndSend(widget.patientId, knownPersonId, widget.sessionToken);
      _showMessage(audioService.lastSummaryMessage ?? 'Recording saved successfully.');
      return;
    }

    await audioService.startRecording();
    if (mounted) {
      setState(() {});
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTimeline() {
    if (_recentMemories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text('No recent memories yet.', style: TextStyle(color: DesignTokens.textSecondary)),
      );
    }

    return Column(
      children: _recentMemories.map((entry) {
        final activity = entry as Map<String, dynamic>;
        final summary = activity['summary'] as String? ?? activity['last_summary'] as String? ?? 'No details available';
        final timestamp = activity['timestamp'] as String? ?? activity['created_at'] as String? ?? '';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(summary, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(timestamp, style: const TextStyle(fontSize: 12)),
        );
      }).toList(),
    );
  }

  Widget _buildPersonCard() {
    final recognitionService = Provider.of<RecognitionService>(context);
    final person = recognitionService.recognizedPerson;

    if (person == null) {
      return const Text('No one recognized yet.', style: TextStyle(color: DesignTokens.textPrimary, fontSize: 24));
    }

    return Card(
      color: DesignTokens.lightSurface,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(person['name'] as String? ?? 'Unknown', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text('Relationship: ${person['relationship'] ?? 'N/A'}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(person['notes'] as String? ?? '', style: const TextStyle(fontSize: 14, color: DesignTokens.textSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recognitionService = Provider.of<RecognitionService>(context);
    final audioService = Provider.of<AudioService>(context);
    final person = recognitionService.recognizedPerson;
    final statusText = person != null ? 'Recognized: ${person['name']}' : 'Ready to scan';

    return Scaffold(
      backgroundColor: DesignTokens.pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              Text(statusText, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(child: Center(child: _buildPersonCard())),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _scanning ? null : _attemptRecognition,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: Text(_scanning ? 'Scanning...' : 'Scan Face'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: person == null ? null : _toggleRecording,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: person == null ? Colors.grey : Colors.blue),
                child: Text(audioService.recording ? 'Stop recording' : 'Record conversation'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientHistoryScreen(sessionToken: widget.sessionToken)));
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: const Text('View Full History'),
              ),
              const SizedBox(height: 20),
              Align(alignment: Alignment.centerLeft, child: Text('Recent memories', style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(height: 12),
              if (_loadingMemories)
                const Center(child: CircularProgressIndicator())
              else
                _buildTimeline(),
            ],
          ),
        ),
      ),
    );
  }
}
