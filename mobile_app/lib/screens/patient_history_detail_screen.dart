import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/app_language.dart';
import '../widgets/image_avatar.dart';

class PatientHistoryDetailScreen extends StatefulWidget {
  final String sessionToken;
  final int knownPersonId;
  final String knownPersonName;

  const PatientHistoryDetailScreen({
    required this.sessionToken,
    required this.knownPersonId,
    required this.knownPersonName,
    super.key,
  });

  @override
  State<PatientHistoryDetailScreen> createState() => _PatientHistoryDetailScreenState();
}

class _PatientHistoryDetailScreenState extends State<PatientHistoryDetailScreen> {
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
        params: {
          'known_person_id': widget.knownPersonId.toString(),
          'language': AppLanguage().language,
        },
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
      appBar: AppBar(title: Text(widget.knownPersonName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('No conversations yet.'))
              : ListView.separated(
                  key: PageStorageKey<String>('patient-history-detail-${widget.knownPersonId}'),
                  controller: _scrollController,
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _history[index] as Map<String, dynamic>;
                    final summary = item['summary'] as String? ?? 'No summary available';
                    final transcript = item['transcript'] as String? ?? '';
                    final errorMessage = item['error_message'] as String?;
                    final createdAt = item['created_at'] as String? ?? '';
                    return ListTile(
                      key: ValueKey<int?>(item['id'] as int?),
                      leading: ImageAvatar(
                        imageUrl: item['captured_image'] as String?,
                        bearerToken: widget.sessionToken,
                      ),
                      title: Text(summary, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(transcript, maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (errorMessage != null && errorMessage.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Error: $errorMessage', style: const TextStyle(color: Colors.red)),
                          ],
                          if (createdAt.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(createdAt, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
