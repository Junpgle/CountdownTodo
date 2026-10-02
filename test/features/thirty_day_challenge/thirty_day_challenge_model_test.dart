import 'package:countdown_todo/features/thirty_day_challenge/models/thirty_day_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('开始并重载经典挑战后仍保留内置类型', () async {
    final started = await ThirtyDayChallengeRepository.startBuiltInChallenge();
    final restored = await ThirtyDayChallengeRepository.load();

    expect(started.isBuiltIn, isTrue);
    expect(restored.isBuiltIn, isTrue);
  });

  test('挑战备份往返保留进度、记录和参与状态', () async {
    final started = await ThirtyDayChallengeRepository.startNewChallenge(
      title: '周末阅读计划',
      taskTitles: ['读完一本书', '写下三条感想'],
    );
    await ThirtyDayChallengeRepository.updateTask(
      started,
      1,
      customTitle: '读完一本小说',
      feeling: '读完后心情放松。',
      imageBase64: 'aW1hZ2U=',
    );
    await ThirtyDayChallengeRepository.setCompleted(
      started,
      1,
      true,
      completedAt: DateTime(2026, 10, 2, 19),
    );
    await ThirtyDayChallengeRepository.setPaused(true);
    await ThirtyDayChallengeRepository.dismissHabitCenterPromotion();

    final bundle = await ThirtyDayChallengeRepository.exportBackup();
    expect(bundle, isNotNull);
    await ThirtyDayChallengeRepository.abandonChallenge();
    expect(
      await ThirtyDayChallengeRepository.importBackup(bundle!),
      2,
    );

    final restored = await ThirtyDayChallengeRepository.load();
    expect(restored.challengeTitle, '周末阅读计划');
    expect(restored.tasks.first.title, '读完一本小说');
    expect(restored.tasks.first.isCompleted, isTrue);
    expect(restored.tasks.first.feeling, '读完后心情放松。');
    expect(restored.tasks.first.imageBase64, 'aW1hZ2U=');
    expect(await ThirtyDayChallengeRepository.hasStarted(), isTrue);
    expect(await ThirtyDayChallengeRepository.hasSeenIntro(), isTrue);
    expect(await ThirtyDayChallengeRepository.isPaused(), isTrue);
    expect(
      await ThirtyDayChallengeRepository.isHabitCenterPromotionDismissed(),
      isTrue,
    );
  });

  test('备份导入导出按调用方账号读写，不跟随切换后的登录账号', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_login_user', 'source');
    await ThirtyDayChallengeRepository.startNewChallenge(
      title: '来源账号挑战',
      taskTitles: ['保留来源账号的数据'],
    );
    final bundle = await ThirtyDayChallengeRepository.exportBackup(
      username: 'source',
    );

    await prefs.setString('current_login_user', 'bob');
    await ThirtyDayChallengeRepository.startNewChallenge(
      title: 'Bob 的挑战',
      taskTitles: ['不能被来源备份覆盖'],
    );
    await ThirtyDayChallengeRepository.importBackup(
      bundle!,
      username: 'alice',
    );

    expect(
      (await ThirtyDayChallengeRepository.load(username: 'alice')).challengeTitle,
      '来源账号挑战',
    );
    expect(
      (await ThirtyDayChallengeRepository.load(username: 'bob')).challengeTitle,
      'Bob 的挑战',
    );
  });
}
