@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_automation_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_automation_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('记账自动化页面未在限定时间内刷新');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('同步更新周期账单后刷新已打开的自动化页面', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = (await tester.runAsync(() async {
      final opened = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await DatabaseHelper.ensureFinanceSchema(opened);
      FinanceStorage.databaseOverride = opened;
      await FinanceStorage.ensureReady();
      return opened;
    }))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final localRule = FinanceRecurringRule(
      uuid: 'remote-refresh-rule',
      name: '本机房租规则',
      amountMinor: 250000,
      dayOfMonth: 15,
      startDate: '2026-01-01',
    );
    await tester.runAsync(() => FinanceStorage.saveRecurringRule(localRule));
    await tester.pumpWidget(
      const MaterialApp(home: FinanceAutomationScreen()),
    );
    await _waitFor(tester, () => find.text('本机房租规则').evaluate().isNotEmpty);

    final remoteRule = FinanceRecurringRule.fromMap(localRule.toMap())
      ..name = '另一设备更新的房租规则'
      ..version = localRule.version + 1
      ..updatedAt = localRule.updatedAt + 10000;
    await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'recurring_rules': [remoteRule.toMap()],
      }),
    );

    await _waitFor(
      tester,
      () => find.text('另一设备更新的房租规则').evaluate().isNotEmpty,
    );
    expect(find.text('本机房租规则'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('停留在其他页面时周期账单到期仍会自动生成', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = (await tester.runAsync(() async {
      final opened = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await DatabaseHelper.ensureFinanceSchema(opened);
      FinanceStorage.databaseOverride = opened;
      await FinanceStorage.ensureReady();
      await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);
      await FinanceStorage.saveRecurringRule(
        FinanceRecurringRule(
          uuid: 'offscreen-auto-rule',
          name: '待办页房租',
          amountMinor: 250000,
          dayOfMonth: 15,
          startDate: '2026-01-01',
        ),
      );
      return opened;
    }))!;
    addTearDown(() async {
      FinanceAutomationService.cancelScheduledAutoGeneration();
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    var clockNow = DateTime(2026, 9, 15, 8, 59);
    final rules = (await tester.runAsync(
      () => FinanceStorage.getRecurringRules(enabledOnly: true),
    ))!;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('待办列表'))),
    );
    FinanceAutomationService.scheduleAutoGenerationForRules(
      rules,
      now: clockNow,
      clock: () => clockNow,
    );

    clockNow = DateTime(2026, 9, 15, 9, 1);
    await tester.pump(const Duration(minutes: 2));
    var rows = <Map<String, Object?>>[];
    for (var attempt = 0; attempt < 40 && rows.isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      rows = (await tester.runAsync(
        () => db.query(
          'finance_transactions',
          where: 'source = ? AND transaction_date = ?',
          whereArgs: [FinanceEntrySource.automation.name, '2026-09-15'],
        ),
      ))!;
    }

    expect(rows, hasLength(1));
    expect(rows.single['merchant'], '待办页房租');
    await tester.pump(const Duration(milliseconds: 500));
    FinanceAutomationService.cancelScheduledAutoGeneration();
    expect(tester.takeException(), isNull);
  });
}
