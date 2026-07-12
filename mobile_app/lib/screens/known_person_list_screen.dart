import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'known_person_detail_screen.dart';

class KnownPersonListScreen extends StatefulWidget {
  final int patientId;

  const KnownPersonListScreen({required this.patientId, super.key});

  @override
  State<KnownPersonListScreen> createState() => _KnownPersonListScreenState();
}

class _KnownPersonListScreenState extends State<KnownPersonListScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  List<dynamic> _knownPeople = [];

  @override
  void initState() {
    super.initState();
    _loadKnownPeople();
  }

  Future<void> _loadKnownPeople() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/known-people/', token: token, params: {
      'patient': widget.patientId.toString(),
    });
    if (response.statusCode == 200) {
      setState(() {
        _knownPeople = json.decode(response.body) as List<dynamic>;
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
      appBar: AppBar(title: const Text('Known People')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _knownPeople.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final person = _knownPeople[index] as Map<String, dynamic>;
                return ListTile(
                  title: Text(person['name'] as String? ?? 'Unknown'),
                  subtitle: Text(person['relationship'] as String? ?? ''),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () async {
                    final needRefresh = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => KnownPersonDetailScreen(personId: person['id'] as int, patientId: widget.patientId),
                      ),
                    );
                    if (needRefresh == true) {
                      _loadKnownPeople();
                    }
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final refresh = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => KnownPersonDetailScreen(patientId: widget.patientId),
            ),
          );
          if (refresh == true) {
            _loadKnownPeople();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
