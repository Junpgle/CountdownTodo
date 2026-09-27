@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/global_search_extra_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('日期搜索包含当月任意一天的预算', () async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    FinanceStorage.databaseOverride = db;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await FinanceStorage.saveBudget(FinanceBudget(
      uuid: 'september-budget',
      monthKey: '2026-09',
      amountMinor: 50000,
      note: '本月预算',
    ));

    final results = await GlobalSearchExtraService.searchFinance(
      ['2026-09-25'],
      DateTime(2026, 9, 25),
    );

    final budgets = results
        .where((item) => item.id.startsWith('finance_budget_'))
        .toList();
    expect(budgets, hasLength(1));
    expect((budgets.single.extraData?['record'] as FinanceBudget).monthKey,
        '2026-09');
  });
}
