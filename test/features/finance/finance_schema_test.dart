@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/models/finance_models.dart';
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
        'finance_loans',
        'finance_loan_installments',
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

    final transactionColumns = await db.rawQuery(
      'PRAGMA table_info(finance_transactions)',
    );
    expect(
      transactionColumns.map((row) => row['name']),
      containsAll(<Object>{
        'installment_group_uuid',
        'installment_index',
        'installment_count',
        'installment_total_minor',
      }),
    );

    final loanColumns = await db.rawQuery(
      'PRAGMA table_info(finance_loans)',
    );
    expect(
      loanColumns.map((row) => row['name']),
      containsAll(<Object>{
        'principal_minor',
        'annual_interest_rate_bps',
        'term_months',
        'repayment_method',
        'pending_sync',
      }),
    );

    final loanInstallmentColumns = await db.rawQuery(
      'PRAGMA table_info(finance_loan_installments)',
    );
    expect(
      loanInstallmentColumns.map((row) => row['name']),
      containsAll(<Object>{
        'loan_uuid',
        'payment_minor',
        'principal_minor',
        'interest_minor',
        'remaining_principal_minor',
        'is_paid',
        'interest_transaction_uuid',
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
      'finance_loans',
      'finance_loan_installments',
    ]) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      expect(columns.map((row) => row['name']), contains('pending_sync'));
    }
  });

  test('AI usage schema upgrades existing records with MiMo detail columns',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE ai_usage_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        operation TEXT NOT NULL,
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        image_count INTEGER NOT NULL DEFAULT 0,
        cost_micros INTEGER,
        is_priced INTEGER NOT NULL DEFAULT 0,
        ledger_key TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await DatabaseHelper.ensureAiUsageSchema(db);

    final columns = await db.rawQuery('PRAGMA table_info(ai_usage_records)');
    expect(
      columns.map((row) => row['name']),
      containsAll(<Object>{
        'cached_prompt_tokens',
        'image_tokens',
        'audio_tokens',
        'video_tokens',
        'reasoning_tokens',
        'audio_seconds',
      }),
    );
  });

  test('贷款保存还款计划，已还利息进入支出并支持删除恢复', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'loan-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    await FinanceStorage.saveLoan(
      FinanceLoan(
        uuid: 'loan-1',
        name: '消费贷',
        lender: '测试银行',
        principalMinor: 1000000,
        annualInterestRateBps: 1200,
        termMonths: 3,
        startDate: '2026-01-31',
        repaymentDay: 31,
      ),
    );

    final installments = await FinanceStorage.getLoanInstallments('loan-1');
    expect(installments, hasLength(3));
    expect(installments.first.dueDate, '2026-02-28');
    expect(
      installments.fold<int>(0, (sum, item) => sum + item.principalMinor),
      1000000,
    );
    expect(installments.last.remainingPrincipalMinor, 0);

    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, true);
    final paid =
        await FinanceStorage.getLoanInstallment(installments.first.uuid);
    expect(paid?.isPaid, isTrue);
    expect(paid?.interestTransactionUuid, isNotNull);
    final interestRows = await db.query(
      'finance_transactions',
      where: 'related_transaction_uuid = ? AND is_deleted = 0',
      whereArgs: [installments.first.uuid],
    );
    expect(interestRows, hasLength(1));
    expect(
        interestRows.single['amount_minor'], installments.first.interestMinor);
    expect(
      interestRows.single['category_uuid'],
      'finance-system-category-loan-interest',
    );

    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, false);
    expect(
      await db.query(
        'finance_transactions',
        where: 'related_transaction_uuid = ? AND is_deleted = 0',
        whereArgs: [installments.first.uuid],
      ),
      isEmpty,
    );

    await FinanceStorage.deleteLoan('loan-1');
    expect(await FinanceStorage.getLoans(), isEmpty);
    expect(
      await FinanceStorage.getLoanInstallments('loan-1'),
      isEmpty,
    );
    expect(
      await FinanceStorage.getLoanInstallments('loan-1', includeDeleted: true),
      everyElement(predicate<FinanceLoanInstallment>((item) => item.isDeleted)),
    );

    await FinanceStorage.restoreLoan('loan-1');
    expect(await FinanceStorage.getLoans(), hasLength(1));
    expect(await FinanceStorage.getLoanInstallments('loan-1'), hasLength(3));
  });

  test('分期账单以同一分期组原子保存，并支持整组删除和恢复', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'installment-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final saved = await FinanceStorage.saveInstallmentPlan(
      transaction: FinanceTransaction(
        uuid: 'installment-root',
        amountMinor: 10000,
        transactionDate: '2026-01-31',
        merchant: '年度服务',
      ),
      totalAmountMinor: 10000,
      installmentCount: 3,
      startDate: DateTime(2026, 1, 31),
    );

    expect(saved, hasLength(3));
    expect(saved.map((item) => item.amountMinor).toList(), [3334, 3333, 3333]);
    expect(saved.every((item) => item.isInstallment), isTrue);
    expect(
        saved.map((item) => item.installmentGroupUuid).toSet(), hasLength(1));
    expect(
      await FinanceStorage.getTransactions(
        from: DateTime(2026, 1),
        to: DateTime(2026, 4),
      ),
      hasLength(3),
    );

    final groupUuid = saved.first.installmentGroupUuid!;
    final edited = await FinanceStorage.saveInstallmentPlan(
      transaction: FinanceTransaction(
        uuid: saved.first.uuid,
        amountMinor: 12000,
        transactionDate: '2026-01-31',
        merchant: '年度服务',
        installmentGroupUuid: groupUuid,
      ),
      totalAmountMinor: 12000,
      installmentCount: 2,
      startDate: DateTime(2026, 1, 31),
      existingInstallments: await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      ),
    );
    expect(edited.map((item) => item.amountMinor).toList(), [6000, 6000]);
    expect(
      await FinanceStorage.getInstallmentGroup(groupUuid, includeDeleted: true),
      everyElement(predicate<FinanceTransaction>(
          (item) => item.isDeleted || item.installmentCount == 2)),
    );

    await FinanceStorage.deleteInstallmentGroup(groupUuid);
    expect(await FinanceStorage.getInstallmentGroup(groupUuid), isEmpty);
    expect(
      await FinanceStorage.getInstallmentGroup(groupUuid, includeDeleted: true),
      everyElement(predicate<FinanceTransaction>((item) => item.isDeleted)),
    );

    await FinanceStorage.restoreInstallmentGroup(groupUuid);
    expect(await FinanceStorage.getInstallmentGroup(groupUuid), hasLength(2));
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

  test('MiMo pricing separates cached input and does not add image fees',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'mimo-cost-test',
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

    final mimoPricing = (await AiUsageCostService.getPricing()).firstWhere(
      (item) => item.provider == 'mimo' && item.model == 'mimo-v2.5',
    );
    expect(mimoPricing.cachedInputMicrosPerMillion, 20000);
    expect(mimoPricing.inputMicrosPerMillion, 1000000);
    expect(mimoPricing.outputMicrosPerMillion, 2000000);

    await AiUsageCostService.recordUsage(
      provider: 'mimo',
      model: 'mimo-v2.5',
      operation: 'vision_todo',
      promptTokens: 10000,
      completionTokens: 2000,
      totalTokens: 12000,
      cachedPromptTokens: 8000,
      imageTokens: 500,
      imageCount: 1,
      now: DateTime(2026, 8, 30, 10),
    );

    final records = await AiUsageCostService.getRecords();
    expect(records, hasLength(1));
    expect(records.single.cachedPromptTokens, 8000);
    expect(records.single.uncachedPromptTokens, 2000);
    expect(records.single.imageTokens, 500);
    // 2,000 * ¥1/M + 8,000 * ¥0.02/M + 2,000 * ¥2/M = ¥0.00616.
    expect(records.single.costMicros, 6160);
    expect(records.single.isPriced, isTrue);

    final summary = await AiUsageCostService.getSummary(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(summary.costMicros, 6160);
    expect(summary.breakdowns.single.cachedPromptTokens, 8000);
    expect(summary.breakdowns.single.imageTokens, 500);
  });

  test('MiMo ASR pricing uses seconds instead of token prices', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'mimo-asr-cost-test',
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

    await AiUsageCostService.recordUsage(
      provider: 'mimo',
      model: 'mimo-v2.5-asr',
      operation: 'asr',
      promptTokens: 46,
      completionTokens: 20,
      totalTokens: 66,
      cachedPromptTokens: 45,
      audioTokens: 25,
      audioSeconds: 4,
      now: DateTime(2026, 8, 30, 10),
    );

    final records = await AiUsageCostService.getRecords();
    expect(records.single.audioSeconds, 4);
    // 4 seconds * ¥0.5/hour = ¥0.000555..., rounded to 556 micro-yuan.
    expect(records.single.costMicros, 556);
    expect(records.single.isPriced, isTrue);
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
