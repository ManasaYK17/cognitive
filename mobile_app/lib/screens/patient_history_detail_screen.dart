import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

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
  bool _loading = true;
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final response = await _api.get(
      '/history/patient-view/',
      token: widget.sessionToken,
      params: {'known_person_id': widget.knownPersonId.toString()},
    );
    if (response.statusCode == 200) {
      setState(() {
        _history = json.decode(response.body) as List<dynamic>;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = false);
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
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _history[index] as Map<String, dynamic>;
                    final summary = item['summary'] as String? ?? 'No summary available';
                    final transcript = item['transcript'] as String? ?? '';
                    final errorMessage = item['error_message'] as String?;
                    final createdAt = item['created_at'] as String? ?? '';
                    return ListTile(
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
