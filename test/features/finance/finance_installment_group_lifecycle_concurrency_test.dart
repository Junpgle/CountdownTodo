@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  group('分期组删除和恢复并发更新', () {
    late Database db;
    late _TransactionGate gate;
    late String groupUuid;
    late FinanceTransaction laterInstallment;

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
      final saved = await FinanceStorage.saveInstallmentPlan(
        transaction: FinanceTransaction(
          uuid: 'lifecycle-installment-root',
          amountMinor: 30000,
          transactionDate: '2026-10-01',
          merchant: '分期商家',
          note: '旧备注',
        ),
        totalAmountMinor: 30000,
        installmentCount: 3,
        startDate: DateTime(2026, 10, 1),
      );
      groupUuid = saved.first.installmentGroupUuid!;
      laterInstallment = saved[1];
    });

    tearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    test('删除和恢复都在事务内保留并发同步字段', () async {
      gate.arm();
      final deleting = FinanceStorage.deleteInstallmentGroup(groupUuid);
      await gate.entered!.future;
      final remoteDuringDelete =
          FinanceTransaction.fromMap(laterInstallment.toMap())
            ..note = '删除期间同步备注'
            ..version = laterInstallment.version + 1
            ..updatedAt = laterInstallment.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [remoteDuringDelete.toMap()],
      });
      gate.released!.complete();
      await deleting;

      var stored = await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      );
      var edited = stored.singleWhere(
        (item) => item.installmentIndex == laterInstallment.installmentIndex,
      );
      expect(edited.isDeleted, true);
      expect(edited.note, '删除期间同步备注');

      laterInstallment = edited;
      gate.arm();
      final restoring = FinanceStorage.restoreInstallmentGroup(groupUuid);
      await gate.entered!.future;
      final remoteDuringRestore =
          FinanceTransaction.fromMap(laterInstallment.toMap())
            ..note = '恢复期间同步备注'
            ..version = laterInstallment.version + 1
            ..updatedAt = laterInstallment.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [remoteDuringRestore.toMap()],
      });
      gate.released!.complete();
      await restoring;

      stored = await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      );
      edited = stored.singleWhere(
        (item) => item.installmentIndex == laterInstallment.installmentIndex,
      );
      expect(edited.isDeleted, false);
      expect(edited.note, '恢复期间同步备注');
    });
  });
}
