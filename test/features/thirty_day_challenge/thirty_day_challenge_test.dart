import 'dart:convert';
import 'dart:math';

import 'package:countdown_todo/features/thirty_day_challenge/models/thirty_day_challenge.dart';
import 'package:countdown_todo/features/thirty_day_challenge/repositories/thirty_day_challenge_repository.dart';
import 'package:countdown_todo/features/thirty_day_challenge/screens/thirty_day_challenge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initializes 30 independent tasks in the original order', () {
    final state = ThirtyDayChallengeState.initial(
      startedAt: DateTime(2026, 8, 2),
    );

    expect(state.tasks, hasLength(30));
    expect(state.tasks.first.id, 1);
    expect(state.tasks.first.title, '去一间从来没去过的餐厅');
    expect(state.tasks.last.id, 30);
    expect(state.completedCount, 0);
    expect(state.progress, 0);
  });

  test('random selection only returns unfinished tasks', () {
    final state = ThirtyDayChallengeState.initial();
    for (final task in state.tasks.take(29)) {
      task.isCompleted = true;
    }

    expect(state.randomUnfinishedTask(Random(1))?.id, 30);
    expect(state.unfinishedTasks, hasLength(1));
  });

  test('persists completion and an independent feeling per task', () async {
    final state = await ThirtyDayChallengeRepository.load();
    final completedAt = DateTime(2026, 8, 2, 19, 30);

    await ThirtyDayChallengeRepository.updateTask(
      state,
      7,
      customTitle: '和家人吃一顿大餐',
      feeling: '原来一起吃饭本身就是很好的礼物。',
      imageBase64: base64Encode([1, 2, 3, 4]),
    );
    await ThirtyDayChallengeRepository.setCompleted(
      state,
      7,
      true,
      completedAt: completedAt,
    );

    final loaded = await ThirtyDayChallengeRepository.load();
    final task = loaded.tasks[6];
    expect(task.title, '和家人吃一顿大餐');
    expect(task.isCompleted, isTrue);
    expect(task.completedAt, completedAt);
    expect(task.feeling, '原来一起吃饭本身就是很好的礼物。');
    expect(task.imageBase64, base64Encode([1, 2, 3, 4]));
    expect(loaded.completedCount, 1);
  });

  test('task image data survives model serialization', () {
    final task = ThirtyDayChallengeTask(
      id: 1,
      originalTitle: '去一间从来没去过的餐厅',
      imageBase64: base64Encode([10, 20, 30]),
    );

    final restored = ThirtyDayChallengeTask.fromJson(task.toJson());
    expect(restored.imageBase64, task.imageBase64);
  });

  test('completion can be undone without deleting the feeling', () async {
    final state = await ThirtyDayChallengeRepository.load();
    await ThirtyDayChallengeRepository.updateTask(
      state,
      3,
      feeling: '重新联系上老朋友，很开心。',
    );
    await ThirtyDayChallengeRepository.setCompleted(state, 3, true);
    await ThirtyDayChallengeRepository.setCompleted(state, 3, false);

    final loaded = await ThirtyDayChallengeRepository.load();
    final task = loaded.tasks[2];
    expect(task.isCompleted, isFalse);
    expect(task.completedAt, isNull);
    expect(task.feeling, '重新联系上老朋友，很开心。');
  });

  test('resetting progress keeps the task records', () async {
    final state = await ThirtyDayChallengeRepository.load();
    await ThirtyDayChallengeRepository.updateTask(
      state,
      5,
      feeling: '离开网络后，注意到了平时忽略的声音。',
      imageBase64: base64Encode([5, 6, 7]),
    );
    await ThirtyDayChallengeRepository.setCompleted(state, 5, true);

    await ThirtyDayChallengeRepository.resetProgress(state);

    final loaded = await ThirtyDayChallengeRepository.load();
    final task = loaded.tasks[4];
    expect(task.isCompleted, isFalse);
    expect(task.completedAt, isNull);
    expect(task.feeling, '离开网络后，注意到了平时忽略的声音。');
    expect(task.imageBase64, base64Encode([5, 6, 7]));
  });

  test('challenge intro is shown only once per account', () async {
    expect(await ThirtyDayChallengeRepository.hasSeenIntro(), isFalse);

    await ThirtyDayChallengeRepository.markIntroSeen();

    expect(await ThirtyDayChallengeRepository.hasSeenIntro(), isTrue);
    expect(await ThirtyDayChallengeRepository.hasStarted(), isTrue);
  });

  test(
    'pausing hides participation without deleting challenge records',
    () async {
      final state = await ThirtyDayChallengeRepository.load();
      await ThirtyDayChallengeRepository.markIntroSeen();
      await ThirtyDayChallengeRepository.updateTask(
        state,
        2,
        feeling: '换一种交通工具回家，发现了新的风景。',
      );
      await ThirtyDayChallengeRepository.setCompleted(state, 2, true);

      await ThirtyDayChallengeRepository.setPaused(true);

      expect(await ThirtyDayChallengeRepository.hasStarted(), isTrue);
      expect(await ThirtyDayChallengeRepository.isPaused(), isTrue);
      final loaded = await ThirtyDayChallengeRepository.load();
      expect(loaded.tasks[1].isCompleted, isTrue);
      expect(loaded.tasks[1].feeling, '换一种交通工具回家，发现了新的风景。');

      await ThirtyDayChallengeRepository.setPaused(false);
      expect(await ThirtyDayChallengeRepository.isPaused(), isFalse);
    },
  );

  test(
    'abandon clears all challenge records and participation state',
    () async {
      final state = await ThirtyDayChallengeRepository.load();
      await ThirtyDayChallengeRepository.markIntroSeen();
      await ThirtyDayChallengeRepository.updateTask(
        state,
        1,
        customTitle: '去一家真正陌生的餐厅',
        feeling: '这次体验值得重新记住。',
        imageBase64: base64Encode([8, 9, 10]),
      );
      await ThirtyDayChallengeRepository.setCompleted(state, 1, true);

      await ThirtyDayChallengeRepository.abandonChallenge();

      expect(await ThirtyDayChallengeRepository.hasStarted(), isFalse);
      expect(await ThirtyDayChallengeRepository.hasSeenIntro(), isFalse);
      expect(await ThirtyDayChallengeRepository.isPaused(), isFalse);
      final resetState = await ThirtyDayChallengeRepository.load();
      final task = resetState.tasks.first;
      expect(task.title, task.originalTitle);
      expect(task.isCompleted, isFalse);
      expect(task.feeling, isEmpty);
      expect(task.imageBase64, isNull);
    },
  );

  testWidgets('challenge screen shows progress and random task action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const ThirtyDayChallengeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.textContaining('你有多久没尝试过'), findsOneWidget);
    expect(find.text('开始这场挑战'), findsOneWidget);
    expect(find.text('暂不参与'), findsOneWidget);

    await tester.ensureVisible(find.text('开始这场挑战'));
    await tester.tap(find.text('开始这场挑战'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了，开始挑战'));
    await tester.pumpAndSettle();

    expect(find.text('0/30'), findsOneWidget);
    expect(find.byTooltip('随机一个任务'), findsOneWidget);
    expect(find.text('导出并分享'), findsOneWidget);
    expect(find.text('重置状态'), findsOneWidget);
    expect(find.text('暂停挑战'), findsOneWidget);
    expect(find.text('放弃挑战'), findsOneWidget);
    expect(find.text('去一间从来没去过的餐厅'), findsOneWidget);

    await tester.tap(find.byTooltip('随机一个任务'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在寻找一项没做过的事'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.textContaining('项 / 30'), findsOneWidget);
  });

  testWidgets('challenge screen adapts to landscape layout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(900, 500)),
          child: const ThirtyDayChallengeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('开始这场挑战'));
    await tester.tap(find.text('开始这场挑战'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了，开始挑战'));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byTooltip('随机一个任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling task edit closes the dialog cleanly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const ThirtyDayChallengeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('开始这场挑战'));
    await tester.tap(find.text('开始这场挑战'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了，开始挑战'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('调整任务').first);
    await tester.tap(find.byTooltip('调整任务').first);
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsNothing);
    expect(find.byTooltip('调整任务').first, findsOneWidget);
  });
}
