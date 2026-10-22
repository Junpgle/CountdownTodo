import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/features/habits/models/habit_goal.dart';
import 'package:countdown_todo/features/habits/services/habit_celebration_service.dart';
import 'package:countdown_todo/features/habits/widgets/habit_celebration_overlay.dart';
import 'package:countdown_todo/features/habits/widgets/habit_celebration_settings_dialog.dart';
import 'package:countdown_todo/features/habits/widgets/habit_checkin_button.dart';
import 'package:countdown_todo/features/habits/widgets/habit_stamp_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testGoal = HabitGoal(
    uuid: 'test_goal_1',
    name: '晨起慢跑',
    icon: '🏃',
    sourceType: HabitSourceType.recurringTodo,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );

  group('HabitCelebrationService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await HabitCelebrationService.ensureInitialized();
      await HabitCelebrationService.setHapticsEnabled(true);
      await HabitCelebrationService.setCelebrationEnabled(true);
      await HabitCelebrationService.setHoldToCheckinEnabled(false);
    });

    test('initial values and setters', () async {
      expect(HabitCelebrationService.isHapticsEnabled, isTrue);
      expect(HabitCelebrationService.isCelebrationEnabled, isTrue);
      expect(HabitCelebrationService.isHoldToCheckinEnabled, isFalse);

      await HabitCelebrationService.setHoldToCheckinEnabled(true);
      expect(HabitCelebrationService.isHoldToCheckinEnabled, isTrue);

      await HabitCelebrationService.setCelebrationEnabled(false);
      expect(HabitCelebrationService.isCelebrationEnabled, isFalse);

      await HabitCelebrationService.setHapticsEnabled(false);
      expect(HabitCelebrationService.isHapticsEnabled, isFalse);
    });

    test('feedback triggers run without errors', () {
      expect(
        () => HabitCelebrationService.playHoldStepImpact(),
        returnsNormally,
      );
      expect(
        () => HabitCelebrationService.playCheckinImpact(),
        returnsNormally,
      );
      expect(
        () => HabitCelebrationService.playGoalMetImpact(),
        returnsNormally,
      );
    });
  });

  group('HabitGoalMetOverlay', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await HabitCelebrationService.ensureInitialized();
      await HabitCelebrationService.setCelebrationEnabled(true);
    });

    testWidgets('renders goal icon, name, streak and dismisses', (
      tester,
    ) async {
      var dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitGoalMetOverlay(
              goal: testGoal,
              streakDays: 7,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('今日习惯达成！'), findsOneWidget);
      expect(find.text('「晨起慢跑」'), findsOneWidget);
      expect(find.text('🏃'), findsOneWidget);
      expect(find.text('🔥 已连续坚持 7 天'), findsOneWidget);

      final btn = find.text('收到 ✨');
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets('showHabitGoalMetCelebration respects celebration switch', (
      tester,
    ) async {
      await HabitCelebrationService.setCelebrationEnabled(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showHabitGoalMetCelebration(context, goal: testGoal);
                },
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      expect(find.text('今日习惯达成！'), findsNothing);
    });
  });

  group('HabitCelebrationTrigger', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await HabitCelebrationService.ensureInitialized();
      await HabitCelebrationService.setHapticsEnabled(false);
      await HabitCelebrationService.setHoldToCheckinEnabled(false);
    });

    testWidgets('tap mode triggers check-in', (tester) async {
      var checkedIn = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HabitCelebrationTrigger(
                enableHoldToCheckin: false,
                onCheckIn: () async {
                  checkedIn = true;
                },
                child: const Text('完成打卡'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('完成打卡'));
      await tester.pump();

      expect(checkedIn, isTrue);
    });

    testWidgets('hold mode triggers check-in on sufficient hold duration', (
      tester,
    ) async {
      var checkedIn = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HabitCelebrationTrigger(
                enableHoldToCheckin: true,
                onCheckIn: () async {
                  checkedIn = true;
                },
                child: const Text('长按打卡'),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('长按打卡')),
      );
      await tester.pump();
      // Hold for more than 560ms
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(checkedIn, isTrue);
    });

    testWidgets('hold mode cancels a short release without checking in', (
      tester,
    ) async {
      var checkInCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCelebrationTrigger(
              enableHoldToCheckin: true,
              semanticLabel: '完成习惯',
              onCheckIn: () async {
                checkInCount++;
              },
              child: const Text('完成打卡'),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('完成打卡')),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(checkInCount, 0);
    });

    testWidgets('hold threshold checks in once and release does not repeat', (
      tester,
    ) async {
      var checkInCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCelebrationTrigger(
              enableHoldToCheckin: true,
              semanticLabel: '完成习惯',
              onCheckIn: () async {
                checkInCount++;
              },
              child: const Text('长按打卡'),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('长按打卡')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(checkInCount, 1);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(checkInCount, 1);
    });

    testWidgets('pointer cancel clears an unfinished hold', (tester) async {
      var checkInCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCelebrationTrigger(
              enableHoldToCheckin: true,
              onCheckIn: () async {
                checkInCount++;
              },
              child: const Text('长按打卡'),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('长按打卡')),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(checkInCount, 0);
    });

    testWidgets('moving outside before the hold threshold cancels check-in', (
      tester,
    ) async {
      var checkInCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HabitCelebrationTrigger(
                enableHoldToCheckin: true,
                onCheckIn: () async {
                  checkInCount++;
                },
                child: const SizedBox(
                  width: 160,
                  height: 64,
                  child: Text('长按打卡'),
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('长按打卡')),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await gesture.moveTo(const Offset(2, 2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(checkInCount, 0);
    });

    testWidgets('disabled or callback-free triggers do not activate', (
      tester,
    ) async {
      var checkInCount = 0;
      Widget buildTrigger({required bool enabled, required bool hasCallback}) =>
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: HabitCelebrationTrigger(
                  enableHoldToCheckin: false,
                  enabled: enabled,
                  onCheckIn: hasCallback
                      ? () async {
                          checkInCount++;
                        }
                      : null,
                  child: const Text('打卡'),
                ),
              ),
            ),
          );

      await tester.pumpWidget(buildTrigger(enabled: false, hasCallback: true));
      await tester.tap(find.text('打卡'));
      await tester.pump();
      expect(checkInCount, 0);

      await tester.pumpWidget(buildTrigger(enabled: true, hasCallback: false));
      await tester.tap(find.text('打卡'));
      await tester.pump();
      expect(checkInCount, 0);
    });

    testWidgets('hold mode exposes an accessible keyboard activation', (
      tester,
    ) async {
      var checkInCount = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCelebrationTrigger(
              enableHoldToCheckin: true,
              semanticLabel: '完成晨跑',
              onCheckIn: () async {
                checkInCount++;
              },
              child: const Text('完成打卡'),
            ),
          ),
        ),
      );

      final actionNode = tester.getSemantics(find.bySemanticsLabel('完成晨跑'));
      expect(
        actionNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(actionNode.hint, contains('轻触会取消蓄力'));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(checkInCount, 1);
      semantics.dispose();
    });
  });

  group('HabitCelebrationSettingsDialog', () {
    testWidgets('can toggle settings and interact with trial widget', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await HabitCelebrationService.ensureInitialized();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => HabitCelebrationSettingsDialog.show(context),
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('打卡仪式感设置'), findsOneWidget);
      expect(find.text('长按蓄力打卡'), findsOneWidget);
      expect(find.text('手感与动效试玩'), findsOneWidget);

      // Tap trial button
      await tester.tap(find.text('点击打卡体验'));
      await tester.pump();

      expect(find.textContaining('已试玩 1 次'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(find.text('打卡仪式感设置'), findsNothing);
    });

    testWidgets('HabitStampBadge renders watermark text and animates', (
      tester,
    ) async {
      bool completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitStampBadge(
              animate: true,
              text: '已达成',
              size: 136,
              opacity: 0.22,
              onAnimationComplete: () => completed = true,
            ),
          ),
        ),
      );

      expect(find.text('已达成'), findsOneWidget);
      expect(find.text('COMPLETED'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(completed, isTrue);
    });

    testWidgets(
      'HabitCelebrationTrigger does not bubble tap to parent GestureDetector',
      (tester) async {
        bool parentTapped = false;
        bool buttonCheckedIn = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureDetector(
                onTap: () => parentTapped = true,
                child: HabitCelebrationTrigger(
                  onCheckIn: () async {
                    buttonCheckedIn = true;
                  },
                  child: const Text('打卡'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打卡'));
        await tester.pump();

        expect(buttonCheckedIn, isTrue);
        expect(parentTapped, isFalse);
      },
    );
  });
}
