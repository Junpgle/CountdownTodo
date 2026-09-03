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

  FinanceTransaction refundTestExpense({
    String uuid = 'original-expense',
    int amountMinor = 10000,
    int updatedAt = 10,
  }) {
    return FinanceTransaction(
      uuid: uuid,
      type: FinanceTransactionType.expense,
      amountMinor: amountMinor,
      categoryUuid: 'category-food',
      paymentMethodUuid: 'payment-card',
      transactionDate: '2026-09-01',
      merchant: '原单商户',
      createdAt: 10,
      updatedAt: updatedAt,
    );
  }

  FinanceTransaction refundTestTransaction({
    required String uuid,
    required String originalUuid,
    required int amountMinor,
    int updatedAt = 20,
  }) {
    return FinanceTransaction(
      uuid: uuid,
      type: FinanceTransactionType.refund,
      amountMinor: amountMinor,
      categoryUuid: 'category-other',
      transactionDate: '2026-09-02',
      relatedTransactionUuid: originalUuid,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

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

  test('同一预算范围使用稳定 UUID，远端重复范围只保留较新记录', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'budget-scope-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final local = FinanceBudget(
      monthKey: '2026-09',
      categoryUuid: 'category-food',
      amountMinor: 30000,
    );
    await FinanceStorage.saveBudget(local);
    expect(
      local.uuid,
      FinanceBudget.stableUuid('2026-09', 'category-food'),
    );
    await expectLater(
      FinanceStorage.saveBudget(FinanceBudget(
        monthKey: '2026-09',
        categoryUuid: 'category-food',
        amountMinor: 40000,
      )),
      throwsStateError,
    );

    await FinanceStorage.mergeRemoteBundle({
      'budgets': [
        {
          'uuid': 'remote-newer-budget',
          'month_key': '2026-09',
          'category_uuid': 'category-food',
          'amount_minor': 50000,
          'updated_at': local.updatedAt + 100,
          'created_at': local.createdAt,
          'version': 2,
        },
      ],
    });
    final budgets = await FinanceStorage.getBudgets(monthKey: '2026-09');
    expect(budgets, hasLength(1));
    expect(budgets.single.uuid, 'remote-newer-budget');
    expect(budgets.single.amountMinor, 50000);
  });

  test('远端较新预算墓碑会压住同范围的历史活动副本', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'budget-tombstone-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    await FinanceStorage.mergeRemoteBundle({
      'budgets': [
        {
          'uuid': 'old-active-budget',
          'month_key': '2026-09',
          'category_uuid': 'category-food',
          'amount_minor': 30000,
          'is_deleted': 0,
          'updated_at': 100,
          'created_at': 100,
          'version': 1,
        },
        {
          'uuid': 'new-budget-tombstone',
          'month_key': '2026-09',
          'category_uuid': 'category-food',
          'amount_minor': 30000,
          'is_deleted': 1,
          'updated_at': 200,
          'created_at': 100,
          'version': 2,
        },
      ],
    });

    expect(await FinanceStorage.getBudgets(monthKey: '2026-09'), isEmpty);
    final stored = await db.query('finance_budgets');
    expect(stored, hasLength(1));
    expect(stored.single['uuid'], 'new-budget-tombstone');
    expect(stored.single['is_deleted'], 1);
  });

  test('记账导出脱敏覆盖贷款和还款明细', () {
    final bundle = <String, dynamic>{
      for (final key in [
        'transactions',
        'categories',
        'payment_methods',
        'budgets',
        'recurring_rules',
        'templates',
        'loans',
        'loan_installments',
      ])
        key: [
          <String, dynamic>{
            'uuid': '$key-1',
            'device_id': 'private-device',
          },
        ],
    };

    FinanceStorage.removeDeviceIdsFromExportBundle(bundle);

    for (final items in bundle.values) {
      expect((items as List).single['device_id'], isNull);
    }
  });

  test('导入跳过无效账单和孤立还款计划', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-import-validation-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final result = await FinanceStorage.importBundle({
      'transactions': [
        {
          'uuid': 'zero-amount',
          'type': 'expense',
          'amount_minor': 0,
          'transaction_date': '2026-09-01',
        },
        {
          'uuid': 'bad-date',
          'type': 'expense',
          'amount_minor': 100,
          'transaction_date': 'not-a-date',
        },
      ],
      'loan_installments': [
        {
          'uuid': 'orphan-installment',
          'loan_uuid': 'missing-loan',
          'installment_index': 1,
          'due_date': '2026-09-01',
          'payment_minor': 110,
          'principal_minor': 100,
          'interest_minor': 10,
          'remaining_principal_minor': 0,
        },
      ],
    });

    expect(result['imported'], 0);
    expect(result['skipped'], 3);
    expect(await db.query('finance_transactions'), isEmpty);
    expect(await db.query('finance_loan_installments'), isEmpty);
  });

  test('历史退款分类迁移到支出侧的专用分类', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'refund-migration-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    final oldUpdatedAt = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    await db.insert('finance_transactions', {
      'uuid': 'legacy-refund',
      'type': 'refund',
      'amount_minor': 1200,
      'currency_code': 'CNY',
      'category_uuid': 'finance-system-category-salary',
      'transaction_date': '2026-01-01',
      'timezone_offset_minutes': 480,
      'source': 'manual',
      'is_deleted': 0,
      'version': 1,
      'created_at': oldUpdatedAt,
      'updated_at': oldUpdatedAt,
      'pending_sync': 0,
    });

    final transactions = await FinanceStorage.getTransactions();
    final refundCategory = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-refund'],
    );

    expect(transactions.single.categoryUuid, 'finance-system-category-refund');
    expect(transactions.single.pendingSync, isTrue);
    expect(refundCategory.single['type'], 'expense');
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
    final stableInterestUuid = paid!.interestTransactionUuid;

    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, false);
    expect(
      await db.query(
        'finance_transactions',
        where: 'related_transaction_uuid = ? AND is_deleted = 0',
        whereArgs: [installments.first.uuid],
      ),
      isEmpty,
    );
    await FinanceStorage.setLoanInstallmentPaid(installments.first.uuid, true);
    final repaid =
        await FinanceStorage.getLoanInstallment(installments.first.uuid);
    expect(repaid?.interestTransactionUuid, stableInterestUuid);
    expect(
      await db.query(
        'finance_transactions',
        where: 'related_transaction_uuid = ? AND is_deleted = 0',
        whereArgs: [installments.first.uuid],
      ),
      hasLength(1),
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

  test('pricing settings preserve tier and peak metadata', () {
    const pricing = AiUsagePricing(
      provider: 'deepseek',
      model: 'deepseek-v4-flash',
      cachedInputMicrosPerMillion: 50000,
      inputMicrosPerMillion: 1500000,
      outputMicrosPerMillion: 4500000,
      peakCachedInputMicrosPerMillion: 100000,
      peakInputMicrosPerMillion: 3000000,
      peakOutputMicrosPerMillion: 9000000,
      imageTokensIncluded: true,
      tiers: [
        AiUsagePriceTier(
          maxPromptTokens: 32000,
          maxCompletionTokens: 200000,
          cachedInputMicrosPerMillion: 400000,
          inputMicrosPerMillion: 2000000,
          outputMicrosPerMillion: 8000000,
        ),
      ],
    );

    final restored = AiUsagePricing.fromJson(pricing.toJson());
    expect(restored.provider, pricing.provider);
    expect(restored.peakInputMicrosPerMillion, 3000000);
    expect(restored.imageTokensIncluded, isTrue);
    expect(restored.tiers.single.maxPromptTokens, 32000);
    expect(restored.tiers.single.maxCompletionTokens, 200000);
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

  test('Zhipu pricing applies prompt and completion token tiers', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'zhipu-tier-cost-test',
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

    final pricing = (await AiUsageCostService.getPricing()).firstWhere(
      (item) => item.provider == 'zhipu' && item.model == 'glm-4.7',
    );
    expect(pricing.tiers, hasLength(3));

    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7',
      operation: 'chat',
      promptTokens: 10000,
      completionTokens: 100000,
      totalTokens: 110000,
      cachedPromptTokens: 2000,
      now: DateTime.utc(2026, 8, 30, 10),
    );
    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7',
      operation: 'chat',
      promptTokens: 40000,
      completionTokens: 100000,
      totalTokens: 140000,
      cachedPromptTokens: 10000,
      now: DateTime.utc(2026, 8, 31, 10),
    );
    await AiUsageCostService.recordUsage(
      provider: 'zhipu',
      model: 'glm-4.7',
      operation: 'chat',
      promptTokens: 10000,
      completionTokens: 200000,
      totalTokens: 210000,
      cachedPromptTokens: 2000,
      now: DateTime.utc(2026, 8, 31, 11),
    );

    final records = await AiUsageCostService.getRecords();
    expect(
        records.map((item) => item.costMicros),
        containsAll(<int?>[
          816800,
          1728000,
          2825200,
        ]));
    expect(records.every((item) => item.isPriced), isTrue);
  });

  test('Zhipu visual token pricing does not add a per-image fee', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'zhipu-vision-cost-test',
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
      provider: 'zhipu',
      model: 'glm-4.6v',
      operation: 'vision_todo',
      promptTokens: 10000,
      completionTokens: 1000,
      totalTokens: 11000,
      cachedPromptTokens: 1000,
      imageTokens: 1500,
      imageCount: 1,
      now: DateTime.utc(2026, 8, 31, 1),
    );

    final record = (await AiUsageCostService.getRecords()).single;
    // 9,000 * ¥1/M + 1,000 * ¥0.2/M + 1,000 * ¥3/M = ¥0.0122.
    expect(record.costMicros, 12200);
    expect(record.isPriced, isTrue);
  });

  test('DeepSeek pricing switches between Beijing peak and off-peak rates',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'deepseek-peak-cost-test',
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

    for (final timestamp in <DateTime>[
      DateTime.utc(2026, 8, 31, 0), // Beijing 08:00, off-peak.
      DateTime.utc(2026, 8, 31, 2), // Beijing 10:00, peak.
    ]) {
      await AiUsageCostService.recordUsage(
        provider: 'deepseek',
        model: 'deepseek-v4-flash',
        operation: 'chat',
        promptTokens: 1000000,
        completionTokens: 100000,
        totalTokens: 1100000,
        cachedPromptTokens: 400000,
        now: timestamp,
      );
    }

    final records = await AiUsageCostService.getRecords();
    expect(
        records.map((item) => item.costMicros),
        containsAll(<int?>[
          1370000,
          2740000,
        ]));
  });

  test('free provider models are priced at zero when usage is available',
      () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'free-model-cost-test',
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
      provider: 'zhipu',
      model: 'glm-4.7-flash',
      operation: 'chat',
      promptTokens: 100000,
      completionTokens: 100000,
      totalTokens: 200000,
      now: DateTime.utc(2026, 8, 31, 1),
    );

    final record = (await AiUsageCostService.getRecords()).single;
    expect(record.costMicros, 0);
    expect(record.isPriced, isTrue);
  });

  test('NVIDIA NIM has no guessed universal built-in price', () async {
    SharedPreferences.setMockInitialValues({});

    final pricing = await AiUsageCostService.getPricing();
    expect(pricing.where((item) => item.provider == 'nvidia_nim'), isEmpty);
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

  test('备份导入不能覆盖或伪造系统目录', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-system-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();

    final result = await FinanceStorage.importBundle({
      'categories': [
        {
          'uuid': 'finance-system-category-food',
          'name': '被篡改的分类',
          'type': 'income',
          'is_system': 0,
          'updated_at': 9999999999999,
        },
        {
          'uuid': 'fake-system-category',
          'name': '伪系统分类',
          'type': 'expense',
          'is_system': 1,
          'updated_at': 9999999999999,
        },
      ],
      'payment_methods': [
        {
          'uuid': 'finance-system-payment-cash',
          'name': '被篡改的现金',
          'is_system': 0,
          'updated_at': 9999999999999,
        },
      ],
    });

    expect(result['skipped'], 3);
    final food = await db.query(
      'finance_categories',
      where: 'uuid = ?',
      whereArgs: ['finance-system-category-food'],
    );
    final cash = await db.query(
      'finance_payment_methods',
      where: 'uuid = ?',
      whereArgs: ['finance-system-payment-cash'],
    );
    expect(food.single['name'], isNot('被篡改的分类'));
    expect(cash.single['name'], isNot('被篡改的现金'));
    expect(
      await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['fake-system-category'],
      ),
      isEmpty,
    );
  });

  test('旧版数字交易类型备份仍可正常导入', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-numeric-type-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final result = await FinanceStorage.importBundle({
      'transactions': [
        {
          'uuid': 'legacy-numeric-refund',
          'type': 2,
          'amount_minor': 880,
          'transaction_date': '2026-08-31',
          'created_at': 10,
          'updated_at': 10,
        },
      ],
    });
    expect(result['imported'], 1);
    expect(
      (await FinanceStorage.getTransaction('legacy-numeric-refund'))!.type,
      FinanceTransactionType.refund,
    );
  });

  test('已删除贷款不接受活动还款计划', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-deleted-loan-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    final loan = FinanceLoan(
      uuid: 'deleted-loan',
      name: '已删除贷款',
      principalMinor: 100000,
      annualInterestRateBps: 300,
      termMonths: 12,
      startDate: '2026-01-01',
      repaymentDay: 1,
      isDeleted: true,
      createdAt: 10,
      updatedAt: 10,
    );
    final installment = FinanceLoanInstallment(
      uuid: 'orphan-active-installment',
      loanUuid: loan.uuid,
      installmentIndex: 1,
      dueDate: '2026-02-01',
      paymentMinor: 8500,
      principalMinor: 8300,
      interestMinor: 200,
      remainingPrincipalMinor: 91700,
      createdAt: 11,
      updatedAt: 11,
    );

    final result = await FinanceStorage.importBundle({
      'loans': [loan.toMap()],
      'loan_installments': [installment.toMap()],
    });
    expect(result['imported'], 1);
    expect(result['skipped'], 1);
    expect(
      await db.query('finance_loan_installments'),
      isEmpty,
    );
    expect(
      await FinanceStorage.mergeRemoteBundle({
        'loan_installments': [
          {...installment.toMap(), 'uuid': 'remote-active-installment'},
        ],
      }),
      0,
    );
  });

  test('记账备份导入中途失败时整批回滚', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-atomic-import-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await db.execute('''
      CREATE TRIGGER fail_finance_budget_import
      BEFORE INSERT ON finance_budgets
      BEGIN
        SELECT RAISE(ABORT, 'forced import failure');
      END
    ''');

    await expectLater(
      FinanceStorage.importBundle({
        'categories': [
          {
            'uuid': 'category-before-failure',
            'name': '应当回滚',
            'type': 'expense',
            'updated_at': 10,
          },
        ],
        'budgets': [
          {
            'uuid': 'budget-trigger-failure',
            'month_key': '2026-09',
            'amount_minor': 10000,
            'updated_at': 11,
          },
        ],
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: ['category-before-failure'],
      ),
      isEmpty,
    );
  });

  test('删除后重建稳定范围预算会超过旧墓碑版本', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-budget-recreate-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final first = FinanceBudget(
      monthKey: '2026-09',
      categoryUuid: 'category-food',
      amountMinor: 10000,
      updatedAt: 10,
    );
    await FinanceStorage.saveBudget(first);
    await FinanceStorage.deleteBudget(first.uuid);
    final tombstone = (await FinanceStorage.getBudget(first.uuid))!;
    tombstone.updatedAt = 9999999999999;
    await db.update(
      'finance_budgets',
      tombstone.toMap(),
      where: 'uuid = ?',
      whereArgs: [tombstone.uuid],
    );

    final recreated = FinanceBudget(
      monthKey: first.monthKey,
      categoryUuid: first.categoryUuid,
      amountMinor: 20000,
      updatedAt: 20,
    );
    await FinanceStorage.saveBudget(recreated);
    final stored = (await FinanceStorage.getBudget(first.uuid))!;
    expect(recreated.uuid, first.uuid);
    expect(stored.isDeleted, isFalse);
    expect(stored.amountMinor, 20000);
    expect(stored.version, greaterThan(tombstone.version));
    expect(stored.updatedAt, greaterThan(tombstone.updatedAt));
  });

  test('原单支持多次部分退款，累计不能超过原金额', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-refund-binding-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final original = refundTestExpense();
    await FinanceStorage.saveTransaction(original);
    final first = refundTestTransaction(
      uuid: 'refund-1',
      originalUuid: original.uuid,
      amountMinor: 3000,
    );
    await FinanceStorage.saveTransaction(first);
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      7000,
    );
    final storedFirst = await FinanceStorage.getTransaction(first.uuid);
    expect(storedFirst!.relatedTransactionUuid, original.uuid);
    expect(storedFirst.categoryUuid, original.categoryUuid);

    final second = refundTestTransaction(
      uuid: 'refund-2',
      originalUuid: original.uuid,
      amountMinor: 7000,
    );
    await FinanceStorage.saveTransaction(second);
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      0,
    );
    await expectLater(
      FinanceStorage.saveTransaction(refundTestTransaction(
        uuid: 'refund-overflow',
        originalUuid: original.uuid,
        amountMinor: 1,
      )),
      throwsStateError,
    );

    first
      ..amountMinor = 2000
      ..updatedAt = 30;
    await FinanceStorage.saveTransaction(first);
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      1000,
    );
    original
      ..isDeleted = true
      ..updatedAt = 40;
    await expectLater(
      FinanceStorage.saveTransaction(original),
      throwsStateError,
    );
  });

  test('退款只能绑定存在且未删除的支出原单', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-refund-target-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    await expectLater(
      FinanceStorage.saveTransaction(refundTestTransaction(
        uuid: 'missing-original-refund',
        originalUuid: 'missing-original',
        amountMinor: 100,
      )),
      throwsStateError,
    );
    final income = refundTestExpense(uuid: 'income-original')
      ..type = FinanceTransactionType.income;
    await FinanceStorage.saveTransaction(income);
    await expectLater(
      FinanceStorage.saveTransaction(refundTestTransaction(
        uuid: 'income-refund',
        originalUuid: income.uuid,
        amountMinor: 100,
      )),
      throwsStateError,
    );
  });

  test('云端合并先落原单再校验退款，超额记录会被忽略', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-refund-merge-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;

    final original = refundTestExpense(
      uuid: 'remote-original',
      updatedAt: 10,
    );
    final partial = refundTestTransaction(
      uuid: 'remote-refund',
      originalUuid: original.uuid,
      amountMinor: 4000,
      updatedAt: 11,
    );
    expect(
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [partial.toMap(), original.toMap()],
      }),
      2,
    );
    expect(
      await FinanceStorage.getRemainingRefundableMinor(original.uuid),
      6000,
    );

    final overflow = refundTestTransaction(
      uuid: 'remote-overflow',
      originalUuid: original.uuid,
      amountMinor: 6001,
      updatedAt: 12,
    );
    expect(
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [overflow.toMap()],
      }),
      0,
    );
    expect(await FinanceStorage.getTransaction(overflow.uuid), isNull);
  });
}
