@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
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
  });
  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  Future<void> apply(
    String path,
    List<FinanceTransaction> items, {
    required int expectedChanged,
    int expectedSkipped = 0,
  }) async {
    final bundle = {'transactions': items.map((item) => item.toMap()).toList()};
    if (path == 'backup') {
      final result = await FinanceStorage.importBundle(bundle);
      expect(result['updated'], expectedChanged);
      expect(result['skipped'], expectedSkipped);
    } else {
      final deferred = <String>{};
      expect(
        await FinanceStorage.mergeRemoteBundle(
          bundle,
          deferredTransactionUuids: deferred,
        ),
        expectedChanged,
      );
      expect(deferred.length, expectedSkipped);
    }
  }

  for (final path in ['backup', 'remote']) {
    for (final deleted in [false, true]) {
      for (final reverse in [false, true]) {
        test('$path 缩减原单和退款整批恢复，删除退款=$deleted，反序=$reverse', () async {
          final original = FinanceTransaction(
            uuid: 'original',
            amountMinor: 10000,
            transactionDate: '2026-09-01',
            updatedAt: 100,
          );
          final refund = FinanceTransaction(
            uuid: 'refund',
            type: FinanceTransactionType.refund,
            amountMinor: 8000,
            relatedTransactionUuid: original.uuid,
            transactionDate: '2026-09-02',
            updatedAt: 100,
          );
          await db.insert('finance_transactions', original.toMap());
          await db.insert('finance_transactions', refund.toMap());
          original
            ..amountMinor = 5000
            ..updatedAt = 200
            ..version = 2;
          refund
            ..amountMinor = 3000
            ..isDeleted = deleted
            ..updatedAt = 200
            ..version = 2;
          final items = [original, refund];
          await apply(
            path,
            reverse ? items.reversed.toList() : items,
            expectedChanged: 2,
          );
          expect(
            (await FinanceStorage.getTransaction('original'))!.amountMinor,
            5000,
          );
          expect(
            (await FinanceStorage.getTransaction('refund'))!.isDeleted,
            deleted,
          );
          expect(
            await FinanceStorage.getRemainingRefundableMinor(original.uuid),
            deleted ? 5000 : 2000,
          );
        });
      }
    }

    test('$path 同批重新分配两笔退款，先增加的一笔也能恢复', () async {
      final original = FinanceTransaction(
        uuid: 'original',
        amountMinor: 10000,
        transactionDate: '2026-09-01',
        updatedAt: 100,
      );
      final first = FinanceTransaction(
        uuid: 'first',
        type: FinanceTransactionType.refund,
        amountMinor: 2000,
        relatedTransactionUuid: original.uuid,
        transactionDate: '2026-09-02',
        updatedAt: 100,
      );
      final second = FinanceTransaction.fromMap(first.toMap())
        ..uuid = 'second'
        ..amountMinor = 8000;
      for (final item in [original, first, second]) {
        await db.insert('finance_transactions', item.toMap());
      }
      first
        ..amountMinor = 8000
        ..updatedAt = 200
        ..version = 2;
      second
        ..amountMinor = 2000
        ..updatedAt = 200
        ..version = 2;
      await apply(path, [first, second], expectedChanged: 2);
      expect((await FinanceStorage.getTransaction('first'))!.amountMinor, 8000);
      expect(
        (await FinanceStorage.getTransaction('second'))!.amountMinor,
        2000,
      );
      expect(
        await FinanceStorage.getRemainingRefundableMinor(original.uuid),
        0,
      );
    });

    test('$path 过期退款不能为不合法的原单缩减解除约束', () async {
      final original = FinanceTransaction(
        uuid: 'original',
        amountMinor: 10000,
        transactionDate: '2026-09-01',
        updatedAt: 100,
      );
      final refund = FinanceTransaction(
        uuid: 'refund',
        type: FinanceTransactionType.refund,
        amountMinor: 8000,
        relatedTransactionUuid: original.uuid,
        transactionDate: '2026-09-02',
        updatedAt: 300,
        version: 3,
      );
      await db.insert('finance_transactions', original.toMap());
      await db.insert('finance_transactions', refund.toMap());
      original
        ..amountMinor = 5000
        ..updatedAt = 200
        ..version = 2;
      refund
        ..isDeleted = true
        ..updatedAt = 200
        ..version = 2;
      // A stale remote row is ignored rather than treated as deferred.
      await apply(
        path,
        [original, refund],
        expectedChanged: 0,
        expectedSkipped: path == 'backup' ? 2 : 1,
      );
      expect(
        (await FinanceStorage.getTransaction('original'))!.amountMinor,
        10000,
      );
      expect((await FinanceStorage.getTransaction('refund'))!.isDeleted, false);
    });
  }
}
