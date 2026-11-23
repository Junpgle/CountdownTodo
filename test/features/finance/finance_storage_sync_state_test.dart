@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'current_login_user': 'finance-pending-test',
    });
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
  });

  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  FinanceTransaction transaction({
    required String uuid,
    required int updatedAt,
    int version = 1,
  }) => FinanceTransaction(
    uuid: uuid,
    amountMinor: 1200,
    transactionDate: '2026-08-27',
    version: version,
    createdAt: 10,
    updatedAt: updatedAt,
  );

  test('本地写入会设置 pending_sync', () async {
    await FinanceStorage.saveTransaction(
      transaction(uuid: 'pending-tx', updatedAt: 10),
    );

    final rows = await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: ['pending-tx'],
    );
    expect(rows.single['pending_sync'], 1);
  });

  test('服务端确认只清除请求快照对应的本地版本', () async {
    final original = transaction(uuid: 'ack-tx', updatedAt: 10);
    await FinanceStorage.saveTransaction(original);

    final acknowledged = await FinanceStorage.acknowledgePendingChanges(
      {
        'finance_transactions_changes': [
          {...original.toMap(), 'pending_sync': 1},
        ],
      },
      [
        {
          'table': 'transactions',
          'uuid': original.uuid,
          'updated_at': 20,
          'version': 2,
        },
      ],
    );

    expect(acknowledged, 1);
    final rows = await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: [original.uuid],
    );
    expect(rows.single['pending_sync'], 0);
    expect(rows.single['updated_at'], 20);
    expect(rows.single['version'], 2);

    final edited = transaction(uuid: original.uuid, updatedAt: 30, version: 3);
    await FinanceStorage.saveTransaction(edited);
    final staleAcknowledged = await FinanceStorage.acknowledgePendingChanges(
      {
        'finance_transactions_changes': [
          {...original.toMap(), 'pending_sync': 1},
        ],
      },
      [
        {
          'table': 'transactions',
          'uuid': original.uuid,
          'updated_at': 20,
          'version': 2,
        },
      ],
    );
    expect(staleAcknowledged, 0);
    final editedRows = await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: [original.uuid],
    );
    expect(editedRows.single['pending_sync'], 1);
  });

  test('远端胜出版本合并后不会再次成为本地 pending', () async {
    final local = transaction(uuid: 'remote-winner', updatedAt: 10);
    await FinanceStorage.saveTransaction(local);

    await FinanceStorage.mergeRemoteBundle({
      'transactions': [
        {...local.toMap(), 'updated_at': 20, 'version': 2},
      ],
    });

    final rows = await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: [local.uuid],
    );
    expect(rows.single['pending_sync'], 0);
    expect(rows.single['updated_at'], 20);
  });

  test('不完整的服务端确认不会清除 pending', () async {
    final local = transaction(uuid: 'incomplete-ack', updatedAt: 10);
    await FinanceStorage.saveTransaction(local);

    final acknowledged = await FinanceStorage.acknowledgePendingChanges(
      {
        'finance_transactions_changes': [
          {...local.toMap(), 'pending_sync': 1},
        ],
      },
      [
        {'table': 'transactions', 'uuid': local.uuid},
      ],
    );

    expect(acknowledged, 0);
    final rows = await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: [local.uuid],
    );
    expect(rows.single['pending_sync'], 1);
  });

  test('远端互转记录在合并及恢复旧版软删除投影时可正常入库', () async {
    final legacyDeleted = FinanceTransaction(
      uuid: 'transfer-restore-tx',
      type: FinanceTransactionType.expense,
      amountMinor: 5000,
      paymentMethodUuid: 'pm-bank',
      transactionDate: '2026-10-12',
      version: 2,
      createdAt: 10,
      updatedAt: 20,
      isDeleted: true,
    ).toMap();
    await FinanceStorage.mergeRemoteBundle({
      'transactions': [legacyDeleted],
    });

    final restored = await FinanceStorage.mergeRemoteBundle({
      'transactions': [
        {
          ...legacyDeleted,
          'type': 'transfer',
          'target_payment_method_uuid': 'pm-campus',
          'is_deleted': false,
        },
      ],
    });

    expect(restored, 1);
    final rows = await db.query(
      'finance_transactions',
      where: 'uuid = ?',
      whereArgs: ['transfer-restore-tx'],
    );
    expect(rows.single['type'], 'transfer');
    expect(rows.single['target_payment_method_uuid'], 'pm-campus');
    expect(rows.single['is_deleted'], 0);
  });
}
