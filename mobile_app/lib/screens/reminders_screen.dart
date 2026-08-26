import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cognitive_features_service.dart';

class RemindersScreen extends StatefulWidget {
  final int patientId;
  const RemindersScreen({required this.patientId, super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _service = CognitiveFeaturesService();
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) return;
    try { final items = await _service.getReminders(token, patientId: widget.patientId); if (mounted) setState(() { _items = items; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _add(String type) async {
    final result = await showDialog<Map<String, String>>(context: context, builder: (_) => _ReminderDialog(type: type));
    if (result == null) return;
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      await _service.createReminder(token, {'patient': widget.patientId, 'reminder_type': type, 'medicine_name': result['medicine_name'] ?? '', 'message': result['message'] ?? '', 'scheduled_for': result['scheduled_for']});
      _load();
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', '')))); }
  }

  @override
  Widget build(BuildContext context) {
    final sections = {'medicine': 'Medicines', 'food': 'Food', 'other': 'Other Important Reminders'};
    return Scaffold(appBar: AppBar(title: const Text('Reminders')), body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      for (final entry in sections.entries) _section(entry.key, entry.value),
    ])));
  }

  Widget _section(String type, String title) {
    final items = _items.where((item) => item['type'] == type).toList();
    final active = items.where((item) => item['status'] == 'pending' || item['status'] == 'triggered').toList();
    final completed = items.where((item) => item['status'] == 'completed').toList();
    final missed = items.where((item) => item['status'] == 'missed').toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))), IconButton(onPressed: () => _add(type), icon: const Icon(Icons.add_circle, size: 32))]),
      _subheading('Active reminders'), ...active.map(_reminderTile),
      _subheading(type == 'medicine' ? 'Taken History' : 'Completed History'), ...completed.map(_reminderTile),
      _subheading('Missed History'), ...missed.map(_reminderTile),
      if (items.isEmpty) const Text('No reminders yet.'),
    ])));
  }
  Widget _subheading(String text) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)));
  Widget _reminderTile(dynamic item) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(item['type'] == 'medicine' ? Icons.medication : item['type'] == 'food' ? Icons.restaurant : Icons.notifications, color: item['status'] == 'missed' ? Colors.red : Colors.green), title: Text(item['type'] == 'medicine' ? item['medicine_name'] : item['message']), subtitle: Text('${item['scheduled_for']}\n${item['status'] == 'completed' ? 'Completed' : item['status'] == 'missed' ? 'Missed' : item['status']}'));
}

class _ReminderDialog extends StatefulWidget { final String type; const _ReminderDialog({required this.type}); @override State<_ReminderDialog> createState() => _ReminderDialogState(); }
class _ReminderDialogState extends State<_ReminderDialog> {
  final _name = TextEditingController(); final _message = TextEditingController(); final _date = TextEditingController(); final _time = TextEditingController();
  @override void dispose() { _name.dispose(); _message.dispose(); _date.dispose(); _time.dispose(); super.dispose(); }
  Future<void> _pickDate() async { final value = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: DateTime.now()); if (value != null) _date.text = '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'; }
  Future<void> _pickTime() async { final value = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (value != null) _time.text = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00'; }
  @override Widget build(BuildContext context) => AlertDialog(title: Text('Add ${widget.type} reminder'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [if (widget.type == 'medicine') TextField(controller: _name, decoration: const InputDecoration(labelText: 'Medicine name')), if (widget.type != 'medicine') TextField(controller: _message, decoration: const InputDecoration(labelText: 'Note / message')), TextField(controller: _date, readOnly: true, onTap: _pickDate, decoration: const InputDecoration(labelText: 'Date')), TextField(controller: _time, readOnly: true, onTap: _pickTime, decoration: const InputDecoration(labelText: 'Time'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (_date.text.isEmpty || _time.text.isEmpty || (widget.type == 'medicine' ? _name.text.trim().isEmpty : _message.text.trim().isEmpty)) return; Navigator.pop(context, {'medicine_name': _name.text.trim(), 'message': _message.text.trim(), 'scheduled_for': '${_date.text}T${_time.text}Z'}); }, child: const Text('Set Reminder'))]);
}
