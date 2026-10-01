@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    for (final month in ['2026-08', '2026-09']) {
      await FinanceStorage.saveBudget(
        FinanceBudget(monthKey: month, amountMinor: 10000),
      );
    }
    for (final item in [
      FinanceTransaction(
        uuid: 'august',
        amountMinor: 1000,
        transactionDate: '2026-08-31',
      ),
      FinanceTransaction(
        uuid: 'earlier-september',
        amountMinor: 3000,
        transactionDate: '2026-09-01',
      ),
      FinanceTransaction(
        uuid: 'today',
        amountMinor: 2000,
        transactionDate: '2026-09-02',
      ),
    ]) {
      await FinanceStorage.saveTransaction(item);
    }
  });
  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  test('今天明细只包含当天，月预算包含整月支出', () async {
    final context = await FinanceAiContextService.buildContext(
      userMessage: '今天支出和预算还有多少',
      now: DateTime(2026, 9, 2),
    );
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥50.00 | 剩余 ¥50.00'));
    expect(context, contains('[transactionId: today]'));
    expect(context, isNot(contains('[transactionId: earlier-september]')));
    expect(context, isNot(contains('[transactionId: august]')));
    expect(context, contains('净支出 ¥20.00'));
  });

  test('跨月周查询分别给出两个自然月预算，不能混用整周支出', () async {
    final context = await FinanceAiContextService.buildContext(
      userMessage: '本周支出和预算还有多少',
      now: DateTime(2026, 9, 2),
    );
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥10.00 | 剩余 ¥90.00'));
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥50.00 | 剩余 ¥50.00'));
    expect(context, contains('净支出 ¥60.00'));
  });

  test('今年查询按实际月份给出预算，账单汇总仍按全年', () async {
    final context = await FinanceAiContextService.buildContext(
      userMessage: '今年支出和预算还有多少',
      now: DateTime(2026, 9, 2),
    );
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥10.00 | 剩余 ¥90.00'));
    expect(context, contains('整体: 额度 ¥100.00 | 已用 ¥50.00 | 剩余 ¥50.00'));
    expect(context, contains('净支出 ¥60.00'));
  });
}
