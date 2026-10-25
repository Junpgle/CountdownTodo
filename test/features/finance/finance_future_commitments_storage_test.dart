import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_future_commitments_service.dart';
import 'package:countdown_todo/features/finance/services/finance_repository.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('读取已物化周期账单及未来计划不写入财务数据', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'future-commitments-test',
    });
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    FinanceStorage.databaseOverride = db;
    await DatabaseHelper.ensureFinanceSchema(db);
    await FinanceStorage.ensureReady();
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    final rent = FinanceRecurringRule(
      uuid: 'future-storage-rent',
      name: '已生成租金',
      amountMinor: 100000,
      startDate: '2026-01-01',
      dayOfMonth: 25,
      autoGenerate: false,
    );
    await db.insert('finance_recurring_rules', rent.toMap());
    final generatedUuid = FinanceRecurringRule.transactionUuidForPeriod(
      rent.uuid,
      '2026-10',
    );
    await db.insert(
      'finance_transactions',
      FinanceTransaction(
        uuid: generatedUuid,
        amountMinor: rent.amountMinor,
        transactionDate: '2026-10-25',
        source: FinanceEntrySource.automation,
        isDeleted: true,
      ).toMap(),
    );
    final unrelatedUuid = FinanceRecurringRule.transactionUuidForPeriod(
      rent.uuid,
      '2026-09',
    );
    await db.insert(
      'finance_transactions',
      FinanceTransaction(
        uuid: unrelatedUuid,
        amountMinor: rent.amountMinor,
        transactionDate: '2026-09-25',
        source: FinanceEntrySource.automation,
      ).toMap(),
    );
    await db.insert(
      'finance_transactions',
      FinanceTransaction(
        uuid: 'future-storage-manual',
        amountMinor: 1234,
        merchant: '水电账单',
        transactionDate: '2026-11-05',
        source: FinanceEntrySource.manual,
      ).toMap(),
    );
    await db.insert(
      'finance_transactions',
      FinanceTransaction(
        uuid: 'future-storage-deleted',
        amountMinor: 9999,
        transactionDate: '2026-11-06',
        isDeleted: true,
      ).toMap(),
    );

    final loan = FinanceLoan(
      uuid: 'future-storage-loan',
      name: '设备贷款',
      principalMinor: 300000,
      currencyCode: 'USD',
      termMonths: 3,
      startDate: '2026-09-01',
      repaymentDay: 15,
    );
    await db.insert('finance_loans', loan.toMap());
    await db.insert(
      'finance_loan_installments',
      FinanceLoanInstallment(
        uuid: 'future-storage-overdue',
        loanUuid: loan.uuid,
        installmentIndex: 1,
        dueDate: '2026-10-23',
        paymentMinor: 50000,
        principalMinor: 49000,
        interestMinor: 1000,
        remainingPrincipalMinor: 251000,
      ).toMap(),
    );
    await db.insert(
      'finance_loan_installments',
      FinanceLoanInstallment(
        uuid: 'future-storage-upcoming',
        loanUuid: loan.uuid,
        installmentIndex: 2,
        dueDate: '2026-11-15',
        paymentMinor: 50000,
        principalMinor: 49500,
        interestMinor: 500,
        remainingPrincipalMinor: 201500,
      ).toMap(),
    );

    final revision = FinanceStorage.revision.value;
    final existing = await FinanceRepository.getExistingTransactionUuids([
      generatedUuid,
      unrelatedUuid,
      'not-in-database',
    ]);
    final forecast = await FinanceFutureCommitmentsService.read(
      now: DateTime(2026, 10, 24, 18),
      horizonMonths: 3,
    );

    expect(existing, {generatedUuid, unrelatedUuid});
    expect(
      forecast.commitments.any(
        (item) => item.id == 'recurring:${rent.uuid}:2026-10',
      ),
      isFalse,
    );
    expect(
      forecast.commitments.any(
        (item) => item.id == 'loan:future-storage-upcoming',
      ),
      isTrue,
    );
    expect(
      forecast.commitments.any(
        (item) => item.id == 'transaction:future-storage-manual',
      ),
      isTrue,
    );
    expect(
      forecast.commitments.any(
        (item) => item.id == 'transaction:future-storage-deleted',
      ),
      isFalse,
    );
    expect(
      forecast.overdueLoanInstallments.single.id,
      'loan:future-storage-overdue',
    );
    expect(FinanceStorage.revision.value, revision);
  });
}
