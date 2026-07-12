import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class HistoryDashboardScreen extends StatefulWidget {
  final int? patientId;

  const HistoryDashboardScreen({this.patientId, super.key});

  @override
  State<HistoryDashboardScreen> createState() => _HistoryDashboardScreenState();
}

class _HistoryDashboardScreenState extends State<HistoryDashboardScreen> {
  final ApiClient _api = ApiClient();
  final _searchController = TextEditingController();
  List<dynamic> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory([String? search]) async {
    setState(() {
      _loading = true;
    });
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/history/', token: token, params: {
      if (widget.patientId != null) 'patient_id': widget.patientId.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    });
    if (response.statusCode == 200) {
      setState(() {
        _events = json.decode(response.body) as List<dynamic>;
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
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search history',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _loadHistory(_searchController.text.trim()),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index] as Map<String, dynamic>;
                      return ListTile(
                        title: Text(event['event_type'] as String? ?? 'Event'),
                        subtitle: Text(event['summary'] as String? ?? event['outcome'] as String? ?? ''),
                        trailing: event['known_person_name'] != null
                            ? Text(event['known_person_name'] as String)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
