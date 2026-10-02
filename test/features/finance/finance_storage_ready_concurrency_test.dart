@TestOn('vm')
library;

import 'dart:async';

import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RefundMigrationGate implements Database {
  _RefundMigrationGate(this.inner);

  final Database inner;
  final migrationEntered = Completer<void>();
  final migrationRelease = Completer<void>();

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('UPDATE finance_transactions')) {
      migrationEntered.complete();
      await migrationRelease.future;
    }
    return inner.rawUpdate(sql, arguments);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => inner.transaction(action, exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected database access: ${invocation.memberName}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('并发 ensureReady 等待旧退款分类迁移结束', () async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-ready-concurrency-test',
    });
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    await db.insert('finance_transactions', {
      'uuid': 'legacy-refund-ready-race',
      'type': 'refund',
      'amount_minor': 1200,
      'currency_code': 'CNY',
      'category_uuid': 'finance-system-category-salary',
      'transaction_date': '2026-01-01',
      'timezone_offset_minutes': 480,
      'source': 'manual',
      'is_deleted': 0,
      'version': 1,
      'created_at': 10,
      'updated_at': 10,
      'pending_sync': 0,
    });

    final gate = _RefundMigrationGate(db);
    FinanceStorage.databaseOverride = gate;
    final firstReady = FinanceStorage.ensureReady();
    await gate.migrationEntered.future.timeout(const Duration(seconds: 3));

    var secondCompleted = false;
    final secondReady = FinanceStorage.ensureReady().then((_) {
      secondCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);
    final completedBeforeMigration = secondCompleted;

    gate.migrationRelease.complete();
    await Future.wait([firstReady, secondReady]);
    expect(completedBeforeMigration, isFalse);
    final row = (await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: ['legacy-refund-ready-race'],
      limit: 1,
    )).single;
    expect(row['category_uuid'], 'finance-system-category-refund');
  });
}
