import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cognitive_features_service.dart';

class ImprovementsScreen extends StatefulWidget { final int patientId; const ImprovementsScreen({required this.patientId, super.key}); @override State<ImprovementsScreen> createState() => _ImprovementsScreenState(); }
class _ImprovementsScreenState extends State<ImprovementsScreen> {
  final _service = CognitiveFeaturesService(); List<dynamic> _results = []; bool _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final token = Provider.of<AuthService>(context, listen: false).accessToken; if (token == null) return; try { final results = await _service.getGameResults(token, widget.patientId); if (mounted) setState(() { _results = results; _loading = false; }); } catch (_) { if (mounted) setState(() => _loading = false); } }
  @override Widget build(BuildContext context) { const games = ['Memory Game', 'Attention & Concentration', 'Pattern & Object Recognition', 'Daily Routine Recall']; return Scaffold(appBar: AppBar(title: const Text('Patient Improvements')), body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [const Text('Gaming Performance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), for (final game in games) _summary(game), const SizedBox(height: 18), const Text('Game History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), ..._results.map((item) => ListTile(title: Text(item['game_name']), subtitle: Text(item['played_at']), trailing: Text('${item['score']}')))]))); }
  Widget _summary(String game) { final matches = _results.where((item) => item['game_name'] == game).toList(); return Card(child: ListTile(title: Text(game), subtitle: Text('Played: ${matches.length} times'), trailing: Text(matches.isEmpty ? '-' : 'Latest ${matches.first['score']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))); }
}
