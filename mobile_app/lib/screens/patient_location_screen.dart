import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class PatientLocationScreen extends StatefulWidget {
  final int patientId;
  final String patientName;
  final double? initialLatitude;
  final double? initialLongitude;

  const PatientLocationScreen({
    required this.patientId,
    required this.patientName,
    this.initialLatitude,
    this.initialLongitude,
    super.key,
  });

  @override
  State<PatientLocationScreen> createState() => _PatientLocationScreenState();
}

class _PatientLocationScreenState extends State<PatientLocationScreen> {
  static const _pollInterval = Duration(seconds: 12);

  final ApiClient _api = ApiClient();
  GoogleMapController? _mapController;
  Timer? _pollTimer;

  double? _latitude;
  double? _longitude;
  double? _distanceMeters;
  bool? _insideSafeZone;
  DateTime? _lastUpdated;
  Map<String, dynamic>? _safeZone;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _latitude = widget.initialLatitude;
    _longitude = widget.initialLongitude;
    _fetchLocation();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetchLocation(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);

    final token = Provider.of<AuthService>(context, listen: false).accessToken;
    try {
      final response = await _api.get('/patients/${widget.patientId}/location/latest/', token: token);
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          _latitude = (data['latitude'] as num?)?.toDouble();
          _longitude = (data['longitude'] as num?)?.toDouble();
          _distanceMeters = (data['distance_from_center_meters'] as num?)?.toDouble();
          _insideSafeZone = data['inside_safe_zone'] as bool?;
          _lastUpdated = DateTime.tryParse(data['timestamp'] as String? ?? '');
          _safeZone = data['safe_zone'] as Map<String, dynamic>?;
          _loading = false;
          _error = null;
        });
        _moveCamera();
      } else if (response.statusCode == 404) {
        setState(() {
          _loading = false;
          _error = 'No location data available yet.';
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_latitude == null) _error = 'Unable to reach the server.';
      });
    }
  }

  void _moveCamera() {
    if (_latitude == null || _longitude == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLng(LatLng(_latitude!, _longitude!)));
  }

  String _formatRelativeTime(DateTime? time) {
    if (time == null) return 'unknown';
    final difference = DateTime.now().difference(time);
    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = _latitude != null && _longitude != null;
    final safeZoneRadius = (_safeZone?['radius_meters'] as num?)?.toDouble();
    final safeZoneCenter = _safeZone != null &&
            _safeZone!['center_latitude'] != null &&
            _safeZone!['center_longitude'] != null
        ? LatLng(
            (_safeZone!['center_latitude'] as num).toDouble(),
            (_safeZone!['center_longitude'] as num).toDouble(),
          )
        : null;

    return Scaffold(
      appBar: AppBar(title: Text("${widget.patientName}'s location")),
      body: !hasLocation
          ? Center(child: Text(_error ?? (_loading ? '' : 'No location data available yet.')))
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: LatLng(_latitude!, _longitude!), zoom: 16),
                  onMapCreated: (controller) => _mapController = controller,
                  markers: {
                    Marker(
                      markerId: const MarkerId('patient'),
                      position: LatLng(_latitude!, _longitude!),
                      infoWindow: InfoWindow(title: widget.patientName),
                    ),
                  },
                  circles: safeZoneCenter != null && safeZoneRadius != null
                      ? {
                          Circle(
                            circleId: const CircleId('safe_zone'),
                            center: safeZoneCenter,
                            radius: safeZoneRadius,
                            strokeColor: Colors.blue,
                            strokeWidth: 2,
                            fillColor: Colors.blue.withAlpha(30),
                          ),
                        }
                      : {},
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _buildStatusCard(),
                ),
                if (_loading)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                  ),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    final statusText =
        _insideSafeZone == null ? 'Safe zone not set' : (_insideSafeZone! ? 'Inside safe zone' : 'Outside safe zone');
    final statusColor = _insideSafeZone == true ? const Color(0xFF10B981) : const Color(0xFFDC2626);
    final distanceText = _distanceMeters != null ? ' · ${_distanceMeters!.toStringAsFixed(0)}m from center' : '';

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$statusText$distanceText', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Updated ${_formatRelativeTime(_lastUpdated)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
