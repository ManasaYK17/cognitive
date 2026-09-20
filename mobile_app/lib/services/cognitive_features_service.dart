import 'dart:convert';
import 'api_client.dart';

class CognitiveFeaturesService {
  final ApiClient _api = ApiClient();

  Future<List<dynamic>> getReminders(String token, {int? patientId}) async {
    final response = await _api.get('/cognitive/reminders/', token: token, params: patientId == null ? null : {'patient': '$patientId'});
    if (response.statusCode != 200) throw StateError('Unable to load reminders.');
    return json.decode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createReminder(String token, Map<String, dynamic> data) async {
    final response = await _api.post('/cognitive/reminders/', token: token, body: data);
    if (response.statusCode != 201) throw StateError(_message(response.body, 'Unable to save reminder.'));
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateReminderStatus(String token, int id, String status) async {
    final response = await _api.put('/cognitive/reminders/$id/status/', token: token, body: {'status': status});
    if (response.statusCode != 200) throw StateError('Unable to update reminder.');
    return json.decode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteReminder(String token, int id) async {
    final response = await _api.delete('/cognitive/reminders/$id/', token: token);
    if (response.statusCode != 204) throw StateError('Unable to delete reminder.');
  }

  Future<void> saveGameResult(String token, Map<String, dynamic> data) async {
    final response = await _api.post('/cognitive/games/', token: token, body: data);
    if (response.statusCode != 201) throw StateError('Score could not be saved.');
  }

  Future<List<dynamic>> getGameResults(String token, int patientId) async {
    final response = await _api.get('/cognitive/games/', token: token, params: {'patient': '$patientId'});
    if (response.statusCode != 200) throw StateError('Unable to load game results.');
    return json.decode(response.body) as List<dynamic>;
  }

  String _message(String body, String fallback) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['detail'] != null) return decoded['detail'].toString();
    } catch (_) {}
    return fallback;
  }
}
