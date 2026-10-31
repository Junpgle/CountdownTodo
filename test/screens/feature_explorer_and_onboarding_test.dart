import 'package:countdown_todo/screens/help/feature_explorer_screen.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/services/onboarding_checklist_service.dart';
import 'package:countdown_todo/widgets/onboarding_checklist_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'OnboardingChecklistService auto-completes from data and persists tasks',
    () async {
      final initial = await OnboardingChecklistService.loadSnapshot(
        hasTodosOrCountdowns: true,
        hasCoursesOrSchedules: false,
        hasPlanBlocks: true,
      );

      expect(initial.completedCount, 2);
      expect(
        initial.tasks
            .firstWhere(
              (t) =>
                  t.id == OnboardingChecklistService.taskCreateTodoOrCountdown,
            )
            .isCompleted,
        isTrue,
      );
      expect(
        initial.tasks
            .firstWhere((t) => t.id == OnboardingChecklistService.taskPlanBlock)
            .isCompleted,
        isTrue,
      );

      await OnboardingChecklistService.markTaskCompleted(
        OnboardingChecklistService.taskPomodoroFocus,
      );
      final updated = await OnboardingChecklistService.loadSnapshot();
      expect(updated.completedCount, 3);

      await OnboardingChecklistService.setDismissed(true);
      expect(
        (await OnboardingChecklistService.loadSnapshot()).isDismissed,
        isTrue,
      );

      await FeatureTipService.resetAllTips();
      expect(
        (await OnboardingChecklistService.loadSnapshot()).isDismissed,
        isFalse,
      );
    },
  );

  testWidgets(
    'OnboardingChecklistCard expands, spotlights, and launches tasks',
    (tester) async {
      final launchedTasks = <String>[];
      final spotlightedTasks = <String>[];
      var explorerOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingChecklistCard(
                isLight: false,
                hasTodosOrCountdowns: false,
                hasCoursesOrSchedules: false,
                hasPlanBlocks: false,
                onLaunchTask: launchedTasks.add,
                onSpotlightTask: spotlightedTasks.add,
                onOpenFeatureExplorer: () => explorerOpened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('功能探索'), findsOneWidget);
      expect(find.text('0/6'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('onboarding-open-feature-explorer-btn'),
        ),
      );
      await tester.pump();
      expect(explorerOpened, isTrue);

      // Expand full list
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-toggle-expand-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('记录第一条待办或倒计时'), findsOneWidget);
      expect(find.text('逛逛「功能百宝箱」解锁隐藏技能'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'onboarding-spotlight-create_todo_or_countdown',
          ),
        ),
      );
      await tester.pump();
      expect(spotlightedTasks, ['create_todo_or_countdown']);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('onboarding-launch-create_todo_or_countdown'),
        ),
      );
      await tester.pump();
      expect(launchedTasks, ['create_todo_or_countdown']);
    },
  );

  testWidgets(
    'FeatureExplorerScreen prioritizes unread new features first under All and filters by search',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Mark 'fixed_schedule_related_todo' as already seen so we can verify
      // unread new items appear BEFORE seen new items and regular items.
      await FeatureTipService.markFeatureBadgeSeen(
        'fixed_schedule_related_todo',
      );

      await tester.pumpWidget(
        const MaterialApp(home: FeatureExplorerScreen(username: 'tester')),
      );
      await tester.pumpAndSettle();

      expect(find.text('功能探索百宝箱'), findsOneWidget);
      expect(find.text('功能探索进度'), findsOneWidget);
      expect(find.text('已体验 1 项'), findsOneWidget);
      expect(find.textContaining('还差 '), findsWidgets);
      expect(find.text('近期新增 · 未读'), findsOneWidget);

      // Unread new feature ('todo_plan_center' and 'finance_and_ai_bill') should
      // be rendered above the already-seen 'fixed_schedule_related_todo'.
      final unreadPlanY = tester.getTopLeft(find.text('规划中心与时间块排期')).dy;
      final unreadFinanceY = tester.getTopLeft(find.text('个人记账与 AI 账单识别')).dy;
      expect(unreadPlanY, lessThan(unreadFinanceY));

      // Filter by search query
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '调休',
      );
      await tester.pumpAndSettle();

      expect(find.text('法定节假日放假与调休'), findsOneWidget);
      expect(find.text('规划中心与时间块排期'), findsNothing);

      // Tap card to open step-by-step detail sheet
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'feature-explorer-card-course_holiday_adjustment',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('如何操作'), findsOneWidget);
      expect(find.text('配置放假与调休'), findsOneWidget);

      // Merely opening the detail sheet to read does NOT mark the feature as explored
      expect(
        await FeatureTipService.isFeatureBadgeUnread(
          'course_holiday_adjustment',
        ),
        isTrue,
      );
      expect(find.text('已体验 1 项'), findsOneWidget);

      // Tapping the action button to actually open the target screen marks it as explored
      await tester.tap(find.text('配置放假与调休'));
      await tester.pumpAndSettle();
      expect(
        await FeatureTipService.isFeatureBadgeUnread(
          'course_holiday_adjustment',
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'FeatureExplorerScreen displays and searches v7.22 newly updated features',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: FeatureExplorerScreen(username: 'tester')),
      );
      await tester.pumpAndSettle();

      // Search for '日记回收站'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '回收站',
      );
      await tester.pumpAndSettle();
      expect(find.text('私密日记回收站与完整附件保留'), findsOneWidget);

      // Search for '纯黑'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '纯黑',
      );
      await tester.pumpAndSettle();
      expect(find.text('神技 9：纯黑 OLED 极致省电与 Liquid Glass 自定义'), findsOneWidget);

      // Search for '设置搜索'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '设置搜索',
      );
      await tester.pumpAndSettle();
      expect(find.text('神技 10：设置中心实时搜功能，一秒直达深层配置'), findsOneWidget);
    },
  );
}
