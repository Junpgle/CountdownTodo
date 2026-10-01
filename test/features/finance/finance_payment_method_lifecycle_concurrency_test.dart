@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _OperationGate implements Database {
  _OperationGate(this.inner);

  final Database inner;
  Completer<void>? entered;
  Completer<void>? released;
  bool armed = false;

  void arm() {
    entered = Completer<void>();
    released = Completer<void>();
    armed = true;
  }

  Future<void> _pauseIfArmed() async {
    if (!armed) return;
    armed = false;
    entered!.complete();
    await released!.future;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    await _pauseIfArmed();
    return inner.transaction(action, exclusive: exclusive);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      inner.rawUpdate(sql, arguments);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

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
  }) async {
    final rows = await inner.query(
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
    if (table == 'finance_payment_methods') await _pauseIfArmed();
    return rows;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected database access: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('付款方式归档并发同步', () {
    late Database db;
    late _OperationGate gate;
    const methodUuid = 'payment-method-lifecycle-sync';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await DatabaseHelper.ensureFinanceSchema(db);
      gate = _OperationGate(db);
      FinanceStorage.databaseOverride = gate;
      await FinanceStorage.ensureReady();
      await FinanceStorage.savePaymentMethod(
        FinancePaymentMethod(uuid: methodUuid, name: '本地账户', sortOrder: 10),
      );
    });

    tearDown(() async {
      if (gate.released != null && !gate.released!.isCompleted) {
        gate.released!.complete();
      }
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    test('归档和取消归档均保留交错到达的同步名称', () async {
      var current = (await FinanceStorage.getPaymentMethods(
        includeArchived: true,
      )).singleWhere((item) => item.uuid == methodUuid);

      gate.arm();
      final archiving = FinanceStorage.archivePaymentMethod(methodUuid);
      await gate.entered!.future;
      final remoteDuringArchive = FinancePaymentMethod.fromMap(current.toMap())
        ..name = '归档期间同步名称'
        ..version = current.version + 1
        ..updatedAt = current.updatedAt + 10000;
      await FinanceStorage.mergeRemoteBundle({
        'payment_methods': [remoteDuringArchive.toMap()],
      });
      gate.released!.complete();
      await archiving;

      current = (await FinanceStorage.getPaymentMethods(includeArchived: true))
          .singleWhere((item) => item.uuid == methodUuid);
      expect(current.isArchived, true);
      expect(current.name, '归档期间同步名称');

      gate.arm();
      final unarchiving = FinanceStorage.unarchivePaymentMethod(methodUuid);
      await gate.entered!.future;
      final remoteDuringUnarchive =
          FinancePaymentMethod.fromMap(current.toMap())
            ..name = '取消归档期间同步名称'
            ..version = current.version + 1
            ..updatedAt = current.updatedAt + 10000;
      await FinanceStorage.mergeRemoteBundle({
        'payment_methods': [remoteDuringUnarchive.toMap()],
      });
      gate.released!.complete();
      await unarchiving;

      current = (await FinanceStorage.getPaymentMethods(includeArchived: true))
          .singleWhere((item) => item.uuid == methodUuid);
      expect(current.isArchived, false);
      expect(current.name, '取消归档期间同步名称');
    });
  });
}
