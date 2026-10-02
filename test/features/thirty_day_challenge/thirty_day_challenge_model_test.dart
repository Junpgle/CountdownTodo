import 'package:countdown_todo/features/thirty_day_challenge/models/thirty_day_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只有内置任务清单会被标记为内置挑战', () {
    final startedAt = DateTime(2026, 10, 2);
    final builtIn = ThirtyDayChallengeState.initial(startedAt: startedAt);
    final restored = ThirtyDayChallengeState.fromJson(builtIn.toJson());
    final legacyRestored = ThirtyDayChallengeState.fromJson(
      Map<String, dynamic>.from(builtIn.toJson())..remove('is_built_in'),
    );
    final custom = ThirtyDayChallengeState.custom(
      title: ThirtyDayChallengeState.defaultTitle,
      taskTitles: [
        for (var index = 0; index < 30; index++) '自定义任务 ${index + 1}',
      ],
      startedAt: startedAt,
    );
    final customWithClassicTasks = ThirtyDayChallengeState.custom(
      title: ThirtyDayChallengeState.defaultTitle,
      taskTitles: builtIn.tasks.map((task) => task.originalTitle),
      startedAt: startedAt,
    );
    final restoredCustomWithClassicTasks = ThirtyDayChallengeState.fromJson(
      customWithClassicTasks.toJson(),
    );

    expect(builtIn.isBuiltIn, isTrue);
    expect(restored.isBuiltIn, isTrue);
    expect(legacyRestored.isBuiltIn, isTrue);
    expect(custom.isBuiltIn, isFalse);
    expect(customWithClassicTasks.isBuiltIn, isFalse);
    expect(restoredCustomWithClassicTasks.isBuiltIn, isFalse);
  });
}
