import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cognitive_features_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_event.dart';

class ImprovementsScreen extends StatefulWidget { final int patientId; const ImprovementsScreen({required this.patientId, super.key}); @override State<ImprovementsScreen> createState() => _ImprovementsScreenState(); }
class _ImprovementsScreenState extends State<ImprovementsScreen> {
  final _service = CognitiveFeaturesService(); List<dynamic> _results = []; bool _loading = true; StreamSubscription<RealtimeEvent>? _realtimeSubscription; StreamSubscription<void>? _resumeSubscription;
  @override void initState() { super.initState(); _load(); _realtimeSubscription = NotificationService.events.listen(_handleEvent); _resumeSubscription = NotificationService.resumeEvents.listen((_) => _load()); }
  void _handleEvent(RealtimeEvent event) {
    if (!mounted || event.patientId != widget.patientId || event.type != 'GAME_SCORE_UPDATED') return;
    final score = {
      'id': event.objectId,
      'game_name': event.data['game_name'],
      'score': int.tryParse(event.data['score']?.toString() ?? '') ?? 0,
      'played_at': event.data['played_at'] ?? event.data['timestamp'],
    };
    setState(() {
      _results = [score, ..._results.where((item) => item['id'] != event.objectId)];
    });
  }

  @override void dispose() { _realtimeSubscription?.cancel(); _resumeSubscription?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null) return;
    try {
      final results = await _service.getGameResults(token, widget.patientId);
      if (mounted) setState(() { _results = results; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
  @override Widget build(BuildContext context) { const games = ['Sequence Memory', 'Image Matching', 'Missing Card Memory', 'Daily Routine Recall']; return Scaffold(appBar: AppBar(title: const Text('Patient Improvements')), body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [const Text('Gaming Performance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), for (final game in games) _summary(game), const SizedBox(height: 18), const Text('Game History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), ..._results.map((item) => ListTile(title: Text(item['game_name']), subtitle: Text(item['played_at']), trailing: Text('${item['score']}')))]))); }
  Widget _summary(String game) { final matches = _results.where((item) => item['game_name'] == game).toList(); return Card(child: ListTile(title: Text(game), subtitle: Text('Played: ${matches.length} times'), trailing: Text(matches.isEmpty ? '-' : 'Latest ${matches.first['score']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))); }
}
