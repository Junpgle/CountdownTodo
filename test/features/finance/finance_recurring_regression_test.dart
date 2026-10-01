@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_automation_service.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_automation_editor.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const cash = 'finance-system-payment-cash';

Future<Database> openDatabase() async {
  SharedPreferences.setMockInitialValues({});
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await DatabaseHelper.ensureFinanceSchema(db);
  FinanceStorage.databaseOverride = db;
  await FinanceStorage.ensureReady();
  await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);
  return db;
}

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready() && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('UI did not settle');
}

void configureView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('周期账单运行边界', () {
    late Database db;
    setUp(() async => db = await openDatabase());
    tearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    test('恢复已暂停的周期账单后仍保持暂停', () async {
      final rule = FinanceRecurringRule(
        uuid: 'restore-paused-recurring-rule',
        name: '暂停的订阅',
        amountMinor: 10000,
        startDate: '2026-01-01',
        isEnabled: false,
      );
      await FinanceStorage.saveRecurringRule(rule);

      await FinanceStorage.deleteRecurringRule(rule.uuid);
      expect(
        (await FinanceStorage.getRecurringRule(rule.uuid))!.isDeleted,
        true,
      );

      await FinanceStorage.restoreRecurringRule(rule.uuid);
      final restored = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      expect(restored.isDeleted, false);
      expect(restored.isEnabled, false);
      expect(
        await FinanceStorage.getRecurringRules(enabledOnly: true),
        isEmpty,
      );
    });

    for (final transport in ['remote', 'backup']) {
      Future<void> apply(FinanceRecurringRule rule) async {
        final bundle = {
          'recurring_rules': [rule.toMap()],
        };
        if (transport == 'remote') {
          await FinanceStorage.mergeRemoteBundle(bundle);
        } else {
          await FinanceStorage.importBundle(bundle);
        }
      }

      test('$transport 接收每月改每年的新进度，不被旧月度标记覆盖', () async {
        final old = FinanceRecurringRule(
          uuid: 'monthly-to-yearly',
          name: '订阅',
          amountMinor: 10000,
          startDate: '2020-01-01',
          lastGeneratedPeriod: '2026-09',
          updatedAt: DateTime(2026, 9, 2).millisecondsSinceEpoch,
        );
        await db.insert('finance_recurring_rules', old.toMap());
        final incoming = FinanceRecurringRule.fromMap(old.toMap())
          ..frequency = FinanceRecurringFrequency.yearly
          ..monthOfYear = 12
          ..lastGeneratedPeriod = '2025'
          ..updatedAt = DateTime(2026, 10, 1, 12).millisecondsSinceEpoch;
        await apply(incoming);
        final stored = (await FinanceStorage.getRecurringRule(old.uuid))!;
        expect(stored.lastGeneratedPeriod, '2025');
        expect(
          await FinanceStorage.materializeRecurringRule(
            old,
            dueAt: DateTime(2026, 10, 1, 9),
            periodKey: '2026-10',
          ),
          false,
        );
        expect(
          await FinanceAutomationService.reconcileCurrentPeriod(
            now: DateTime(2026, 10, 2),
          ),
          0,
        );
        expect(
          await FinanceAutomationService.reconcileCurrentPeriod(
            now: DateTime(2026, 12, 2),
          ),
          1,
        );
        expect(
          (await FinanceStorage.getTransactions()).single.transactionDate,
          '2026-12-01',
        );
        expect(
          (await FinanceStorage.getRecurringRule(old.uuid))!
              .lastGeneratedPeriod,
          '2026',
        );
      });

      test('$transport 同频率旧编辑快照不能回退已生成进度', () async {
        final current = FinanceRecurringRule(
          uuid: 'preserve-monthly-progress',
          name: '月费',
          amountMinor: 10000,
          startDate: '2026-01-01',
          lastGeneratedPeriod: '2026-09',
          updatedAt: DateTime(2026, 9, 2).millisecondsSinceEpoch,
        );
        await db.insert('finance_recurring_rules', current.toMap());
        final stale = FinanceRecurringRule.fromMap(current.toMap())
          ..note = '只修改备注'
          ..lastGeneratedPeriod = '2026-06'
          ..updatedAt = DateTime(2026, 10, 1).millisecondsSinceEpoch;
        await apply(stale);
        expect(
          (await FinanceStorage.getRecurringRule(current.uuid))!
              .lastGeneratedPeriod,
          '2026-09',
        );
        expect(
          await FinanceAutomationService.reconcileCurrentPeriod(
            now: DateTime(2026, 10, 2),
          ),
          1,
        );
        expect(
          (await FinanceStorage.getTransactions()).single.transactionDate,
          '2026-10-01',
        );
      });
    }

    test('编辑期间到达的远端字段更新不会被旧草稿一并覆盖', () async {
      final original = FinanceRecurringRule(
        uuid: 'recurring-three-way-edit',
        name: '每月订阅',
        amountMinor: 10000,
        startDate: '2026-01-01',
        updatedAt: 100,
      );
      await FinanceStorage.saveRecurringRule(original);
      final baseline = (await FinanceStorage.getRecurringRule(original.uuid))!;
      final localEdit = FinanceRecurringRule.fromMap(baseline.toMap())
        ..note = '本地新增备注';
      localEdit.markAsChanged();
      final remoteUpdate = FinanceRecurringRule.fromMap(baseline.toMap())
        ..name = '远端新名称'
        ..amountMinor = 20000
        ..lastGeneratedPeriod = '2026-09'
        ..version = baseline.version + 1
        ..updatedAt = localEdit.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'recurring_rules': [remoteUpdate.toMap()],
      });

      await expectLater(
        FinanceStorage.saveRecurringRule(localEdit),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getRecurringRule(original.uuid))!.name,
        '远端新名称',
      );
      await FinanceStorage.saveRecurringRule(localEdit, original: baseline);

      final saved = (await FinanceStorage.getRecurringRule(original.uuid))!;
      expect(saved.name, '远端新名称');
      expect(saved.amountMinor, 20000);
      expect(saved.note, '本地新增备注');
      expect(saved.lastGeneratedPeriod, '2026-09');
    });

    final scheduleChanges = <String, void Function(FinanceRecurringRule)>{
      '关闭自动生成': (rule) => rule.autoGenerate = false,
      '调整到期日': (rule) => rule.dayOfMonth = 20,
      '推迟开始日期': (rule) => rule.startDate = '2026-10-20',
      '提前结束日期': (rule) => rule.endDate = '2026-09-30',
    };
    for (final change in scheduleChanges.entries) {
      test('${change.key}后，已读取旧规则的调度不能写入账单', () async {
        final old = FinanceRecurringRule(
          uuid: 'stale-schedule',
          name: '月费',
          amountMinor: 10000,
          startDate: '2026-01-01',
          lastGeneratedPeriod: '2026-09',
        );
        await FinanceStorage.saveRecurringRule(old);
        final current = FinanceRecurringRule.fromMap(old.toMap());
        change.value(current);
        current.markAsChanged();
        await FinanceStorage.saveRecurringRule(current);
        expect(
          await FinanceStorage.materializeRecurringRule(
            old,
            dueAt: DateTime(2026, 10, 1, 9),
            periodKey: '2026-10',
          ),
          false,
        );
        expect(await FinanceStorage.getTransactions(), isEmpty);
        expect(
          (await FinanceStorage.getRecurringRule(old.uuid))!
              .lastGeneratedPeriod,
          '2026-09',
        );
      });
    }

    test('年度到期月份修改后拒绝旧调度，并在新月份正常生成', () async {
      final old = FinanceRecurringRule(
        uuid: 'stale-yearly-schedule',
        name: '年费',
        amountMinor: 10000,
        frequency: FinanceRecurringFrequency.yearly,
        monthOfYear: 1,
        startDate: '2020-01-01',
        lastGeneratedPeriod: '2025',
      );
      await FinanceStorage.saveRecurringRule(old);
      final current = FinanceRecurringRule.fromMap(old.toMap())
        ..monthOfYear = 12;
      current.markAsChanged();
      await FinanceStorage.saveRecurringRule(current);
      expect(
        await FinanceStorage.materializeRecurringRule(
          old,
          dueAt: DateTime(2026, 1, 1, 9),
          periodKey: '2026',
        ),
        false,
      );
      expect(
        await FinanceAutomationService.reconcileCurrentPeriod(
          now: DateTime(2026, 12, 2),
        ),
        1,
      );
      expect(
        (await FinanceStorage.getTransactions()).single.transactionDate,
        '2026-12-01',
      );
    });

    test('编辑金额和短月到期日后，仍按最新金额正常补记且保持幂等', () async {
      final old = FinanceRecurringRule(
        uuid: 'edited-month-end',
        name: '月费',
        amountMinor: 10000,
        dayOfMonth: 28,
        startDate: '2026-01-01',
        lastGeneratedPeriod: '2026-01',
      );
      await FinanceStorage.saveRecurringRule(old);
      final current = FinanceRecurringRule.fromMap(old.toMap())
        ..dayOfMonth = 31
        ..amountMinor = 20000;
      current.markAsChanged();
      await FinanceStorage.saveRecurringRule(current);
      expect(
        await FinanceStorage.materializeRecurringRule(
          old,
          dueAt: DateTime(2026, 2, 28, 9),
          periodKey: '2026-02',
        ),
        true,
      );
      expect(
        await FinanceStorage.materializeRecurringRule(
          old,
          dueAt: DateTime(2026, 2, 28, 9),
          periodKey: '2026-02',
        ),
        false,
      );
      expect(
        await FinanceAutomationService.reconcileCurrentPeriod(
          now: DateTime(2026, 4, 1),
        ),
        1,
      );
      final bills = await FinanceStorage.getTransactions();
      expect(bills.map((bill) => bill.transactionDate).toSet(), {
        '2026-02-28',
        '2026-03-31',
      });
      expect(bills.every((bill) => bill.amountMinor == 20000), true);
    });

    test('旧格式年度标记切换月度后，只补修改之后的月份', () {
      final rule = FinanceRecurringRule(
        name: '旧月费',
        amountMinor: 10000,
        startDate: '2020-01-01',
        lastGeneratedPeriod: '2026',
        updatedAt: DateTime(2026, 10, 1, 12).millisecondsSinceEpoch,
      );
      expect(rule.effectiveLastGeneratedPeriod, '2026-10');
      expect(
        FinanceAutomationService.missedDuesFor(
          rule,
          now: DateTime(2026, 11, 1, 12),
        ).map((due) => due.periodKey),
        ['2026-11'],
      );
      rule.markAsChanged();
      expect(rule.lastGeneratedPeriod, '2026-10');
      rule.dayOfMonth = 31;
      expect(
        rule.generationPeriodBefore(DateTime(2026, 2, 28, 8, 59)),
        '2026-01',
      );
      expect(rule.generationPeriodBefore(DateTime(2026, 2, 28, 9)), '2026-02');
    });

    test('旧格式月度标记切换年度后，不倒补往年且保留当年未来到期项', () {
      final rule = FinanceRecurringRule(
        name: '旧年费',
        amountMinor: 10000,
        frequency: FinanceRecurringFrequency.yearly,
        monthOfYear: 12,
        startDate: '2020-01-01',
        lastGeneratedPeriod: '2026-09',
        updatedAt: DateTime(2026, 10, 1, 12).millisecondsSinceEpoch,
      );
      expect(rule.effectiveLastGeneratedPeriod, '2025');
      expect(
        FinanceAutomationService.missedDuesFor(
          rule,
          now: DateTime(2026, 12, 2),
        ).map((due) => due.periodKey),
        ['2026'],
      );
      rule.monthOfYear = 1;
      expect(rule.effectiveLastGeneratedPeriod, '2026');
      expect(
        FinanceAutomationService.missedDuesFor(
          rule,
          now: DateTime(2026, 12, 2),
        ),
        isEmpty,
      );
    });

    test('年度跨年提前提醒仍按实际触发日期入列', () async {
      await FinanceStorage.saveRecurringRule(
        FinanceRecurringRule(
          uuid: 'yearly-advance-reminder',
          name: '跨年年费',
          amountMinor: 10000,
          frequency: FinanceRecurringFrequency.yearly,
          monthOfYear: 1,
          dayOfMonth: 2,
          startDate: '2026-01-01',
          reminderMinutes: 10080,
          autoGenerate: false,
        ),
      );
      final reminders = await FinanceAutomationService.buildRecurringReminders(
        now: DateTime(2026, 12, 25, 12),
      );
      expect(reminders, hasLength(1));
      expect(reminders.single['financePeriodKey'], '2027');
      expect(
        reminders.single['triggerAtMs'],
        DateTime(2026, 12, 26, 9).millisecondsSinceEpoch,
      );
    });

    test('已过提醒时间、关闭提醒、停用规则和无效窗口都不排入', () async {
      for (final rule in [
        FinanceRecurringRule(
          name: '已过提醒',
          amountMinor: 10000,
          dayOfMonth: 2,
          startDate: '2026-01-01',
          reminderMinutes: 10080,
        ),
        FinanceRecurringRule(
          name: '关闭提醒',
          amountMinor: 10000,
          dayOfMonth: 9,
          startDate: '2026-01-01',
          reminderMinutes: 0,
        ),
        FinanceRecurringRule(
          name: '停用规则',
          amountMinor: 10000,
          dayOfMonth: 9,
          startDate: '2026-01-01',
          reminderMinutes: 10080,
          isEnabled: false,
        ),
      ]) {
        await FinanceStorage.saveRecurringRule(rule);
      }
      final now = DateTime(2026, 10, 1, 10);
      expect(
        await FinanceAutomationService.buildRecurringReminders(now: now),
        isEmpty,
      );
      expect(
        await FinanceAutomationService.buildRecurringReminders(
          now: now,
          limit: now,
        ),
        isEmpty,
      );
    });
  });

  testWidgets('通过编辑器修改周期频率不倒补历史账单，后续周期仍按新频率生成', (tester) async {
    configureView(tester);
    final db = (await tester.runAsync(openDatabase))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    final changedAt = DateTime.now();
    final previousYear = changedAt.year - 1;
    final rule = (await tester.runAsync(() async {
      final annual = FinanceRecurringRule(
        uuid: 'annual-to-monthly',
        name: '测试订阅',
        amountMinor: 10000,
        paymentMethodUuid: cash,
        frequency: FinanceRecurringFrequency.yearly,
        monthOfYear: 1,
        dayOfMonth: 1,
        startDate: '$previousYear-01-01',
        autoGenerate: true,
        reminderMinutes: 0,
      );
      await FinanceStorage.saveRecurringRule(annual);
      await FinanceAutomationService.reconcileCurrentPeriod(
        now: DateTime(previousYear, 1, 1, 12),
      );
      return (await FinanceStorage.getRecurringRule(annual.uuid))!;
    }))!;
    expect(rule.lastGeneratedPeriod, '$previousYear');
    final categories = (await tester.runAsync(
      () => FinanceStorage.getCategories(),
    ))!;
    final methods = (await tester.runAsync(
      () => FinanceStorage.getPaymentMethods(),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => FinanceAutomationEditor.rule(
                  rule: rule,
                  categories: categories,
                  paymentMethods: methods,
                  onSave: FinanceRepository.saveRecurringRule,
                ),
              ),
              child: const Text('编辑周期'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑周期'));
    await tester.pumpAndSettle();
    final frequency = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<FinanceRecurringFrequency>,
    );
    await tester.ensureVisible(frequency);
    await tester.tap(frequency);
    await tester.pumpAndSettle();
    await tester.tap(find.text('每月').last);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('finance-automation-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await waitFor(
      tester,
      () => find.byType(FinanceAutomationEditor).evaluate().isEmpty,
    );
    await tester.runAsync(() async {
      final current = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      expect(current.lastGeneratedPeriod, matches(r'^\d{4}-\d{2}$'));
      final future = DateTime(changedAt.year, changedAt.month + 2, 1, 12);
      final dues = FinanceAutomationService.missedDuesFor(current, now: future);
      expect(dues, isNotEmpty);
      expect(dues.every((due) => due.dueAt.isAfter(changedAt)), true);
      final generated = await FinanceAutomationService.reconcileCurrentPeriod(
        now: future,
      );
      expect(generated, dues.length);
      expect((await FinanceStorage.getTransactions()).length, 1 + dues.length);
      expect(
        await FinanceAutomationService.reconcileCurrentPeriod(now: future),
        0,
      );
    });
    expect(tester.takeException(), isNull);
  });

  test('提前一周的提醒按触发时间入列，即使账单在调度窗口之外', () async {
    final db = await openDatabase();
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    final rule = FinanceRecurringRule(
      uuid: 'advance-reminder',
      name: '提前一周提醒',
      amountMinor: 10000,
      dayOfMonth: 9,
      startDate: '2026-10-01',
      autoGenerate: false,
      reminderMinutes: 10080,
    );
    await FinanceStorage.saveRecurringRule(rule);
    final now = DateTime(2026, 10, 1, 10);
    final end = now.add(const Duration(days: 7));
    final due = FinanceAutomationService.dueDateFor(rule, 2026, 10)!;
    final triggerAt = due.subtract(Duration(minutes: rule.reminderMinutes));
    expect(triggerAt.isAfter(now) && triggerAt.isBefore(end), isTrue);
    final reminders = await FinanceAutomationService.buildRecurringReminders(
      now: now,
      limit: end,
    );
    expect(reminders, hasLength(1));
    expect(reminders.single['triggerAtMs'], triggerAt.millisecondsSinceEpoch);
    expect(reminders.single['financeDueAtMs'], due.millisecondsSinceEpoch);
    expect(reminders.single['withinWindow'], true);
  });
}
