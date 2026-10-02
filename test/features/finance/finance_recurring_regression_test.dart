@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_automation_service.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_automation_editor.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/focus_do_not_disturb_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

    test('重新启用暂停的自动记账规则不会补记暂停期间', () async {
      final now = DateTime.now();
      final lastPeriod = financeMonthKey(DateTime(now.year, now.month - 3));
      final rule = FinanceRecurringRule(
        uuid: 'resume-paused-auto-rule',
        name: '暂停期间的订阅',
        amountMinor: 10000,
        dayOfMonth: 1,
        startDate: '$lastPeriod-01',
        lastGeneratedPeriod: lastPeriod,
      );
      await FinanceStorage.saveRecurringRule(rule);

      await FinanceStorage.setRecurringRuleEnabled(rule.uuid, false);
      await FinanceStorage.setRecurringRuleEnabled(rule.uuid, true);

      expect(
        await FinanceAutomationService.reconcileCurrentPeriod(now: now),
        0,
      );
      expect(await FinanceStorage.getTransactions(), isEmpty);
    });

    test('手动记账模式切回自动时不会补记手动期间', () async {
      final now = DateTime.now();
      final lastPeriod = financeMonthKey(DateTime(now.year, now.month - 3));
      final rule = FinanceRecurringRule(
        uuid: 'resume-auto-generation-rule',
        name: '手动期间的订阅',
        amountMinor: 10000,
        dayOfMonth: 1,
        startDate: '$lastPeriod-01',
        lastGeneratedPeriod: lastPeriod,
        autoGenerate: false,
      );
      await FinanceStorage.saveRecurringRule(rule);
      final original = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      final updated = FinanceRecurringRule.fromMap(original.toMap())
        ..autoGenerate = true
        ..markAsChanged();
      await FinanceStorage.saveRecurringRule(updated, original: original);

      expect(
        await FinanceAutomationService.reconcileCurrentPeriod(now: now),
        0,
      );
      expect(await FinanceStorage.getTransactions(), isEmpty);
    });

    test('哈希冲突的周期账单仍各自保留系统提醒', () async {
      for (final uuid in ['rule-0', 'rule-242']) {
        await FinanceStorage.saveRecurringRule(
          FinanceRecurringRule(
            uuid: uuid,
            name: uuid,
            amountMinor: 1000,
            dayOfMonth: 2,
            startDate: '2026-01-01',
            reminderMinutes: 60,
            autoGenerate: false,
          ),
        );
      }

      final reminders = await FinanceAutomationService.buildRecurringReminders(
        now: DateTime(2026, 10, 1, 7),
        limit: DateTime(2026, 10, 3),
      );

      expect(reminders, hasLength(2));
      expect(
        reminders.map((reminder) => reminder['notifId']).toSet(),
        hasLength(2),
      );
    });

    test('周期账单提醒保留大额金额的分精度', () async {
      await FinanceStorage.saveRecurringRule(
        FinanceRecurringRule(
          uuid: 'large-amount-reminder',
          name: '大额周期账单',
          amountMinor: maxFinanceAmountMinor - 1,
          dayOfMonth: 2,
          startDate: '2026-01-01',
          reminderMinutes: 60,
          autoGenerate: false,
        ),
      );

      final reminders = await FinanceAutomationService.buildRecurringReminders(
        now: DateTime(2026, 10, 1, 7),
        limit: DateTime(2026, 10, 3),
      );

      expect(reminders, hasLength(1));
      expect(
        reminders.single['text'],
        '2026-10-02 · ¥90,071,992,547,409.90 · 请确认是否记账',
      );
    });

    test('跨夏令时的一天或一周提前提醒保持设定的本地时刻', () async {
      for (final reminder in [
        (uuid: 'dst-one-day-reminder', minutes: 1440),
        (uuid: 'dst-one-week-reminder', minutes: 10080),
      ]) {
        await FinanceStorage.saveRecurringRule(
          FinanceRecurringRule(
            uuid: reminder.uuid,
            name: reminder.uuid,
            amountMinor: 10000,
            dayOfMonth: 1,
            startDate: '2026-01-01',
            reminderMinutes: reminder.minutes,
            autoGenerate: false,
          ),
        );
      }

      final reminders = await FinanceAutomationService.buildRecurringReminders(
        now: DateTime(2026, 10, 24, 9),
        limit: DateTime(2026, 11, 2),
      );
      final triggerTimes = {
        for (final reminder in reminders)
          reminder['financeRuleUuid']
              as String: DateTime.fromMillisecondsSinceEpoch(
            reminder['triggerAtMs'] as int,
          ),
      };

      expect(triggerTimes['dst-one-day-reminder'], DateTime(2026, 10, 31, 9));
      expect(triggerTimes['dst-one-week-reminder'], DateTime(2026, 10, 25, 9));
    });

    test('发现已有周期账单后回填进度仍触发刷新和同步', () async {
      final rule = FinanceRecurringRule(
        uuid: 'repair-recurring-generation-marker',
        name: '月费',
        amountMinor: 10000,
        startDate: '2026-01-01',
      );
      await FinanceStorage.saveRecurringRule(rule);
      const periodKey = '2026-09';
      final dueAt = DateTime(2026, 9, 1, 9);
      expect(
        await FinanceStorage.materializeRecurringRule(
          rule,
          dueAt: dueAt,
          periodKey: periodKey,
        ),
        true,
      );
      await db.update(
        'finance_recurring_rules',
        {'last_generated_period': '2026-08', 'pending_sync': 0},
        where: 'uuid = ?',
        whereArgs: [rule.uuid],
      );
      final staleRule = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      final revisionBefore = FinanceStorage.revision.value;

      expect(
        await FinanceStorage.materializeRecurringRule(
          staleRule,
          dueAt: dueAt,
          periodKey: periodKey,
        ),
        false,
      );

      final repaired = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      expect(repaired.lastGeneratedPeriod, periodKey);
      expect(repaired.pendingSync, true);
      expect(FinanceStorage.revision.value, greaterThan(revisionBefore));
    });

    test('其他设备删除周期账单后拒绝保存旧页面中的编辑', () async {
      final rule = FinanceRecurringRule(
        uuid: 'stale-edit-deleted-recurring-rule',
        name: '原名称',
        amountMinor: 10000,
        startDate: '2026-01-01',
      );
      await FinanceStorage.saveRecurringRule(rule);
      final staleOriginal = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      final staleEdit = FinanceRecurringRule.fromMap(staleOriginal.toMap())
        ..name = '旧页面中的新名称'
        ..markAsChanged();
      final remoteDelete = FinanceRecurringRule.fromMap(staleOriginal.toMap())
        ..isDeleted = true
        ..version = staleOriginal.version + 1
        ..updatedAt = staleEdit.updatedAt + 10000;
      await FinanceStorage.mergeRemoteBundle({
        'recurring_rules': [remoteDelete.toMap()],
      });

      await expectLater(
        FinanceStorage.saveRecurringRule(staleEdit, original: staleOriginal),
        throwsA(isA<StateError>()),
      );
      final stored = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      expect(stored.name, '原名称');
      expect(stored.isDeleted, true);
    });

    test('删除期间合并到同步更新并恢复后仍保留原启用状态', () async {
      final rule = FinanceRecurringRule(
        uuid: 'restore-enabled-recurring-after-sync',
        name: '启用中的订阅',
        amountMinor: 10000,
        startDate: '2026-01-01',
      );
      await FinanceStorage.saveRecurringRule(rule);
      final baseline = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      final localDelete = FinanceRecurringRule.fromMap(baseline.toMap())
        ..isDeleted = true;
      localDelete.markAsChanged();
      final remoteUpdate = FinanceRecurringRule.fromMap(baseline.toMap())
        ..note = '删除期间同步的备注'
        ..version = baseline.version + 1
        ..updatedAt = localDelete.updatedAt + 10000;
      await FinanceStorage.mergeRemoteBundle({
        'recurring_rules': [remoteUpdate.toMap()],
      });

      await FinanceStorage.saveRecurringRule(localDelete, original: baseline);
      final deleted = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      expect(deleted.isDeleted, true);
      expect(deleted.isEnabled, true);
      expect(deleted.note, '删除期间同步的备注');

      await FinanceStorage.restoreRecurringRule(rule.uuid);
      final restored = (await FinanceStorage.getRecurringRule(rule.uuid))!;
      expect(restored.isDeleted, false);
      expect(restored.isEnabled, true);
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
          current.autoGenerate
              ? '2026-09'
              : current.generationPeriodBefore(DateTime.now()),
        );
      });
    }

    test('把每月到期日改到本月已过日期不会补记倒签账单', () async {
      final now = DateTime.now();
      final currentPeriod = financeMonthKey(now);
      final previousPeriod = financeMonthKey(DateTime(now.year, now.month - 1));
      final original = FinanceRecurringRule(
        uuid: 'move-recurring-day-into-past',
        name: '调整到期日的月费',
        amountMinor: 10000,
        dayOfMonth: 25,
        startDate: dateKey(DateTime(now.year, now.month, 1)),
        lastGeneratedPeriod: previousPeriod,
      );
      await FinanceStorage.saveRecurringRule(original);

      final edited = FinanceRecurringRule.fromMap(original.toMap())
        ..dayOfMonth = 1;
      edited.markAsChanged();
      await FinanceStorage.saveRecurringRule(edited);

      expect(
        (await FinanceStorage.getRecurringRule(original.uuid))!
            .lastGeneratedPeriod,
        currentPeriod,
      );
      expect(
        await FinanceAutomationService.reconcileCurrentPeriod(
          now: DateTime(now.year, now.month, now.day, 12),
        ),
        0,
      );
      expect(await FinanceStorage.getTransactions(), isEmpty);
    });

    for (final source in ['backup', 'remote']) {
      test('$source 同步把每月到期日改到本月已过日期不会倒签', () async {
        final now = DateTime.now();
        final currentPeriod = financeMonthKey(now);
        final previousPeriod = financeMonthKey(
          DateTime(now.year, now.month - 1),
        );
        final original = FinanceRecurringRule(
          uuid: 'synced-recurring-day-into-past-$source',
          name: '同步调整到期日的月费',
          amountMinor: 10000,
          dayOfMonth: 25,
          startDate: dateKey(DateTime(now.year, now.month, 1)),
          lastGeneratedPeriod: previousPeriod,
        );
        await FinanceStorage.saveRecurringRule(original);
        final incoming = FinanceRecurringRule.fromMap(original.toMap())
          ..dayOfMonth = 1;
        incoming.markAsChanged();
        final bundle = {
          'recurring_rules': [incoming.toMap()],
        };

        if (source == 'backup') {
          await FinanceStorage.importBundle(bundle);
        } else {
          await FinanceStorage.mergeRemoteBundle(bundle);
        }

        expect(
          (await FinanceStorage.getRecurringRule(original.uuid))!
              .lastGeneratedPeriod,
          currentPeriod,
        );
        expect(
          await FinanceAutomationService.reconcileCurrentPeriod(
            now: DateTime(now.year, now.month, now.day, 12),
          ),
          0,
        );
        expect(await FinanceStorage.getTransactions(), isEmpty);
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

  test('免打扰拦截时不消耗预算提醒去重标记', () async {
    const accountKey = 'finance-budget-alert-test-user';
    final db = await openDatabase();
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);

    final now = DateTime(2026, 10, 2, 12);
    final monthKey = financeMonthKey(now);
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'dnd-budget-alert',
        monthKey: monthKey,
        amountMinor: 10000,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'dnd-budget-alert-expense',
        amountMinor: 8000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );

    await FocusDoNotDisturbService.setActive(true);
    expect(FocusDoNotDisturbService.isActive, isTrue);

    await FinanceAutomationService.checkBudgetAlerts(now: now);

    final savedBudget = (await FinanceStorage.getBudgets(monthKey: monthKey))
        .single;
    final alertKey =
        'finance-budget-v1-$accountKey-${savedBudget.uuid}-'
        '${savedBudget.monthKey}-${savedBudget.version}-80';
    expect(prefs.getBool(alertKey), isNull);
  });

  test('保存预算时立即检查已有支出并发送阈值提醒', () async {
    final db = await openDatabase();
    const accountKey = 'finance-budget-save-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    var shownNotifications = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          shownNotifications++;
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    final monthKey = financeMonthKey(now);
    await FinanceRepository.saveTransaction(
      FinanceTransaction(
        uuid: 'expense-before-budget-save',
        amountMinor: 8000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );

    await FinanceRepository.saveBudget(
      FinanceBudget(
        uuid: 'saved-budget-alert',
        monthKey: monthKey,
        amountMinor: 10000,
      ),
    );

    final savedBudget = (await FinanceStorage.getBudgets(monthKey: monthKey))
        .single;
    final alertKey =
        'finance-budget-v1-$accountKey-${savedBudget.uuid}-'
        '${savedBudget.monthKey}-${savedBudget.version}-80';
    expect(shownNotifications, 1);
    expect(prefs.getBool(alertKey), isTrue);

    await FinanceStorage.deleteTransaction('expense-before-budget-save');
    await _clearBudgetAlertMarkers(prefs, accountKey);
    await FinanceRepository.restoreTransaction('expense-before-budget-save');
    expect(shownNotifications, 2);

    await FinanceStorage.deleteBudget(savedBudget.uuid);
    await _clearBudgetAlertMarkers(prefs, accountKey);
    await FinanceRepository.restoreBudget(savedBudget.uuid);
    expect(shownNotifications, 3);
  });

  test('删除退款使净支出重新达到预算阈值时立即提醒', () async {
    final db = await openDatabase();
    const accountKey = 'finance-refund-delete-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    final notificationBodies = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          notificationBodies.add(arguments['body'] as String);
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'refund-delete-budget',
        monthKey: financeMonthKey(now),
        amountMinor: 10000,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'refund-delete-expense',
        amountMinor: 8000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'refund-delete-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 1000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
        relatedTransactionUuid: 'refund-delete-expense',
      ),
    );

    await FinanceRepository.deleteTransaction('refund-delete-refund');

    expect(notificationBodies, ['本月总支出 ¥80.00 / ¥100.00']);
  });

  test('标记贷款还款后利息达到预算阈值时立即提醒', () async {
    final db = await openDatabase();
    const accountKey = 'finance-loan-interest-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    final notificationBodies = <String>[];
    final notificationShown = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          notificationBodies.add(arguments['body'] as String);
          if (!notificationShown.isCompleted) notificationShown.complete();
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'loan-interest-budget',
        monthKey: financeMonthKey(now),
        amountMinor: 100000,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'loan-interest-existing-expense',
        amountMinor: 79000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );
    await FinanceStorage.saveLoan(
      FinanceLoan(
        uuid: 'loan-interest-budget-loan',
        name: '预算提醒贷款',
        principalMinor: 100000,
        annualInterestRateBps: 1200,
        termMonths: 1,
        startDate: dateKey(now),
        repaymentDay: now.day,
      ),
    );
    final installment = (await FinanceStorage.getLoanInstallments(
      'loan-interest-budget-loan',
    )).single;

    await FinanceRepository.setLoanInstallmentPaid(installment.uuid, true);
    await notificationShown.future.timeout(const Duration(seconds: 5));

    expect(installment.interestMinor, 1000);
    expect(notificationBodies, ['本月总支出 ¥800.00 / ¥1,000.00']);
  });

  test('大额预算提醒不会截断已使用金额', () async {
    final db = await openDatabase();
    const accountKey = 'finance-large-budget-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    final notificationBodies = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          notificationBodies.add(arguments['body'] as String);
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    final monthKey = financeMonthKey(now);
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'large-budget-alert',
        monthKey: monthKey,
        amountMinor: 3000000000,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'large-budget-alert-expense',
        amountMinor: 2500000000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );

    await FinanceAutomationService.checkBudgetAlerts(now: now);

    expect(notificationBodies, ['本月总支出 ¥25,000,000.00 / ¥30,000,000.00']);
  });

  test('并发预算检查只发送一次相同提醒', () async {
    final db = await openDatabase();
    const accountKey = 'finance-concurrent-budget-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    var shownNotifications = 0;
    final notificationStarted = Completer<void>();
    final releaseNotification = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          shownNotifications++;
          if (!notificationStarted.isCompleted) notificationStarted.complete();
          await releaseNotification.future;
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      if (!releaseNotification.isCompleted) releaseNotification.complete();
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(true);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'concurrent-budget-alert',
        monthKey: financeMonthKey(now),
        amountMinor: 10000,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'concurrent-budget-alert-expense',
        amountMinor: 8000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );

    final first = FinanceAutomationService.checkBudgetAlerts(now: now);
    await notificationStarted.future.timeout(const Duration(seconds: 3));
    final second = FinanceAutomationService.checkBudgetAlerts(now: now);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    releaseNotification.complete();
    await Future.wait([first, second]);

    expect(shownNotifications, 1);
  });

  test('开启预算提醒后立即检查已达到阈值的支出', () async {
    final db = await openDatabase();
    const accountKey = 'finance-enable-budget-alert-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    var shownNotifications = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'checkPermissions':
          return {
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': true,
            'isSoundEnabled': true,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
            'isProvidesAppNotificationSettingsEnabled': false,
          };
        case 'show':
          shownNotifications++;
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);
    await AppSettingsStorage.setNormalNotificationEnabled(true);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    final monthKey = financeMonthKey(now);
    await FinanceStorage.saveBudget(
      FinanceBudget(
        uuid: 'enabled-budget-alert',
        monthKey: monthKey,
        amountMinor: 10000,
      ),
    );
    await FinanceStorage.saveTransaction(
      FinanceTransaction(
        uuid: 'enabled-budget-alert-expense',
        amountMinor: 8000,
        transactionDate: dateKey(now),
        occurredAt: now.millisecondsSinceEpoch,
      ),
    );

    await FinanceAutomationService.setBudgetAlertsEnabled(true);

    expect(shownNotifications, 1);
    final budget = (await FinanceStorage.getBudgets(monthKey: monthKey)).single;
    final alertKey =
        'finance-budget-v1-$accountKey-${budget.uuid}-'
        '${budget.monthKey}-${budget.version}-80';
    expect(prefs.getBool(alertKey), isTrue);
  });

  test('从回收站恢复周期账单后重新调度提醒', () async {
    final db = await openDatabase();
    const accountKey = 'finance-recurring-restore-test-user';
    const localNotificationChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const macStatusBarChannel = MethodChannel(
      'countdown_todo/macos_status_bar',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(localNotificationChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'zonedSchedule':
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      macStatusBarChannel,
      (call) async => null,
    );
    addTearDown(() async {
      await FocusDoNotDisturbService.setActive(false, force: true);
      messenger.setMockMethodCallHandler(localNotificationChannel, null);
      messenger.setMockMethodCallHandler(macStatusBarChannel, null);
      debugDefaultTargetPlatformOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyCurrentUser, accountKey);
    await prefs.setInt('current_user_id', 1);
    await FocusDoNotDisturbService.setActive(false, force: true);
    final now = DateTime.now();
    final dueTomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final rule = FinanceRecurringRule(
      uuid: 'trash-restored-recurring-reminder',
      name: '恢复后提醒',
      amountMinor: 10000,
      dayOfMonth: dueTomorrow.day,
      startDate: dateKey(now),
      autoGenerate: false,
      reminderMinutes: 60,
    );
    await FinanceStorage.saveRecurringRule(rule);
    await FinanceStorage.deleteRecurringRule(rule.uuid);

    await FinanceRepository.restoreRecurringRule(rule.uuid);

    final scheduled = await StorageService.getWindowsScheduledReminders();
    expect(
      scheduled.any((reminder) => reminder['financeRuleUuid'] == rule.uuid),
      isTrue,
    );
  });
}

Future<void> _clearBudgetAlertMarkers(
  SharedPreferences prefs,
  String accountKey,
) async {
  final prefix = 'finance-budget-v1-$accountKey-';
  for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
    await prefs.remove(key);
  }
}
