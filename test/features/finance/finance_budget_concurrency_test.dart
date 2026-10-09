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

  group('预算并发编辑', () {
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

    test('本地改备注时保留同步后的预算金额', () async {
      final original = FinanceBudget(
        uuid: 'budget-concurrent-edit',
        monthKey: '2026-10',
        categoryUuid: 'finance-system-category-food',
        amountMinor: 10000,
        note: '旧备注',
      );
      await FinanceStorage.saveBudget(original);
      final baseline = (await FinanceStorage.getBudget(original.uuid))!;
      final localEdit = FinanceBudget.fromMap(baseline.toMap())..note = '本地新备注';
      localEdit.markAsChanged();
      final remoteUpdate = FinanceBudget.fromMap(baseline.toMap())
        ..amountMinor = 20000
        ..note = '远端新备注'
        ..version = baseline.version + 1
        ..updatedAt = localEdit.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [remoteUpdate.toMap()],
      });

      await expectLater(FinanceStorage.saveBudget(localEdit), throwsStateError);
      expect(
        (await FinanceStorage.getBudget(baseline.uuid))!.amountMinor,
        20000,
      );
      await FinanceStorage.saveBudget(localEdit, original: baseline);

      final saved = (await FinanceStorage.getBudget(baseline.uuid))!;
      expect(saved.amountMinor, 20000);
      expect(saved.note, '本地新备注');
    });

    test('本地仅改余额备注时保留同步金额及其对应时间', () async {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month);
      final original = FinanceBudget(
        uuid: 'balance-concurrent-edit',
        monthKey: financeMonthKey(now),
        paymentMethodUuid: 'finance-system-payment-cash',
        amountMinor: 10000,
        note: '旧备注',
        balanceSnapshotAt: monthStart.millisecondsSinceEpoch,
      );
      await FinanceStorage.saveBudget(
        original,
        balanceSnapshotAt: original.balanceSnapshotAt,
      );
      final baseline = (await FinanceStorage.getBudget(original.uuid))!;
      final localEdit = FinanceBudget.fromMap(baseline.toMap())..note = '本地新备注';
      localEdit.markAsChanged();
      final remoteSnapshotAt = DateTime.now().millisecondsSinceEpoch;
      final remoteUpdate = FinanceBudget.fromMap(baseline.toMap())
        ..amountMinor = 25000
        ..balanceSnapshotAt = remoteSnapshotAt
        ..version = baseline.version + 1
        ..updatedAt = localEdit.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'budgets': [remoteUpdate.toMap()],
      });

      await expectLater(FinanceStorage.saveBudget(localEdit), throwsStateError);
      await FinanceStorage.saveBudget(localEdit, original: baseline);

      final saved = (await FinanceStorage.getBudget(baseline.uuid))!;
      expect(saved.amountMinor, 25000);
      expect(saved.note, '本地新备注');
      expect(saved.balanceSnapshotAt, remoteSnapshotAt);
    });
  });
}
