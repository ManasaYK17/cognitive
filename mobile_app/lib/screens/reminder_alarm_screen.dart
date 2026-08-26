import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/cognitive_features_service.dart';

class ReminderAlarmScreen extends StatefulWidget {
  final Map<String, dynamic> reminder;
  final String sessionToken;
  const ReminderAlarmScreen({required this.reminder, required this.sessionToken, super.key});
  @override State<ReminderAlarmScreen> createState() => _ReminderAlarmScreenState();
}

class _ReminderAlarmScreenState extends State<ReminderAlarmScreen> {
  final _service = CognitiveFeaturesService();
  final _tts = FlutterTts();
  Timer? _timeout;
  bool _saving = false;

  String get _type => widget.reminder['type']?.toString() ?? 'other';
  String get _message => _type == 'medicine' ? 'Time to take ${widget.reminder['medicine_name']}' : (widget.reminder['message']?.toString() ?? 'Reminder');

  @override
  void initState() { super.initState(); _timeout = Timer(const Duration(minutes: 5), () => _finish('missed')); _tts.speak(_message); }
  @override void dispose() { _timeout?.cancel(); _tts.stop(); super.dispose(); }
  Future<void> _finish(String status) async { if (_saving) return; setState(() => _saving = true); try { await _service.updateReminderStatus(widget.sessionToken, widget.reminder['id'] as int, status); } catch (_) {} if (mounted) Navigator.of(context).pop(); }

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, child: Scaffold(backgroundColor: Colors.red.shade900, body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(_type == 'medicine' ? Icons.medication : _type == 'food' ? Icons.restaurant : Icons.notifications_active, size: 110, color: Colors.white),
    const SizedBox(height: 28), Text(_type == 'medicine' ? 'MEDICINE REMINDER' : _type == 'food' ? 'FOOD REMINDER' : 'REMINDER', textAlign: TextAlign.center, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: Colors.white)),
    const SizedBox(height: 22), Text(_message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, color: Colors.white)),
    const SizedBox(height: 50), SizedBox(width: double.infinity, height: 86, child: ElevatedButton(onPressed: _saving ? null : () => _finish('completed'), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red), child: Text(_saving ? 'Saving...' : 'STOP ALARM', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)))),
  ]))))));
}
