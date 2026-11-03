@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_home_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_calendar_panel.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  bool settleAfterReady = true,
}) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) {
      if (settleAfterReady) await tester.pumpAndSettle();
      return;
    }
  }
  fail('页面未在限定时间内完成数据库操作');
}

Future<Database> _seed(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'tip_shown_coach_finance_intro': true,
  });
  final db = (await tester.runAsync(() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    await db.insert(
      'finance_categories',
      FinanceCategory(uuid: 'test-food', name: '日常餐饮', icon: '🍜').toMap(),
    );
    final expenseAt = DateTime(2026, 10, 15, 12);
    await db.insert(
      'finance_transactions',
      FinanceTransaction(
        uuid: 'test-expense-1',
        amountMinor: 3500,
        categoryUuid: 'test-food',
        transactionDate: dateKey(expenseAt),
        occurredAt: expenseAt.millisecondsSinceEpoch,
        createdAt: expenseAt.millisecondsSinceEpoch,
        merchant: '午餐',
      ).toMap(),
    );
    return db;
  }))!;
  addTearDown(() async {
    await db.close();
    FinanceStorage.databaseOverride = null;
  });
  return db;
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: screen,
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(
    finder.evaluate().first,
    alignment: 0.2,
    duration: Duration.zero,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('记账切换月份、周视图、日视图及周期时不出现整页加载白屏', (tester) async {
    await _seed(tester);
    final clockNow = DateTime(2026, 10, 23, 12);
    await _pump(
      tester,
      FinanceHomeScreen(username: 'default', clock: () => clockNow),
    );

    // 初始加载完成后，整个页面保持挂载，不应出现全屏加载圈
    expect(find.byType(FinanceOverviewPanel), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 1. 切换月份（前一月）
    await _tap(tester, _key('finance-overview-period-previous'));
    // 切换瞬间和其后：无白屏加载圈，页面依然完整挂载
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FinanceOverviewPanel), findsOneWidget);
    await _waitFor(tester, () => find.text('2026年9月').evaluate().isNotEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 2. 切换到周视图
    await _tap(tester, _key('finance-overview-view-selector-week'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FinanceOverviewPanel), findsOneWidget);

    // 3. 切换周周期（前一周，跨入8月）
    await _tap(tester, _key('finance-overview-period-previous'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FinanceOverviewPanel), findsOneWidget);
    await _waitFor(
      tester,
      () => find.textContaining('8月').evaluate().isNotEmpty,
    );

    // 4. 切换到日视图
    await _tap(tester, _key('finance-overview-view-selector-day'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FinanceOverviewPanel), findsOneWidget);
    await _waitFor(
      tester,
      () => find.textContaining('时段净支出').evaluate().isNotEmpty,
    );

    // 5. 切换日周期（前一天至8月24日）
    await _tap(tester, _key('finance-overview-period-previous'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FinanceOverviewPanel), findsOneWidget);
    await _waitFor(
      tester,
      () => find.textContaining('8月24日').evaluate().isNotEmpty,
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('记账板块在宽屏桌面窗口下自适应双列布局且无溢出', (tester) async {
    await _seed(tester);
    final clockNow = DateTime(2026, 10, 23, 12);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: FinanceHomeScreen(username: 'default', clock: () => clockNow),
      ),
    );
    await _waitFor(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );

    // 1. 验证宽屏下主内容区域被限制在最大 1040 宽度以内并居中
    final overviewFinder = find.byType(FinanceOverviewPanel);
    expect(overviewFinder, findsOneWidget);
    final overviewSize = tester.getSize(overviewFinder);
    expect(overviewSize.width, lessThanOrEqualTo(1040.0));

    // 2. 验证模式选择器（报表/日历）被限制在 maxWidth: 380 以内居中
    final reportModeFinder = _key('finance-overview-mode-selector-report');
    final calendarModeFinder = _key('finance-overview-mode-selector-calendar');
    expect(reportModeFinder, findsOneWidget);
    expect(calendarModeFinder, findsOneWidget);
    final reportRect = tester.getRect(reportModeFinder);
    final calendarRect = tester.getRect(calendarModeFinder);
    final totalModeSelectorWidth = calendarRect.right - reportRect.left;
    expect(totalModeSelectorWidth, lessThanOrEqualTo(380.0));

    // 3. 验证时间视图与统计周期在宽屏下横向并排（同一 Row）
    expect(find.text('时间视图'), findsOneWidget);
    expect(find.text('统计周期'), findsOneWidget);
    final viewSelectorY = tester.getTopLeft(find.text('时间视图')).dy;
    final periodNavigatorY = tester.getTopLeft(find.text('统计周期')).dy;
    expect((viewSelectorY - periodNavigatorY).abs(), lessThanOrEqualTo(2.0));

    // 4. 验证分类卡片在宽屏下甜甜圈图与分类列表横向排列
    final categoryNameFinder = find.text('日常餐饮');
    expect(categoryNameFinder, findsOneWidget);
    // 甜甜圈图中心文本
    expect(find.text('总净支出'), findsOneWidget);
    final donutX = tester.getCenter(find.text('总净支出')).dx;
    final categoryX = tester.getCenter(categoryNameFinder).dx;
    // 分类在甜甜圈图右侧
    expect(categoryX, greaterThan(donutX));

    // 5. 切换到日历模式，验证日历面板在宽屏下同样受控且无溢出
    await _tap(tester, calendarModeFinder);
    await tester.pumpAndSettle();
    expect(find.byType(FinanceCalendarPanel), findsOneWidget);
    final calendarPanelSize = tester.getSize(find.byType(FinanceCalendarPanel));
    expect(calendarPanelSize.width, lessThanOrEqualTo(1040.0));

    // 6. 切换到底栏「账单」页签，验证搜索框与统计周期在宽屏下横向并排
    await tester.tap(
      find.byIcon(Icons.receipt_long_outlined).last,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(FinanceLedgerPanel), findsOneWidget);
    final searchFieldFinder = find.byType(TextField);
    final ledgerPeriodFinder = _key('finance-ledger-period-picker');
    expect(searchFieldFinder, findsOneWidget);
    expect(ledgerPeriodFinder, findsOneWidget);

    final searchRect = tester.getRect(searchFieldFinder);
    final periodRect = tester.getRect(ledgerPeriodFinder);
    // 搜索框在左侧，周期选择器在右侧
    expect(searchRect.center.dx, lessThan(periodRect.center.dx));
    // 垂直中心对齐在同一行内（容差 <= 4px）
    expect(
      (searchRect.center.dy - periodRect.center.dy).abs(),
      lessThanOrEqualTo(4.0),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('记账概览展示预算看板、快捷模板、消费节奏洞察、账户分布与待发生周期收支', (tester) async {
    final db = await _seed(tester);
    final clockNow = DateTime(2026, 10, 23, 12);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await (tester.runAsync(() async {
      // 1. 预算
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'test-budget-1',
          monthKey: '2026-10',
          amountMinor: 200000,
        ).toMap(),
      );
      // 2. 支付账户
      await db.insert(
        'finance_payment_methods',
        FinancePaymentMethod(
          uuid: 'test-pm-wechat',
          name: '微信支付',
          icon: '💬',
        ).toMap(),
      );
      // 3. 更新现有消费关联此账户
      await db.update(
        'finance_transactions',
        {'payment_method_uuid': 'test-pm-wechat'},
        where: 'uuid = ?',
        whereArgs: ['test-expense-1'],
      );
      // 4. 周期收支 (2天后：10月25日)
      await db.insert(
        'finance_recurring_rules',
        FinanceRecurringRule(
          uuid: 'test-rule-1',
          name: '音乐会员',
          amountMinor: 1500,
          dayOfMonth: 25,
          startDate: '2026-01-01',
        ).toMap(),
      );
      // 5. 常用模板
      await db.insert(
        'finance_entry_templates',
        FinanceEntryTemplate(
          uuid: 'test-tpl-1',
          name: '通勤打车',
          amountMinor: 2500,
          useCount: 15,
        ).toMap(),
      );
    }));

    await _pump(
      tester,
      FinanceHomeScreen(username: 'default', clock: () => clockNow),
    );

    // 1. 快捷动作栏：记一笔、预算管理、自定义模板
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('预算管理'), findsOneWidget);
    expect(find.textContaining('通勤打车'), findsOneWidget);

    // 2. 预算看板
    expect(find.text('10月总预算'), findsOneWidget);
    expect(find.text('总额 ¥2,000.00'), findsOneWidget);
    expect(find.text('剩余 '), findsOneWidget);

    // 3. 消费节奏与洞察
    final insightFinder = find.text('本月消费节奏与洞察');
    await tester.scrollUntilVisible(
      insightFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(insightFinder, findsOneWidget);
    expect(find.text('笔均支出'), findsOneWidget);
    expect(find.text('最高单笔支出'), findsOneWidget);
    expect(find.textContaining('日常餐饮 · 午餐'), findsOneWidget);

    // 4. 账户支出分布
    final accountFinder = find.text('账户支出分布');
    await tester.scrollUntilVisible(
      accountFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(accountFinder, findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);

    // 5. 未来7天待发生周期收支
    final recurringFinder = find.textContaining('未来7天待发生收支');
    await tester.scrollUntilVisible(
      recurringFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(recurringFinder, findsOneWidget);
    expect(find.text('音乐会员'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
