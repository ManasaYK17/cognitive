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
  bool _changed = false;

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

  void _markChanged() {
    if (!_changed) setState(() => _changed = true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_changed == true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Known People')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: _knownPeople.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final person = _knownPeople[index] as Map<String, dynamic>;
                          final name = person['name'] as String? ?? 'Unknown';
                          final relationship = person['relationship'] as String? ?? '';
                          final initials = name
                              .split(RegExp(r"\s+"))
                              .where((s) => s.isNotEmpty)
                              .map((s) => s[0])
                              .take(2)
                              .join()
                              .toUpperCase();
                          return GestureDetector(
                            onTap: () async {
                              final needRefresh = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => KnownPersonDetailScreen(personId: person['id'] as int, patientId: widget.patientId),
                                ),
                              );
                              if (needRefresh == true) {
                                _markChanged();
                                _loadKnownPeople();
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.12), blurRadius: 6, offset: Offset(0, 2)),
                                ],
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((0.2 * 255).round()),
                                    backgroundImage: person['face_image'] != null ? NetworkImage(person['face_image'] as String) : null,
                                    child: person['face_image'] == null ? Text(initials, style: const TextStyle(fontWeight: FontWeight.bold)) : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        const SizedBox(height: 4),
                                        Text(relationship, style: const TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final refresh = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => KnownPersonDetailScreen(patientId: widget.patientId),
                            ),
                          );
                          if (refresh == true) {
                            _markChanged();
                            _loadKnownPeople();
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('+  Add known person'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
