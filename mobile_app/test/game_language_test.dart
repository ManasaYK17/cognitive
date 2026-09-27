import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cognitive_assist_app/services/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('game instructions and Improvements labels exist in every supported language', () async {
    final appLanguage = AppLanguage();
    await appLanguage.setLanguage('English');

    for (final language in AppLanguage.supportedLanguages) {
      await appLanguage.setLanguage(language);
      expect(appLanguage.translate('game_sequence_memory'), isNot('game_sequence_memory'));
      expect(appLanguage.translate('sequence_observe'), contains('{number}'));
      expect(appLanguage.translate('routine_after'), contains('{activity}'));
      expect(appLanguage.translate('missing_question'), isNot('missing_question'));
      expect(appLanguage.translate('improvements_performance'), isNot('improvements_performance'));
    }

    await appLanguage.setLanguage('English');
  });
}