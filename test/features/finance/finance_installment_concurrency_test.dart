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

  group('分期组并发编辑', () {
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

    test('任一期在编辑期间同步更新后拒绝用旧整组覆盖', () async {
      final original = FinanceTransaction(
        uuid: 'installment-concurrent-edit',
        amountMinor: 30000,
        transactionDate: '2026-10-01',
        merchant: '整组商家',
        note: '旧备注',
      );
      final saved = await FinanceStorage.saveInstallmentPlan(
        transaction: original,
        totalAmountMinor: 30000,
        installmentCount: 3,
        startDate: DateTime(2026, 10, 1),
      );
      final groupUuid = saved.first.installmentGroupUuid!;
      final baseline = await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      );
      final localEdit = FinanceTransaction.fromMap(baseline.first.toMap())
        ..note = '本地新备注';
      localEdit.markAsChanged();
      final remoteUpdates = baseline
          .map(
            (item) => FinanceTransaction.fromMap(item.toMap())
              ..note = '远端新备注'
              ..version = item.version + 1
              ..updatedAt = localEdit.updatedAt + 1000,
          )
          .toList();
      await FinanceStorage.mergeRemoteBundle({
        'transactions': remoteUpdates.map((item) => item.toMap()).toList(),
      });

      await expectLater(
        FinanceStorage.saveInstallmentPlan(
          transaction: localEdit,
          original: baseline.first,
          totalAmountMinor: 30000,
          installmentCount: 3,
          startDate: DateTime(2026, 10, 1),
          existingInstallments: baseline,
        ),
        throwsStateError,
      );

      final current = await FinanceStorage.getInstallmentGroup(
        groupUuid,
        includeDeleted: true,
      );
      expect(
        current,
        everyElement(
          predicate<FinanceTransaction>((item) => item.note == '远端新备注'),
        ),
      );

      final latestRoot = current.firstWhere(
        (item) => item.installmentIndex == 1,
      );
      final refreshedEdit = FinanceTransaction.fromMap(latestRoot.toMap())
        ..note = '本地新备注';
      refreshedEdit.markAsChanged();
      await FinanceStorage.saveInstallmentPlan(
        transaction: refreshedEdit,
        original: latestRoot,
        totalAmountMinor: 30000,
        installmentCount: 3,
        startDate: DateTime(2026, 10, 1),
        existingInstallments: current,
      );
      expect(
        await FinanceStorage.getInstallmentGroup(groupUuid),
        everyElement(
          predicate<FinanceTransaction>((item) => item.note == '本地新备注'),
        ),
      );
    });
  });
}
