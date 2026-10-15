import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/services/todo_completion_celebration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TodoCompletionCelebrationService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await TodoCompletionCelebrationService.ensureInitialized();
    });

    test('default preferences are both enabled', () {
      expect(TodoCompletionCelebrationService.isHapticsEnabled, isTrue);
      expect(TodoCompletionCelebrationService.isCelebrationEnabled, isTrue);
    });

    test('setHapticsEnabled persists to preferences', () async {
      await TodoCompletionCelebrationService.setHapticsEnabled(false);
      expect(TodoCompletionCelebrationService.isHapticsEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('todo_completion_haptics_enabled'), isFalse);

      await TodoCompletionCelebrationService.setHapticsEnabled(true);
      expect(TodoCompletionCelebrationService.isHapticsEnabled, isTrue);
    });

    test('setCelebrationEnabled persists to preferences', () async {
      await TodoCompletionCelebrationService.setCelebrationEnabled(false);
      expect(TodoCompletionCelebrationService.isCelebrationEnabled, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('todo_all_done_celebration_enabled'), isFalse);

      await TodoCompletionCelebrationService.setCelebrationEnabled(true);
      expect(TodoCompletionCelebrationService.isCelebrationEnabled, isTrue);
    });

    test('play impacts run without throwing', () {
      expect(
        () => TodoCompletionCelebrationService.playCompletionImpact(),
        returnsNormally,
      );
      expect(
        () => TodoCompletionCelebrationService.playCelebrationImpact(),
        returnsNormally,
      );
    });
  });
}
