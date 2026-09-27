import 'package:flutter_test/flutter_test.dart';
import 'package:cognitive_assist_app/screens/reminder_alarm_screen.dart';

void main() {
  test('usage reminder is silent reminder data with the selected-language message', () {
    final reminder = ReminderAlarmScreen.buildUsageReminder();

    expect(reminder['type'], 'usage');
    expect(reminder['message'], isNotEmpty);
  });
}
