@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  test('priced AI usage is aggregated into one personal finance transaction',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'ai-cost-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;
    await AiUsageCostService.savePricing(
      const AiUsagePricing(
        provider: 'zhipu',
        model: 'glm-test',
        inputMicrosPerMillion: 1000000,
        outputMicrosPerMillion: 2000000,
      ),
    );

    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-test',
      operation: 'chat',
      promptTokens: 1000000,
      completionTokens: 500000,
      totalTokens: 1500000,
      now: DateTime(2026, 8, 30, 10),
    );

    final summary = await AiUsageCostService.getSummary(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(summary.calls, 1);
    expect(summary.costMicros, 2000000);
    final transactions = await db.query('finance_transactions');
    expect(transactions, hasLength(1));
    expect(transactions.single['amount_minor'], 200);
    expect(
      transactions.single['category_uuid'],
      'finance-system-category-ai-service',
    );
  });

  test('unpriced AI usage is retained without creating a guessed expense',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'ai-unpriced-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      AiUsageCostService.databaseOverride = null;
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    await DatabaseHelper.ensureAiUsageSchema(db);
    AiUsageCostService.databaseOverride = db;
    FinanceStorage.databaseOverride = db;
    await AiUsageCostService.savePricing(
      const AiUsagePricing(
        provider: 'custom',
        model: 'unknown-model',
        inputMicrosPerMillion: 1000000,
        outputMicrosPerMillion: 1000000,
        imageMicrosPerImage: 1000000,
      ),
    );

    await AiUsageCostService.recordUsage(
      provider: 'custom',
      model: 'unknown-model',
      operation: 'vision_todo',
      promptTokens: 120,
      completionTokens: 20,
      totalTokens: 140,
      imageCount: 1,
      usageAvailable: false,
      now: DateTime(2026, 8, 30, 10),
    );

    final records = await AiUsageCostService.getRecords();
    expect(records, hasLength(1));
    expect(records.single.isPriced, isFalse);
    expect(await db.query('finance_transactions'), isEmpty);
  });
}
