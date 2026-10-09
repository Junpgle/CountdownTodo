@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/screens/finance_entry_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_home_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_settings_screen.dart';
import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/widgets/finance_intro_guide.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/feature_tip_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _username = 'finance-guide-test';

Future<void> _seed(WidgetTester tester, {bool seen = false}) async {
  SharedPreferences.setMockInitialValues({
    'current_login_user': _username,
    'tip_shown_${FinanceIntroGuide.tipId}': seen,
  });
  final db = (await tester.runAsync(() async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await DatabaseHelper.ensureFinanceSchema(database);
    await DatabaseHelper.ensureAiUsageSchema(database);
    FinanceStorage.databaseOverride = database;
    AiUsageCostService.databaseOverride = database;
    await FinanceStorage.ensureReady();
    return database;
  }))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    FinanceStorage.databaseOverride = null;
    AiUsageCostService.databaseOverride = null;
    await tester.runAsync(db.close);
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('未显示目标控件: $finder');
}

Future<void> _pumpHome(
  WidgetTester tester, {
  bool quickEntry = false,
  bool compact = false,
}) async {
  tester.view.physicalSize = compact
      ? const Size(320, 740)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: FinanceHomeScreen(username: _username, openQuickEntry: quickEntry),
    ),
  );
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();

  testWidgets(
    'first finance visit explains custom categories and optional cloud sync',
    (tester) async {
      await _seed(tester);
      await _pumpHome(tester);
      await _waitFor(tester, find.text('从记一笔开始'));
      expect(find.text('1 / 5'), findsOneWidget);
      expect(
        await AppSettingsStorage.isFinanceCloudSyncEnabled(_username),
        false,
      );
      await _next(tester);
      expect(find.text('分类可以自己定'), findsOneWidget);
      expect(find.textContaining('记账设置 → 分类目录'), findsOneWidget);
      expect(find.textContaining('二级小类'), findsOneWidget);
      await _next(tester);
      expect(find.text('管理自己的付款方式'), findsOneWidget);
      await _next(tester);
      expect(find.text('预算与周期账单'), findsOneWidget);
      await _next(tester);
      expect(find.text('需要时再开启云同步'), findsOneWidget);
      expect(find.textContaining('记账设置 → 其他设置'), findsOneWidget);
      expect(find.textContaining('默认仅保存在本机'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(
        await FeatureTipService.hasTipBeenShown(FinanceIntroGuide.tipId),
        true,
      );
      expect(
        await AppSettingsStorage.isFinanceCloudSyncEnabled(_username),
        false,
      );
      expect(tester.takeException(), null);
    },
  );

  testWidgets('skipping persists and more menu can replay the guide', (
    tester,
  ) async {
    await _seed(tester);
    await _pumpHome(tester);
    await _waitFor(tester, find.text('从记一笔开始'));
    await tester.tap(find.text('跳过教程'));
    await tester.pumpAndSettle();
    expect(
      await FeatureTipService.hasTipBeenShown(FinanceIntroGuide.tipId),
      true,
    );
    await tester.tap(find.text('账单').hitTestable().last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记账新手指引'));
    await tester.pumpAndSettle();
    expect(find.text('从记一笔开始'), findsOneWidget);
    await tester.tap(find.text('跳过教程'));
    await tester.pumpAndSettle();
    expect(
      await AppSettingsStorage.isFinanceCloudSyncEnabled(_username),
      false,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('seen guide does not reopen on a new finance screen', (
    tester,
  ) async {
    await _seed(tester, seen: true);
    await _pumpHome(tester);
    await _waitFor(tester, find.text('净支出'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('从记一笔开始'), findsNothing);
    expect(find.text('跳过教程'), findsNothing);
  });

  testWidgets('category ledger does not show an unavailable guide action', (
    tester,
  ) async {
    await _seed(tester, seen: true);
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await tester.runAsync(
      () => FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'guide-category-ledger',
          amountMinor: 1500,
          categoryUuid: 'finance-system-category-food',
          transactionDate: date,
          merchant: '测试分类账单',
        ),
      ),
    );
    await _pumpHome(tester);
    await _waitFor(tester, find.text('净支出'));
    final category = find.byKey(
      const ValueKey('finance-overview-category-finance-system-category-food'),
    );
    await tester.scrollUntilVisible(
      category,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(category);
    await tester.pumpAndSettle();
    final categoryDetail = find.byKey(
      const ValueKey('finance-category-detail-finance-system-category-food'),
    );
    expect(categoryDetail, findsOneWidget);
    await tester.tap(categoryDetail);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回支出分类'), findsOneWidget);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('记账新手指引'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick entry takes priority and guide waits until it closes', (
    tester,
  ) async {
    await _seed(tester);
    await _pumpHome(tester, quickEntry: true);
    await _waitFor(tester, find.byType(FinanceEntryScreen));
    expect(find.text('从记一笔开始'), findsNothing);
    Navigator.of(tester.element(find.byType(FinanceEntryScreen))).pop();
    await _waitFor(tester, find.text('从记一笔开始'));
    await tester.tap(find.text('跳过教程'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });

  testWidgets('small screen guide opens settings only after explicit action', (
    tester,
  ) async {
    await _seed(tester);
    await _pumpHome(tester, compact: true);
    await _waitFor(tester, find.text('从记一笔开始'));
    for (var i = 0; i < 4; i++) {
      expect(tester.takeException(), null);
      await _next(tester);
    }
    expect(find.byType(FinanceSettingsScreen), findsNothing);
    await tester.tap(find.text('去设置'));
    await _waitFor(tester, find.byType(FinanceSettingsScreen));
    expect(find.text('需要时再开启云同步'), findsNothing);
    expect(
      await FeatureTipService.hasTipBeenShown(FinanceIntroGuide.tipId),
      true,
    );
    expect(
      await AppSettingsStorage.isFinanceCloudSyncEnabled(_username),
      false,
    );
    expect(tester.takeException(), null);
  });

  testWidgets(
    'system back dismisses guide without leaving finance or enabling sync',
    (tester) async {
      await _seed(tester);
      await _pumpHome(tester);
      await _waitFor(tester, find.text('从记一笔开始'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('从记一笔开始'), findsNothing);
      expect(find.byType(FinanceHomeScreen), findsOneWidget);
      expect(
        await FeatureTipService.hasTipBeenShown(FinanceIntroGuide.tipId),
        true,
      );
      expect(
        await AppSettingsStorage.isFinanceCloudSyncEnabled(_username),
        false,
      );
      expect(tester.takeException(), null);
    },
  );
}
