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
}
