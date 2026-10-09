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

  group('账单并发编辑', () {
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

    test('旧草稿不会覆盖同步后的账单金额和商家', () async {
      final original = FinanceTransaction(
        uuid: 'transaction-concurrent-edit',
        amountMinor: 10000,
        transactionDate: '2026-10-01',
        merchant: '旧商家',
        note: '旧备注',
      );
      await FinanceStorage.saveTransaction(original);
      final baseline = (await FinanceStorage.getTransaction(original.uuid))!;
      final localEdit = FinanceTransaction.fromMap(baseline.toMap())
        ..note = '本地新备注';
      localEdit.markAsChanged();
      final remoteUpdate = FinanceTransaction.fromMap(baseline.toMap())
        ..amountMinor = 20000
        ..merchant = '远端新商家'
        ..version = baseline.version + 1
        ..updatedAt = localEdit.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'transactions': [remoteUpdate.toMap()],
      });

      await expectLater(
        FinanceStorage.saveTransaction(localEdit),
        throwsStateError,
      );
      await expectLater(
        FinanceStorage.saveTransaction(localEdit, original: baseline),
        throwsStateError,
      );

      final latest = (await FinanceStorage.getTransaction(original.uuid))!;
      expect(latest.amountMinor, 20000);
      expect(latest.merchant, '远端新商家');
      expect(latest.note, '旧备注');
      final refreshedEdit = FinanceTransaction.fromMap(latest.toMap())
        ..note = '本地新备注';
      refreshedEdit.markAsChanged();
      await FinanceStorage.saveTransaction(refreshedEdit, original: latest);

      final saved = (await FinanceStorage.getTransaction(original.uuid))!;
      expect(saved.amountMinor, 20000);
      expect(saved.merchant, '远端新商家');
      expect(saved.note, '本地新备注');
    });
  });
}
