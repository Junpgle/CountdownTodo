@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_automation_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('编辑周期规则不会清空已生成周期或重复生成本月账单', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'recurring-idempotency-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final rule = FinanceRecurringRule(
      uuid: 'rule-phone',
      name: '话费',
      amountMinor: 5000,
      dayOfMonth: 1,
      startDate: '2026-01-01',
    );
    await FinanceStorage.saveRecurringRule(rule);

    expect(
      await FinanceAutomationService.reconcileCurrentPeriod(
        now: DateTime(2026, 8, 1, 10),
      ),
      1,
    );
    expect(await FinanceStorage.getTransactions(), hasLength(1));
    final generated = await FinanceStorage.getTransactions(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(generated, hasLength(1));
    final persisted = await FinanceStorage.getRecurringRule('rule-phone');
    expect(persisted?.lastGeneratedPeriod, '2026-08');

    final staleEdit = FinanceRecurringRule(
      uuid: persisted!.uuid,
      name: '话费（已修改）',
      amountMinor: persisted.amountMinor,
      dayOfMonth: persisted.dayOfMonth,
      startDate: persisted.startDate,
      createdAt: persisted.createdAt,
      updatedAt: persisted.updatedAt,
      version: persisted.version,
      // 编辑页打开时可能还停留在上个月的快照，而不是简单的 null。
      lastGeneratedPeriod: '2026-07',
    );
    await FinanceStorage.saveRecurringRule(staleEdit);
    expect(
      (await FinanceStorage.getRecurringRule('rule-phone'))
          ?.lastGeneratedPeriod,
      '2026-08',
    );

    expect(
      await FinanceAutomationService.reconcileCurrentPeriod(
        now: DateTime(2026, 8, 1, 10),
      ),
      0,
    );
    expect(
      await FinanceStorage.getTransactions(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 9, 1),
      ),
      hasLength(1),
    );

    // 模拟旧快照确实把标记清空，确定性交易 UUID 仍能挡住重复账单。
    await db.update(
      'finance_recurring_rules',
      {'last_generated_period': null},
      where: 'uuid = ?',
      whereArgs: ['rule-phone'],
    );
    expect(
      await FinanceAutomationService.reconcileCurrentPeriod(
        now: DateTime(2026, 8, 1, 10),
      ),
      0,
    );
    expect(
      await FinanceStorage.getTransactions(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 9, 1),
      ),
      hasLength(1),
    );
    expect(
      (await FinanceStorage.getRecurringRule('rule-phone'))
          ?.lastGeneratedPeriod,
      '2026-08',
    );
  });
}
