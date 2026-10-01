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

  group('贷款编辑并发保存', () {
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

    test('本地备注与远端贷款字段更新合并，计划按最终本金生成', () async {
      final original = FinanceLoan(
        uuid: 'loan-concurrent-edit',
        name: '旧名称',
        principalMinor: 240000,
        termMonths: 12,
        startDate: '2026-01-01',
        repaymentDay: 1,
        note: '旧备注',
      );
      await FinanceStorage.saveLoan(original);
      final baseline = (await FinanceStorage.getLoan(original.uuid))!;
      final localEdit = FinanceLoan.fromMap(baseline.toMap())..note = '本地新备注';

      final remoteUpdate = FinanceLoan.fromMap(baseline.toMap())
        ..name = '远端新名称'
        ..principalMinor = 480000
        ..version = baseline.version + 1
        ..updatedAt = baseline.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'loans': [remoteUpdate.toMap()],
      });

      await expectLater(FinanceStorage.saveLoan(localEdit), throwsStateError);
      expect((await FinanceStorage.getLoan(original.uuid))!.name, '远端新名称');
      await FinanceStorage.saveLoan(localEdit, original: baseline);

      final saved = (await FinanceStorage.getLoan(original.uuid))!;
      expect(saved.name, '远端新名称');
      expect(saved.principalMinor, 480000);
      expect(saved.note, '本地新备注');
      final installments = await FinanceStorage.getLoanInstallments(
        original.uuid,
      );
      expect(
        installments.fold<int>(0, (sum, item) => sum + item.principalMinor),
        480000,
      );
    });

    test('编辑期间同步删除贷款时拒绝保存，不会重新激活还款计划', () async {
      final original = FinanceLoan(
        uuid: 'loan-concurrent-delete',
        name: '待归档贷款',
        principalMinor: 240000,
        termMonths: 12,
        startDate: '2026-01-01',
        repaymentDay: 1,
      );
      await FinanceStorage.saveLoan(original);
      final baseline = (await FinanceStorage.getLoan(original.uuid))!;
      final localEdit = FinanceLoan.fromMap(baseline.toMap())..note = '编辑中的备注';
      final remoteDelete = FinanceLoan.fromMap(baseline.toMap())
        ..isDeleted = true
        ..version = baseline.version + 1
        ..updatedAt = baseline.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'loans': [remoteDelete.toMap()],
      });

      await expectLater(
        FinanceStorage.saveLoan(localEdit, original: baseline),
        throwsStateError,
      );

      expect(
        (await FinanceStorage.getLoan(
          original.uuid,
          includeDeleted: true,
        ))!.isDeleted,
        true,
      );
      expect(
        (await FinanceStorage.getLoanInstallments(original.uuid)).length,
        12,
      );
    });
  });
}
