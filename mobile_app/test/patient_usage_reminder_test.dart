import 'package:flutter_test/flutter_test.dart';
import 'package:cognitive_assist_app/screens/reminder_alarm_screen.dart';

void main() {
  test('usage reminder is built with a clear patient-mode reminder message', () {
    final reminder = ReminderAlarmScreen.buildUsageReminder();

    expect(reminder['type'], 'usage');
    expect(reminder['message'], contains('still using'));
  });
}
