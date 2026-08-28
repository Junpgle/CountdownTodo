@TestOn('vm')
library;

import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
      'finance schema creates transaction, catalog, budget and automation tables',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await DatabaseHelper.ensureFinanceSchema(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'finance_%'",
    );
    final names = tables.map((row) => row['name']).toSet();

    expect(
      names,
      containsAll(<Object>{
        'finance_transactions',
        'finance_categories',
        'finance_payment_methods',
        'finance_budgets',
        'finance_recurring_rules',
        'finance_entry_templates',
      }),
    );

    final budgetColumns = await db.rawQuery(
      'PRAGMA table_info(finance_budgets)',
    );
    expect(
      budgetColumns.map((row) => row['name']),
      containsAll(<Object>{
        'month_key',
        'category_uuid',
        'amount_minor',
        'is_deleted',
        'version',
        'pending_sync',
      }),
    );

    for (final table in <String>[
      'finance_categories',
      'finance_payment_methods',
      'finance_transactions',
      'finance_budgets',
      'finance_recurring_rules',
      'finance_entry_templates',
    ]) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      expect(columns.map((row) => row['name']), contains('pending_sync'));
    }
  });
}
