@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
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
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);
  });
  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  for (final path in ['local', 'remote', 'backup']) {
    test('$path 原单改分类后关联退款应跟随原单分类', () async {
      final original = FinanceTransaction(
        uuid: 'audit-original',
        amountMinor: 10000,
        categoryUuid: 'finance-system-category-food',
        transactionDate: '2026-09-01',
      );
      await FinanceStorage.saveTransaction(original);
      final refund = FinanceTransaction(
        uuid: 'audit-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 2000,
        relatedTransactionUuid: original.uuid,
        transactionDate: '2026-09-02',
      );
      await FinanceStorage.saveTransaction(refund);
      original.categoryUuid = 'finance-system-category-transport';
      original.markAsChanged();
      if (path == 'local') {
        await FinanceStorage.saveTransaction(original);
      } else if (path == 'remote') {
        expect(
          await FinanceStorage.mergeRemoteBundle({
            'transactions': [original.toMap()],
          }),
          greaterThan(0),
        );
      } else {
        await FinanceStorage.importBundle({
          'transactions': [original.toMap()],
        });
      }
      final storedRefund = (await FinanceStorage.getTransaction(refund.uuid))!;
      final summary = await FinanceStorage.getSummary(
        from: DateTime(2026, 9),
        to: DateTime(2026, 10),
      );
      expect(storedRefund.categoryUuid, original.categoryUuid);
      expect(summary.expenseByCategory[original.categoryUuid], 8000);
    });
  }

  test('同步整批退款时保留新金额和时间，分类修复保持待同步且重试幂等', () async {
    final original = FinanceTransaction(
      uuid: 'batch-original',
      amountMinor: 10000,
      categoryUuid: 'finance-system-category-food',
      transactionDate: '2026-09-01',
    );
    await FinanceStorage.saveTransaction(original);
    final refund = FinanceTransaction(
      uuid: 'batch-refund',
      type: FinanceTransactionType.refund,
      amountMinor: 2000,
      relatedTransactionUuid: original.uuid,
      transactionDate: '2026-09-02',
    );
    await FinanceStorage.saveTransaction(refund);
    original
      ..categoryUuid = 'finance-system-category-transport'
      ..updatedAt += 20000;
    final remoteRefund = FinanceTransaction.fromMap(refund.toMap())
      ..amountMinor = 3000
      ..transactionDate = '2026-09-03'
      ..updatedAt += 10000;
    final bundle = {
      'transactions': [remoteRefund.toMap(), original.toMap()],
    };
    await FinanceStorage.mergeRemoteBundle(bundle);
    final stored = (await FinanceStorage.getTransaction(refund.uuid))!;
    expect(stored.amountMinor, 3000);
    expect(stored.transactionDate, '2026-09-03');
    expect(stored.categoryUuid, original.categoryUuid);
    expect(stored.pendingSync, true);
    expect(stored.version, remoteRefund.version + 1);
    expect(await FinanceStorage.mergeRemoteBundle(bundle), 0);
    expect(
      (await FinanceStorage.getTransaction(refund.uuid))!.updatedAt,
      stored.updatedAt,
    );
  });

  test('修改分期组分类后，已关联的退款一起转到新分类', () async {
    final seed = FinanceTransaction(
      amountMinor: 10000,
      categoryUuid: 'finance-system-category-food',
      transactionDate: '2026-09-01',
    );
    final group = await FinanceStorage.saveInstallmentPlan(
      transaction: seed,
      totalAmountMinor: 20000,
      installmentCount: 2,
      startDate: DateTime(2026, 9, 1),
    );
    final refund = FinanceTransaction(
      uuid: 'installment-refund',
      type: FinanceTransactionType.refund,
      amountMinor: 2000,
      relatedTransactionUuid: group.first.uuid,
      transactionDate: '2026-09-02',
    );
    await FinanceStorage.saveTransaction(refund);
    group.first.categoryUuid = 'finance-system-category-transport';
    await FinanceStorage.saveInstallmentPlan(
      transaction: group.first,
      totalAmountMinor: 20000,
      installmentCount: 2,
      startDate: DateTime(2026, 9, 1),
      existingInstallments: group,
    );
    expect(
      (await FinanceStorage.getTransaction(refund.uuid))!.categoryUuid,
      'finance-system-category-transport',
    );
    final summary = await FinanceStorage.getSummary(
      from: DateTime(2026, 9),
      to: DateTime(2026, 11),
    );
    expect(summary.expenseByCategory, {
      'finance-system-category-transport': 18000,
    });
  });
}
