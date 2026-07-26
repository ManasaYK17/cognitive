// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:cognitive_assist_app/services/api_client.dart';
import 'package:cognitive_assist_app/main.dart';

void main() {
  testWidgets('App shows initial screen', (WidgetTester tester) async {
    await tester.pumpWidget(const CognitiveAssistApp());
    expect(find.text('Checking who\'s here...'), findsOneWidget);
  });

  test('api client expands fallback hosts', () {
    final candidates = ApiClient.getCandidateBaseUrls(
      apiHost: '127.0.0.1:8000',
      apiHostFallback: '10.0.2.2:8000',
    );

    expect(candidates, containsAll(<String>[
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000',
    ]));
  });
}
