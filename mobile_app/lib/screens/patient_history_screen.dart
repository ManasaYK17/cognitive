import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'patient_history_detail_screen.dart';

class PatientHistoryScreen extends StatefulWidget {
  final String sessionToken;

  const PatientHistoryScreen({required this.sessionToken, super.key});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final response = await _api.get('/history/patient-view/', token: widget.sessionToken);
    if (response.statusCode == 200) {
      setState(() {
        _history = json.decode(response.body) as List<dynamic>;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _history.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = _history[index] as Map<String, dynamic>;
                final knownPersonId = item['known_person_id'] as int?;
                final knownPersonName = item['known_person_name'] as String? ?? 'Unknown';
                return ListTile(
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
