import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'patient_detail_screen.dart';
import 'known_person_list_screen.dart';
import 'history_dashboard_screen.dart';
import 'safe_zone_screen.dart';
import 'face_scan_screen.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  State<CaregiverDashboardScreen> createState() => _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  Map<String, dynamic>? _patient;
  int _knownPeopleCount = 0;
  int _historyCount = 0;
  String? _safeZoneLabel;

  @override
  void initState() {
    super.initState();
    _loadPatient();
  }

  Future<void> _loadPatient() async {
    setState(() => _loading = true);
    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/patients/', token: token);
    if (response.statusCode == 200) {
      final patient = json.decode(response.body) as Map<String, dynamic>;
      await _loadPatientMetadata(token, patient['id'] as int);
      setState(() {
        _patient = patient;
        _loading = false;
      });
      return;
    }
    setState(() {
      _patient = null;
      _knownPeopleCount = 0;
      _historyCount = 0;
      _safeZoneLabel = null;
      _loading = false;
    });
  }

  Future<void> _loadPatientMetadata(String? token, int patientId) async {
    await Future.wait([
      _loadKnownPeopleCount(token, patientId),
      _loadHistoryCount(token, patientId),
      _loadSafeZoneLabel(token, patientId),
    ]);
  }

  Future<void> _loadKnownPeopleCount(String? token, int patientId) async {
    if (token == null) return;
    final response = await _api.get('/known-people/', token: token, params: {'patient': patientId.toString()});
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      setState(() => _knownPeopleCount = list.length);
    }
  }

  Future<void> _loadHistoryCount(String? token, int patientId) async {
    if (token == null) return;
    final response = await _api.get('/history/', token: token, params: {'patient': patientId.toString()});
    if (response.statusCode == 200) {
      final list = json.decode(response.body) as List<dynamic>;
      setState(() => _historyCount = list.length);
    }
  }

  Future<void> _loadSafeZoneLabel(String? token, int patientId) async {
    if (token == null) return;
    final response = await _api.get('/patients/$patientId/safe-zone/', token: token);
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final radius = data['radius_meters']?.toStringAsFixed(0);
      setState(() => _safeZoneLabel = radius != null ? '${radius}m from Home' : 'Set limit');
      return;
    }
    setState(() => _safeZoneLabel = 'Set limit');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading
            ? _buildLoadingState()
            : (_patient == null ? _buildEmptyState(context) : _buildPatientOverview(context)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final refresh = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const PatientDetailScreen()),
          );
          if (refresh == true) {
            _loadPatient();
          }
        },
        child: Icon(_patient == null ? Icons.add : Icons.edit),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        Card(
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary.withAlpha(36),
                  ),
                  child: Icon(Icons.person_add_alt_1, size: 36, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 20),
                const Text('Add patient details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text(
                  'Name, date of birth, and a live face scan',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    final refresh = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const PatientDetailScreen()),
                    );
                    if (refresh == true) {
                      _loadPatient();
                    }
                  },
                  child: const Text('Add patient details'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildDisabledLink(context, Icons.group, 'Known People'),
        const SizedBox(height: 12),
        _buildDisabledLink(context, Icons.history, 'History'),
        const SizedBox(height: 12),
        _buildDisabledLink(context, Icons.location_on, 'Set Limit'),
      ],
    );
  }

  Widget _buildPatientOverview(BuildContext context) {
    final name = _patient?['name'] as String? ?? 'Unknown';
    final dateOfBirth = _patient?['date_of_birth'] as String?;
    final age = _patient?['age'];
    final birthdayText = _formatBirthday(dateOfBirth, age);
    final safeZoneText = _safeZoneLabel ?? 'Set limit';
    final patientId = _patient?['id'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    name.isNotEmpty ? name.split(' ').map((word) => word.isNotEmpty ? word[0] : '').take(2).join() : 'P',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(height: 20),
                Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(birthdayText, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildOverviewLink(
          context,
          icon: Icons.group,
          label: 'Known People',
          value: '$_knownPeopleCount people added',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => KnownPersonListScreen(patientId: patientId)));
          },
        ),
        const SizedBox(height: 12),
        _buildOverviewLink(
          context,
          icon: Icons.history,
          label: 'History',
          value: '$_historyCount entries this week',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryDashboardScreen(patientId: patientId)));
          },
        ),
        const SizedBox(height: 12),
        _buildOverviewLink(
          context,
          icon: Icons.location_on,
          label: 'Set Limit',
          value: safeZoneText,
          onTap: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => SafeZoneScreen(patientId: patientId)),
            );
            if (saved == true) {
              _loadPatient();
            }
          },
        ),
      ],
    );
  }

  Widget _buildDisabledLink(BuildContext context, IconData icon, String label) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey),
        title: Text(label, style: const TextStyle(color: Color.fromARGB(115, 227, 224, 224), fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey),
      ),
    );
  }

  Widget _buildOverviewLink(BuildContext context, {required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(32),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(value, style: const TextStyle(color: Color.fromARGB(136, 53, 52, 52))),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }

  String _formatBirthday(String? dateOfBirth, dynamic age) {
    if (dateOfBirth != null && dateOfBirth.isNotEmpty) {
      try {
        final parsed = DateTime.parse(dateOfBirth);
        const months = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return 'Born ${months[parsed.month - 1]} ${parsed.year}';
      } catch (_) {
        return age != null ? 'Age: $age' : 'Birthday not set';
      }
    }
    if (age != null) {
      return 'Age: $age';
    }
    return 'Birthday not set';
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Provider.of<AuthService>(context, listen: false).logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const FaceScanScreen()),
                (route) => false,
              );
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

