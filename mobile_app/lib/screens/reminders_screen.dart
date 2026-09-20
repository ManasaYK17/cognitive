import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cognitive_features_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_event.dart';

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
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<void>? _resumeSubscription;

  @override
  void initState() { super.initState(); _load(); _realtimeSubscription = NotificationService.events.listen(_handleEvent); _resumeSubscription = NotificationService.resumeEvents.listen((_) => _load()); }
  void _handleEvent(RealtimeEvent event) { if (!mounted || event.patientId != widget.patientId || !event.type.startsWith('REMINDER_')) return; final id = event.objectId; final index = _items.indexWhere((item) => item['id']?.toString() == id?.toString()); final updated = Map<String, dynamic>.from(index >= 0 ? _items[index] as Map : <String, dynamic>{}); updated['id'] = id; updated['type'] = event.data['reminder_type'] ?? updated['type']; updated['medicine_name'] = event.data['medicine_name'] ?? updated['medicine_name']; updated['message'] = event.data['message'] ?? updated['message']; updated['scheduled_for'] = event.data['scheduled_for'] ?? updated['scheduled_for']; updated['status'] = event.data['status'] ?? (event.type == 'REMINDER_COMPLETED' ? 'completed' : event.type == 'REMINDER_MISSED' ? 'missed' : updated['status']); if (index < 0 && event.type == 'REMINDER_CREATED') { setState(() => _items = [updated, ..._items]); } else if (index >= 0) { setState(() { _items[index] = updated; }); } }
  @override void dispose() { _realtimeSubscription?.cancel(); _resumeSubscription?.cancel(); super.dispose(); }
  Future<void> _load() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) return;
    try { final items = await _service.getReminders(token, patientId: widget.patientId); if (mounted) setState(() { _items = items; _loading = false; }); }
    catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _add(String type) async {
    final result = await showDialog<Map<String, String>>(context: context, builder: (_) => _ReminderDialog(type: type));
    if (result == null) return;
    if (!mounted) return;
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      await _service.createReminder(token, {'patient': widget.patientId, 'reminder_type': type, 'medicine_name': result['medicine_name'] ?? '', 'message': result['message'] ?? '', 'scheduled_for': result['scheduled_for']});
      _load();
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', '')))); }
  }

  Future<void> _delete(dynamic item) async {
    final id = item['id'];
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: const Text('This reminder will be removed from the patient list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      await _service.deleteReminder(token, id as int);
      if (mounted) {
        setState(() => _items.removeWhere((entry) => entry['id']?.toString() == id.toString()));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))));
      }
    }
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
  Widget _reminderTile(dynamic item) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(item['type'] == 'medicine' ? Icons.medication : item['type'] == 'food' ? Icons.restaurant : Icons.notifications, color: item['status'] == 'missed' ? Colors.red : Colors.green),
    title: Text(item['type'] == 'medicine' ? item['medicine_name'] : item['message']),
    subtitle: Text('${item['scheduled_for']}\n${item['status'] == 'completed' ? 'Completed' : item['status'] == 'missed' ? 'Missed' : item['status']}'),
    trailing: IconButton(
      onPressed: () => _delete(item),
      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
      tooltip: 'Delete reminder',
    ),
  );
}

class _ReminderDialog extends StatefulWidget { final String type; const _ReminderDialog({required this.type}); @override State<_ReminderDialog> createState() => _ReminderDialogState(); }
class _ReminderDialogState extends State<_ReminderDialog> {
  final _name = TextEditingController(); final _message = TextEditingController(); final _date = TextEditingController(); final _time = TextEditingController();
  @override void dispose() { _name.dispose(); _message.dispose(); _date.dispose(); _time.dispose(); super.dispose(); }
  Future<void> _pickDate() async { final value = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: DateTime.now()); if (value != null) _date.text = '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'; }
  Future<void> _pickTime() async { final value = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (value != null) _time.text = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00'; }
  @override Widget build(BuildContext context) => AlertDialog(title: Text('Add ${widget.type} reminder'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [if (widget.type == 'medicine') TextField(controller: _name, decoration: const InputDecoration(labelText: 'Medicine name')), if (widget.type != 'medicine') TextField(controller: _message, decoration: const InputDecoration(labelText: 'Note / message')), TextField(controller: _date, readOnly: true, onTap: _pickDate, decoration: const InputDecoration(labelText: 'Date')), TextField(controller: _time, readOnly: true, onTap: _pickTime, decoration: const InputDecoration(labelText: 'Time'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (_date.text.isEmpty || _time.text.isEmpty || (widget.type == 'medicine' ? _name.text.trim().isEmpty : _message.text.trim().isEmpty)) return; final localDateTime = DateTime.parse('${_date.text}T${_time.text}'); Navigator.pop(context, {'medicine_name': _name.text.trim(), 'message': _message.text.trim(), 'scheduled_for': localDateTime.toUtc().toIso8601String()}); }, child: const Text('Set Reminder'))]);
}
