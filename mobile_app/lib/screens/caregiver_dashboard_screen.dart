import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'patient_detail_screen.dart';
import 'known_person_list_screen.dart';
import 'history_dashboard_screen.dart';
import 'safe_zone_screen.dart';
import 'patient_location_screen.dart';
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
          const SizedBox(height: 18),
          _sidebarItem(
            icon: Icons.my_location,
            label: 'Location',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PatientLocationScreen(
                    patientId: patientId,
                    patientName: _patient?['name'] as String? ?? 'Patient',
                  ),
                ),
              );
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
    final initials = name.isNotEmpty
        ? name.split(' ').where((word) => word.isNotEmpty).take(2).map((word) => word[0]).join().toUpperCase()
        : 'P';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 31,
            backgroundColor: const Color(0xFF1F2937),
            child: Text(
              initials,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'serif'),
                ),
                const SizedBox(height: 4),
                Text(birthdayText, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PatientDetailScreen()));
            },
            icon: const Icon(Icons.edit, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required Color background,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: valueColor.withAlpha(230), fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 30, fontWeight: FontWeight.w900),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }

  Widget _buildMetricRow({required List<Widget> children}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityItem({required String title, required String timestamp, required IconData icon, required Color iconColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(timestamp, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return 'recently checked';
    }

    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return 'recently checked';
    }

    final difference = DateTime.now().difference(parsed);
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} min ago';
    }
    return 'just now';
  }

  String _formatDistance(double? meters) {
    if (meters == null) {
      return 'distance unavailable';
    }
    final miles = meters / 1609.344;
    return '${miles.toStringAsFixed(1)} mi';
  }

  Widget _buildDashboardContent(BuildContext context) {
    final name = _patient?['name'] as String? ?? 'Patient';
    final age = _patient?['age'] as int?;
    final birthdayText = age != null ? 'Age $age' : _formatBirthday(_patient?['date_of_birth'] as String?, _patient?['age']);
    final summary = _summary ?? <String, dynamic>{};
    final today = summary['today'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final weeklyCounts = (summary['weekly_counts'] as List<dynamic>?) ?? <dynamic>[];
    final knownVsUnknown = summary['known_vs_unknown'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final safeZone = summary['safe_zone'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final recentActivity = (summary['recent_activity'] as List<dynamic>?) ?? <dynamic>[];

    final knownPercent = (knownVsUnknown['known_percent'] as num?)?.toDouble() ?? 0.0;
    final unknownPercent = (knownVsUnknown['unknown_percent'] as num?)?.toDouble() ?? 0.0;
    final weeklyLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weeklyMap = {for (final entry in weeklyCounts) (entry as Map<String, dynamic>)['day'] as String? ?? '': (entry['count'] as num?)?.toDouble() ?? 0.0};
    final weeklyValues = weeklyLabels.map((label) => weeklyMap[label] ?? 0.0).toList();
    final weeklyMax = weeklyValues.isEmpty ? 4.0 : weeklyValues.reduce((a, b) => a > b ? a : b) + 2;
    final safeZoneName = safeZone['name'] as String? ?? 'Home';
    final statusInside = safeZone['inside'] as bool? ?? false;
    final statusConfigured = safeZone['configured'] as bool? ?? false;

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 400 ? 16.0 : 26.0;
    final barWidth = screenWidth < 400 ? 14.0 : 18.0;

    return Container(
      color: const Color(0xFF0A0F1D),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dashboard', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Overview of the patient’s detection activity', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 24),
              _buildMainCard(context, name, birthdayText),
              const SizedBox(height: 22),
              const Text('Today\'s detections', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _buildMetricRow(
                children: [
                  _buildMetricCard(
                    title: 'Known people',
                    value: '${today['known_detections'] ?? 0}',
                    background: const Color(0xFF064E3B),
                    valueColor: const Color(0xFF6EE7B7),
                  ),
                  _buildMetricCard(
                    title: 'Unknown',
                    value: '${today['unknown_detections'] ?? 0}',
                    background: const Color(0xFF78350F),
                    valueColor: const Color(0xFFFBCF3F),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildMetricRow(
                children: [
                  _buildMetricCard(
                    title: 'Conversations saved',
                    value: '${summary['conversations_saved'] ?? 0}',
                    background: const Color(0xFF111827),
                    valueColor: Colors.white,
                  ),
                  _buildMetricCard(
                    title: 'Avg. match confidence',
                    value: '${summary['average_match_confidence']?.toStringAsFixed(0) ?? '0'}%',
                    background: const Color(0xFF111827),
                    valueColor: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Detections this week', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          maxY: weeklyMax,
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: const BarTouchData(enabled: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= weeklyLabels.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(weeklyLabels[index], style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(show: false),
                          barGroups: List.generate(weeklyLabels.length, (index) {
                            final count = weeklyValues[index];
                            return BarChartGroupData(
                              x: index,
                              barRods: [
                                BarChartRodData(
                                  toY: count,
                                  color: const Color(0xFF10B981),
                                  width: barWidth,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionCard(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pieSize = constraints.maxWidth < 360
                        ? constraints.maxWidth * 0.42
                        : 180.0;
                    final pie = SizedBox(
                      width: pieSize,
                      height: pieSize,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: pieSize * 0.27,
                          sections: [
                            PieChartSectionData(
                              color: const Color(0xFF10B981),
                              value: knownPercent,
                              title: '',
                              radius: pieSize * 0.31,
                            ),
                            PieChartSectionData(
                              color: const Color(0xFFF59E0B),
                              value: unknownPercent,
                              title: '',
                              radius: pieSize * 0.31,
                            ),
                          ],
                        ),
                      ),
                    );
                    final legend = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Known vs unknown, this week', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        _buildLegendItem(label: 'Known', percent: knownPercent, color: const Color(0xFF10B981)),
                        const SizedBox(height: 10),
                        _buildLegendItem(label: 'Unknown', percent: unknownPercent, color: const Color(0xFFF59E0B)),
                      ],
                    );

                    if (constraints.maxWidth < 320) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: pie),
                          const SizedBox(height: 18),
                          legend,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        pie,
                        const SizedBox(width: 20),
                        Expanded(child: legend),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Safe zone status', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusConfigured && statusInside ? const Color(0xFF065F46) : const Color(0xFF7C2D12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusConfigured ? (statusInside ? 'Inside' : 'Outside') : 'Not set',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${_formatDistance(safeZone['distance_meters'] as double?)} from $safeZoneName · last checked ${_formatRelativeTime(safeZone['last_checked_at'] as String?)}',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _buildSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recent activity', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    if (recentActivity.isEmpty)
                      Text('No recent activity yet', style: TextStyle(color: Colors.grey.shade500))
                    else
                      ...recentActivity.take(5).map((entry) {
                        final activity = entry as Map<String, dynamic>;
                        final title = activity['title'] as String? ?? 'Activity';
                        final timestamp = activity['timestamp'] as String? ?? '';
                        final outcome = activity['outcome'] as String?;
                        final eventType = activity['event_type'] as String? ?? '';
                        late IconData icon;
                        late Color iconColor;
                        if (eventType == 'conversation') {
                          icon = Icons.chat_bubble_outline;
                          iconColor = const Color(0xFF60A5FA);
                        } else if (outcome == 'not_matched') {
                          icon = Icons.warning_amber_rounded;
                          iconColor = const Color(0xFFF59E0B);
                        } else {
                          icon = Icons.visibility_outlined;
                          iconColor = const Color(0xFF10B981);
                        }
                        return _buildActivityItem(title: title, timestamp: _formatRelativeTime(timestamp), icon: icon, iconColor: iconColor);
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem({required String label, required double percent, required Color color}) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999))),
        const SizedBox(width: 10),
        Text('$label — ${percent.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
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

