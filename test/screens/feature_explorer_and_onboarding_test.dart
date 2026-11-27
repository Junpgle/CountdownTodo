import 'package:countdown_todo/features/finance/screens/finance_bill_import_screen.dart';
import 'package:countdown_todo/features/habits/screens/habit_center_screen.dart';
import 'package:countdown_todo/screens/help/feature_explorer_screen.dart';
import 'package:countdown_todo/screens/settings/notification_settings_page.dart';
import 'package:countdown_todo/screens/settings/pages/account_devices_page.dart';
import 'package:countdown_todo/screens/settings/pages/ai_assistant_settings_page.dart';
import 'package:countdown_todo/screens/settings/pages/auto_backup_page.dart';
import 'package:countdown_todo/screens/settings/pages/platform_specific_settings_page.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/services/onboarding_checklist_service.dart';
import 'package:countdown_todo/utils/app_platform.dart';
import 'package:countdown_todo/widgets/onboarding_checklist_card.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  testWidgets(
    'FeatureExplorerScreen displays and searches v7.23 newly updated features',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: FeatureExplorerScreen(username: 'tester')),
      );
      await tester.pumpAndSettle();

      // Search for '环形图'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '环形图',
      );
      await tester.pumpAndSettle();
      expect(find.text('记账预算看板与交互式支出环形图'), findsOneWidget);

      // Search for '专属日历'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '专属日历',
      );
      await tester.pumpAndSettle();
      expect(find.text('习惯中心与专属打卡日历'), findsOneWidget);

      // Search for '流畅度'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '流畅度',
      );
      await tester.pumpAndSettle();
      expect(find.text('Liquid Glass 液态玻璃与实时流畅度监控'), findsOneWidget);
    },
  );

  testWidgets(
    'FeatureExplorerScreen displays and searches v7.24 newly updated features',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: FeatureExplorerScreen(username: 'tester')),
      );
      await tester.pumpAndSettle();

      // Search for '微信账单'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '微信账单',
      );
      await tester.pumpAndSettle();
      expect(find.text('多平台账单批量导入'), findsOneWidget);

      // Search for '账户互转'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '账户互转',
      );
      await tester.pumpAndSettle();
      expect(find.text('账户互转与账单批量管理'), findsOneWidget);

      // Search for '每日AI'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '每日AI',
      );
      await tester.pumpAndSettle();
      expect(find.text('每日 AI 智能建议、记忆偏好与对话工具预算'), findsOneWidget);

      // Search for '自动备份'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '自动备份',
      );
      await tester.pumpAndSettle();
      expect(find.text('定期自动备份与本地快照恢复'), findsOneWidget);

      // Search for 'ECDH'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        'ECDH',
      );
      await tester.pumpAndSettle();
      expect(find.text('局域网面对面互传同步'), findsOneWidget);
    },
  );

  testWidgets(
    'FeatureExplorerScreen displays and searches v7.25 newly updated features',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: FeatureExplorerScreen(username: 'tester')),
      );
      await tester.pumpAndSettle();

      // Search for '语义识别'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '语义识别',
      );
      await tester.pumpAndSettle();
      expect(find.text('倒数日语义识别、到达提醒与实时活动'), findsOneWidget);

      // Search for '全站日均'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '全站日均',
      );
      await tester.pumpAndSettle();
      expect(find.text('番茄钟与跨端实时专注'), findsOneWidget);
      expect(find.text('专注统计看板与多维视图下钻'), findsOneWidget);

      // Search for '戒掉饮料'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '戒掉饮料',
      );
      await tester.pumpAndSettle();
      expect(find.text('习惯日历图标点亮与戒掉饮料饮品记录'), findsOneWidget);

      // Search for '踢出设备'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '踢出设备',
      );
      await tester.pumpAndSettle();
      expect(find.text('在线登录设备管理与安全踢出'), findsOneWidget);

      if (!kIsWeb && (AppPlatform.isMacOS || AppPlatform.isWindows)) {
        // Search for 'Impeller'
        await tester.enterText(
          find.byKey(const ValueKey<String>('feature-explorer-search-field')),
          'Impeller',
        );
        await tester.pumpAndSettle();
        expect(find.text('桌面端 Skia / Impeller 渲染引擎切换'), findsOneWidget);
      }

      // Search for '云闪付'
      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '云闪付',
      );
      await tester.pumpAndSettle();
      expect(find.text('多平台账单批量导入'), findsOneWidget);
    },
  );

  test(
    'FeatureTipService records v7.24-v7.25 newly mapped pages as explored',
    () async {
      await FeatureTipService.recordWidgetOpened(const AccountDevicesPage());
      await FeatureTipService.recordWidgetOpened(
        const FinanceBillImportScreen(),
      );
      await FeatureTipService.recordWidgetOpened(const AutoBackupPage());
      await FeatureTipService.recordWidgetOpened(
        const AiAssistantSettingsPage(),
      );
      await FeatureTipService.recordWidgetOpened(
        const NotificationSettingsPage(),
      );
      await FeatureTipService.recordWidgetOpened(
        const HabitCenterScreen(username: 'tester'),
      );
      await FeatureTipService.recordWidgetOpened(
        const PlatformSpecificSettingsPage(),
      );

      final seen = await FeatureTipService.getSeenFeatureBadges();
      expect(
        seen,
        containsAll([
          'account_online_devices',
          'finance_bill_import',
          'auto_backup_snapshots',
          'daily_ai_suggestion_and_memory',
          'countdown_semantic_and_live_activity',
          'habit_calendar_light_up_and_drinks',
          'desktop_renderer_switch',
        ]),
      );
    },
  );

  testWidgets(
    'FeatureExplorerScreen guards online device management when offline or logged out',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: FeatureExplorerScreen(username: 'tester')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('feature-explorer-search-field')),
        '踢出设备',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'feature-explorer-card-account_online_devices',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('管理登录设备'));
      await tester.pumpAndSettle();

      expect(find.text('当前为离线模式，请先登录账号'), findsOneWidget);
      expect(find.byType(AccountDevicesPage), findsNothing);
      expect(
        await FeatureTipService.getSeenFeatureBadges(),
        isNot(contains('account_online_devices')),
      );
    },
  );
}
