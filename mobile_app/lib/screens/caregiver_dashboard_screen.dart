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
  bool _sidebarExpanded = false;
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadPatient();
  }

  Future<void> _loadPatient() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });

    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    final response = await _api.get('/patients/', token: token);

    if (!mounted) return;
    if (response.statusCode == 200) {
      final patient = json.decode(response.body) as Map<String, dynamic>;
      final patientId = patient['id'] as int;
      if (token != null) {
        final summaryResponse = await _api.get('/patients/$patientId/dashboard-summary/', token: token);
        if (!mounted) return;
        if (summaryResponse.statusCode == 200) {
          final summary = json.decode(summaryResponse.body) as Map<String, dynamic>;
          setState(() {
            _patient = patient;
            _summary = summary;
            _loading = false;
          });
          return;
        }
      }
      setState(() {
        _patient = patient;
        _summary = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _patient = null;
      _summary = null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_patient == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildEmptyState(context),
          ),
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
          child: const Icon(Icons.add),
        ),
      );
    }

    final patientId = _patient?['id'] as int;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(context, patientId),
            Expanded(child: _buildDashboardContent(context)),
          ],
        ),
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
        child: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, int patientId) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: _sidebarExpanded ? 210 : 76,
      color: const Color(0xFF111827),
      child: Column(
        children: [
          const SizedBox(height: 18),
          _buildSidebarToggle(context),
          const SizedBox(height: 26),
          _sidebarItem(
            icon: Icons.dashboard,
            label: 'Dashboard',
            onTap: () {},
          ),
          const SizedBox(height: 18),
          _sidebarItem(
            icon: Icons.group,
            label: 'Known people',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => KnownPersonListScreen(patientId: patientId)));
            },
          ),
          const SizedBox(height: 18),
          _sidebarItem(
            icon: Icons.history,
            label: 'History',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryDashboardScreen(patientId: patientId)));
            },
          ),
          const SizedBox(height: 18),
          _sidebarItem(
            icon: Icons.location_on,
            label: 'Safe Zone',
            onTap: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => SafeZoneScreen(patientId: patientId)),
              );
              if (saved == true) {
                _loadPatient();
              }
            },
          ),
          const Spacer(),
          _sidebarItem(
            icon: Icons.logout,
            label: 'Log out',
            onTap: () => _confirmLogout(context),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle(BuildContext context) {
    return InkWell(
      onTap: () {
        setState(() {
          _sidebarExpanded = !_sidebarExpanded;
        });
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Transform.rotate(
          angle: _sidebarExpanded ? 3.14 : 0,
          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _sidebarItem({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        height: 54,
        padding: EdgeInsets.symmetric(horizontal: _sidebarExpanded ? 16 : 0),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: _sidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 26),
            if (_sidebarExpanded) ...[
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainCard(BuildContext context, String name, String birthdayText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name.split(' ').where((word) => word.isNotEmpty).take(2).map((word) => word[0]).join() : 'P',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(birthdayText, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.edit, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({required String title, required String value, required Color background, required Color valueColor}) {
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: valueColor.withAlpha(230), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Text(value, style: TextStyle(color: valueColor, fontSize: 34, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context) {
    final name = _patient?['name'] as String? ?? 'Patient';
    final age = _patient?['age'] as int?;
    final birthdayText = age != null ? 'Age $age' : _formatBirthday(_patient?['date_of_birth'] as String?, _patient?['age']);
    final summary = _summary ?? <String, dynamic>{};
    final today = summary['today'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final weeklyCounts = (summary['weekly_counts'] as List<dynamic>?) ?? <dynamic>[];

    return Container(
      color: const Color(0xFF0A0F1D),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dashboard', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Overview of the patient’s detection activity', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 24),
              _buildMainCard(context, name, birthdayText),
              const SizedBox(height: 22),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatTile(
                    title: 'Known people',
                    value: '${today['known_detections'] ?? 0}',
                    background: const Color(0xFF064E3B),
                    valueColor: const Color(0xFF6EE7B7),
                  ),
                  _buildStatTile(
                    title: 'Unknown',
                    value: '${today['unknown_detections'] ?? 0}',
                    background: const Color(0xFF78350F),
                    valueColor: const Color(0xFFFBCF3F),
                  ),
                  _buildStatTile(
                    title: 'Conversations saved',
                    value: '${summary['conversations_saved'] ?? 0}',
                    background: const Color(0xFF111827),
                    valueColor: Colors.white,
                  ),
                  _buildStatTile(
                    title: 'Avg. match confidence',
                    value: '${summary['average_match_confidence']?.toStringAsFixed(0) ?? '0'}%',
                    background: const Color(0xFF111827),
                    valueColor: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Detections this week', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                        Text('View all', style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 220,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: weeklyCounts.isEmpty
                            ? [
                                Expanded(
                                  child: Center(
                                    child: Text('No detections yet', style: TextStyle(color: Colors.grey.shade500)),
                                  ),
                                )
                              ]
                            : weeklyCounts.map((entry) {
                                final item = entry as Map<String, dynamic>;
                                final label = item['day'] as String? ?? '';
                                final count = (item['count'] as num?)?.toDouble() ?? 0;
                                final height = 28.0 + (count * 16).clamp(0.0, 150.0);
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          height: height,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981),
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 6),
                                        Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add patient details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text('Name, date of birth, and a live face scan', style: TextStyle(color: Colors.black54)),
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

