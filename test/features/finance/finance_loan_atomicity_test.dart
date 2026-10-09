@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Delay the next transaction before it acquires SQLite's lock, so a competing
// repayment can finish first. All SQL still executes against real SQLite.
class _TransactionGate implements Database {
  _TransactionGate(this.inner);

  final Database inner;
  Completer<void>? entered;
  Completer<void>? released;

  void arm() {
    entered = Completer<void>();
    released = Completer<void>();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    if (entered != null && !entered!.isCompleted) {
      entered!.complete();
      await released!.future;
    }
    return inner.transaction(action, exclusive: exclusive);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      inner.rawUpdate(sql, arguments);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected database access: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late _TransactionGate gate;
  late FinanceLoan loan;
  late FinanceLoanInstallment installment;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    gate = _TransactionGate(db);
    FinanceStorage.databaseOverride = gate;
    await FinanceStorage.ensureReady();
    loan = FinanceLoan(
      uuid: 'loan',
      name: '原贷款',
      principalMinor: 10000,
      annualInterestRateBps: 1200,
      termMonths: 1,
      startDate: '2026-09-01',
      repaymentDay: 1,
    );
    await FinanceStorage.saveLoan(loan);
    installment = (await FinanceStorage.getLoanInstallments(loan.uuid)).single;
  });
  tearDown(() async {
    if (gate.released != null && !gate.released!.isCompleted) {
      gate.released!.complete();
    }
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  Future<void> pay() => FinanceStorage.setLoanInstallmentPaid(
    installment.uuid,
    true,
    paymentMethodUuid: 'finance-system-payment-cash',
    paidAt: DateTime.now().subtract(const Duration(hours: 1)),
  );

  for (final delete in [false, true]) {
    test('${delete ? "删除" : "编辑名称"}贷款和还款交错，保留实际扣款及利息关联', () async {
      loan.name = '新贷款名称';
      gate.arm();
      final operation = delete
          ? FinanceStorage.deleteLoan(loan.uuid)
          : FinanceStorage.saveLoan(loan);
      await gate.entered!.future;
      await pay();
      final paid = (await FinanceStorage.getLoanInstallment(installment.uuid))!;
      gate.released!.complete();
      await operation;
      final stored = (await FinanceStorage.getLoanInstallment(
        installment.uuid,
        includeDeleted: true,
      ))!;
      expect(stored.isPaid, true);
      expect(stored.paidAt, paid.paidAt);
      expect(stored.paymentMethodUuid, paid.paymentMethodUuid);
      expect(stored.interestTransactionUuid, paid.interestTransactionUuid);
      expect(stored.version, greaterThan(paid.version));
      expect(stored.isDeleted, delete);
    });
  }

  test('改本金保存前刚完成还款，拒绝重算并保留已还金额', () async {
    loan.principalMinor = 20000;
    gate.arm();
    final operation = FinanceStorage.saveLoan(loan);
    // Attach the expected error before releasing the competing operation.
    final assertion = expectLater(operation, throwsStateError);
    await gate.entered!.future;
    await pay();
    gate.released!.complete();
    await assertion;
    expect((await FinanceStorage.getLoan(loan.uuid))!.principalMinor, 10000);
    expect(
      (await FinanceStorage.getLoanInstallment(installment.uuid))!.isPaid,
      true,
    );
  });

  test('恢复贷款时保留同期同步到的还款撤销，不能恢复旧扣款状态', () async {
    await pay();
    await FinanceStorage.deleteLoan(loan.uuid);
    final canceled =
        (await FinanceStorage.getLoanInstallment(
            installment.uuid,
            includeDeleted: true,
          ))!
          ..isPaid = false
          ..paidAt = null
          ..paymentMethodUuid = null
          ..updatedAt += 10000
          ..version += 1;
    gate.arm();
    final operation = FinanceStorage.restoreLoan(loan.uuid);
    await gate.entered!.future;
    await FinanceStorage.mergeRemoteBundle({
      'loan_installments': [canceled.toMap()],
    });
    gate.released!.complete();
    await operation;
    final stored = (await FinanceStorage.getLoanInstallment(installment.uuid))!;
    expect(stored.isPaid, false);
    expect(stored.paidAt, isNull);
    expect(stored.paymentMethodUuid, isNull);
    expect(stored.version, greaterThan(canceled.version));
  });
}
