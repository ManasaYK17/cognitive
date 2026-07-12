import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'patient_detail_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> _patients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/patients/', token: token);
    if (response.statusCode == 200) {
      setState(() {
        _patients = json.decode(response.body) as List<dynamic>;
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
      appBar: AppBar(title: const Text('Patients')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _patients.length,
              itemBuilder: (context, index) {
                final patient = _patients[index] as Map<String, dynamic>;
                return ListTile(
                  title: Text(patient['name'] as String? ?? 'Unknown'),
                  subtitle: Text('Age: ${patient['age'] ?? 'N/A'}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () async {
                    final refresh = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => PatientDetailScreen(patientId: patient['id'] as int),
                      ),
                    );
                    if (refresh == true) _loadPatients();
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final refresh = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const PatientDetailScreen()),
          );
          if (refresh == true) _loadPatients();
        },
      ),
    );
  }
}
