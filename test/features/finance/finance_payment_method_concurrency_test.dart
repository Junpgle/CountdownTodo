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

  group('付款方式并发编辑', () {
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

    test('本地改图标不覆盖同步后的名称、顺序和归档状态', () async {
      final original = FinancePaymentMethod(
        uuid: 'payment-method-concurrent-edit',
        name: '旧名称',
        icon: '💼',
        sortOrder: 10,
      );
      await FinanceStorage.savePaymentMethod(original);
      final baseline = (await FinanceStorage.getPaymentMethods(
        includeArchived: true,
      )).singleWhere((item) => item.uuid == original.uuid);
      final localEdit = FinancePaymentMethod.fromMap(baseline.toMap())
        ..icon = '💳';
      localEdit.markAsChanged();

      final remoteUpdate = FinancePaymentMethod.fromMap(baseline.toMap())
        ..name = '远端新名称'
        ..sortOrder = 30
        ..isArchived = true
        ..version = baseline.version + 1
        ..updatedAt = localEdit.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'payment_methods': [remoteUpdate.toMap()],
      });

      await expectLater(
        FinanceStorage.savePaymentMethod(localEdit),
        throwsStateError,
      );
      expect(
        (await FinanceStorage.getPaymentMethods(includeArchived: true))
            .singleWhere((item) => item.uuid == original.uuid)
            .name,
        '远端新名称',
      );
      await FinanceStorage.savePaymentMethod(localEdit, original: baseline);

      final saved = (await FinanceStorage.getPaymentMethods(
        includeArchived: true,
      )).singleWhere((item) => item.uuid == original.uuid);
      expect(saved.name, '远端新名称');
      expect(saved.icon, '💳');
      expect(saved.sortOrder, 30);
      expect(saved.isArchived, true);
    });
  });
}
