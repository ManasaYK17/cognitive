import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/app_language.dart';
import '../services/cognitive_features_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_event.dart';

class ImprovementsScreen extends StatefulWidget { final int patientId; const ImprovementsScreen({required this.patientId, super.key}); @override State<ImprovementsScreen> createState() => _ImprovementsScreenState(); }
class _ImprovementsScreenState extends State<ImprovementsScreen> {
  final _service = CognitiveFeaturesService();
  List<dynamic> _results = [];
  bool _loading = true;
  bool _loadInFlight = false;
  String? _loadError;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<void>? _resumeSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeSubscription = NotificationService.events.listen(_handleEvent);
    _resumeSubscription = NotificationService.resumeEvents.listen((_) => _load());
  }

  void _handleEvent(RealtimeEvent event) {
    if (!mounted || event.patientId != widget.patientId || event.type != 'GAME_SCORE_UPDATED') return;
    final score = {
      'id': event.objectId,
      'game_name': event.data['game_name'],
      'score': int.tryParse(event.data['score']?.toString() ?? '') ?? 0,
      'correct_answers': int.tryParse(event.data['correct_answers']?.toString() ?? '') ?? 0,
      'total_questions': int.tryParse(event.data['total_questions']?.toString() ?? '') ?? 0,
      'played_at': event.data['played_at'] ?? event.data['timestamp'],
    };
    setState(() {
      _results = [score, ..._results.where((item) => item['id'] != event.objectId)];
    });
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _resumeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() { _loading = false; _loadError = AppLanguage().translate('caregiver_sign_in_required'); });
      _loadInFlight = false;
      return;
    }
    try {
      final results = await _service.getGameResults(token, widget.patientId);
      if (mounted) setState(() { _results = results; _loading = false; _loadError = null; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadError = AppLanguage().translate('improvements_load_error'); });
    } finally {
      _loadInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLanguage = Provider.of<AppLanguage>(context);
    const games = ['Sequence Memory', 'Image Matching', 'Missing Card Memory', 'Daily Routine Recall'];
    return Scaffold(
      appBar: AppBar(title: Text(appLanguage.translate('improvements_patient_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loadError != null)
                    ListTile(
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text(appLanguage.translate('improvements_load_error')),
                      subtitle: Text(_loadError!),
                      trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
                    ),
                  Text(appLanguage.translate('improvements_performance'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  for (final game in games) _summary(game, appLanguage),
                  const SizedBox(height: 18),
                  Text(appLanguage.translate('improvements_history'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (_results.isEmpty && _loadError == null)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(appLanguage.translate('improvements_empty')),
                    ),
                  ..._results.map((item) => ListTile(
                        title: Text(_localizedGameName(item['game_name']?.toString() ?? '', appLanguage)),
                        subtitle: Text(
                          '${_localizedGameText(appLanguage, 'improvements_correct_total', {
                            'correct': '${item['correct_answers'] ?? 0}',
                            'total': '${item['total_questions'] ?? 0}',
                          })} · ${item['played_at'] ?? ''}',
                        ),
                        trailing: Text('${item['score'] ?? 0}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                      )),
                ],
              ),
            ),
    );
  }

  Widget _summary(String game, AppLanguage appLanguage) {
    final matches = _results.where((item) => item['game_name'] == game).toList();
    final latestScore = matches.isEmpty ? null : matches.first['score'];
    return Card(
      child: ListTile(
        title: Text(_localizedGameName(game, appLanguage)),
        subtitle: Text(_localizedGameText(appLanguage, 'improvements_played_times', {'count': '${matches.length}'})),
        trailing: Text(
          latestScore == null
              ? '-'
              : _localizedGameText(appLanguage, 'improvements_latest', {'score': '$latestScore'}),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _localizedGameName(String game, AppLanguage appLanguage) {
    const keys = {
      'Sequence Memory': 'game_sequence_memory',
      'Image Matching': 'game_image_matching',
      'Missing Card Memory': 'game_missing_card_memory',
      'Daily Routine Recall': 'game_daily_routine_recall',
    };
    return appLanguage.translate(keys[game] ?? 'game_unavailable');
  }

  String _localizedGameText(AppLanguage appLanguage, String key, Map<String, String> values) {
    var text = appLanguage.translate(key);
    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }
}
