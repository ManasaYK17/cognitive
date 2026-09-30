import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/app_language.dart';
import 'patient_history_detail_screen.dart';
import '../widgets/image_avatar.dart';

class PatientHistoryScreen extends StatefulWidget {
  final String sessionToken;

  const PatientHistoryScreen({required this.sessionToken, super.key});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  final ApiClient _api = ApiClient();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  bool _historyLoadInFlight = false;
  List<dynamic> _history = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadHistory());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted || _historyLoadInFlight) return;
    _historyLoadInFlight = true;
    try {
      final response = await _api.get(
        '/history/patient-view/',
        token: widget.sessionToken,
        params: {'language': AppLanguage().language},
        timeout: const Duration(seconds: 65),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final updatedHistory = json.decode(response.body) as List<dynamic>;
        if (_loading || jsonEncode(updatedHistory) != jsonEncode(_history)) {
          setState(() {
            _history = updatedHistory;
            _loading = false;
          });
        }
        return;
      }
      if (_loading) setState(() => _loading = false);
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    } finally {
      _historyLoadInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              key: const PageStorageKey<String>('patient-history-list'),
              controller: _scrollController,
              itemCount: _history.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = _history[index] as Map<String, dynamic>;
                final knownPersonId = item['known_person_id'] as int?;
                final knownPersonName = item['known_person_name'] as String? ?? 'Unknown';
                return ListTile(
                  key: ValueKey<int?>(knownPersonId),
                  leading: ImageAvatar(
                    imageUrl: item['known_person_image'] as String?,
                    bearerToken: widget.sessionToken,
                  ),
                  title: Text(knownPersonName),
                  subtitle: Text(item['last_summary'] as String? ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: knownPersonId == null
                      ? null
                      : () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PatientHistoryDetailScreen(
                              sessionToken: widget.sessionToken,
                              knownPersonId: knownPersonId,
                              knownPersonName: knownPersonName,
                            ),
                          ));
                        },
                );
              },
            ),
    );
  }
}
