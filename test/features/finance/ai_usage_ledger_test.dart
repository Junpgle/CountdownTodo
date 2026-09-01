@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/ai_usage_cost_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('MiMo 本月低价调用按月合并并补齐自动记账', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'ai-monthly-ledger-test',
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

    await AiUsageCostService.setAutoLedgerEnabled(false);
    for (final timestamp in [
      DateTime(2026, 8, 30, 10),
      DateTime(2026, 8, 31, 10),
    ]) {
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
        now: timestamp,
      );
    }
    expect(await db.query('finance_transactions'), isEmpty);

    await AiUsageCostService.setAutoLedgerEnabled(true);
    await AiUsageCostService.reconcileCurrentMonth(
      now: DateTime(2026, 8, 31, 12),
    );

    final transactions = await FinanceStorage.getTransactions(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(transactions, hasLength(1));
    expect(transactions.single.amountMinor, 1);
    expect(transactions.single.source, FinanceEntrySource.ai);
    expect(transactions.single.transactionDate, '2026-08-01');

    final links = await db.query('ai_usage_ledger_links');
    expect(links, hasLength(1));
    expect(
      links.single['ledger_key'],
      'finance-ai-month-v2|2026-08|mimo|mimo-v2.5',
    );
  });

  test('本月记账会合并旧版按日 AI 账单并软删除重复项', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'ai-legacy-ledger-test',
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

    final firstTimestamp = DateTime(2026, 8, 30, 10);
    final secondTimestamp = DateTime(2026, 8, 31, 10);
    final legacyRecords = [
      (
        uuid: 'legacy-ai-record-1',
        transactionUuid: 'legacy-ai-transaction-1',
        timestamp: firstTimestamp,
      ),
      (
        uuid: 'legacy-ai-record-2',
        transactionUuid: 'legacy-ai-transaction-2',
        timestamp: secondTimestamp,
      ),
    ];
    for (final item in legacyRecords) {
      final dayKey = dateKey(item.timestamp);
      final legacyKey = '$dayKey|mimo|mimo-v2.5';
      final transaction = FinanceTransaction(
        uuid: item.transactionUuid,
        amountMinor: 1,
        categoryUuid: 'finance-system-category-ai-service',
        paymentMethodUuid: 'finance-system-payment-other',
        transactionDate: dayKey,
        merchant: 'mimo · mimo-v2.5',
        source: FinanceEntrySource.ai,
      );
      await db.insert('finance_transactions', transaction.toMap());
      await db.insert('ai_usage_records', {
        'uuid': item.uuid,
        'provider': 'mimo',
        'model': 'mimo-v2.5',
        'operation': 'vision_todo',
        'prompt_tokens': 10000,
        'completion_tokens': 2000,
        'total_tokens': 12000,
        'cached_prompt_tokens': 8000,
        'image_tokens': 500,
        'audio_tokens': 0,
        'video_tokens': 0,
        'reasoning_tokens': 0,
        'audio_seconds': 0,
        'image_count': 1,
        'cost_micros': 6160,
        'is_priced': 1,
        'ledger_key': legacyKey,
        'created_at': item.timestamp.millisecondsSinceEpoch,
      });
      await db.insert('ai_usage_ledger_links', {
        'ledger_key': legacyKey,
        'finance_transaction_uuid': item.transactionUuid,
        'updated_at': item.timestamp.millisecondsSinceEpoch,
      });
    }

    await AiUsageCostService.reconcileCurrentMonth(
      now: DateTime(2026, 8, 31, 12),
    );

    final activeTransactions = await FinanceStorage.getTransactions(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 9, 1),
    );
    expect(activeTransactions, hasLength(1));
    expect(activeTransactions.single.amountMinor, 1);
    final allTransactions = await db.query(
      'finance_transactions',
      orderBy: 'uuid ASC',
    );
    expect(allTransactions, hasLength(2));
    expect(
      allTransactions.where((row) => row['is_deleted'] == 1),
      hasLength(1),
    );
    expect(await db.query('ai_usage_ledger_links'), hasLength(1));
    expect(
      (await db.query('ai_usage_ledger_links')).single['ledger_key'],
      'finance-ai-month-v2|2026-08|mimo|mimo-v2.5',
    );
  });
}
