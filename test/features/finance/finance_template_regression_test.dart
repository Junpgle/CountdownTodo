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

  group('快捷模板并发保存', () {
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

    test('编辑器打开期间的同步字段更新与本地编辑都能保留', () async {
      final original = FinanceEntryTemplate(
        uuid: 'template-concurrent-edit',
        name: '旧名称',
        amountMinor: 10000,
        note: '旧备注',
      );
      await FinanceStorage.saveTemplate(original);
      final baseline = (await FinanceStorage.getTemplate(original.uuid))!;

      final localEdit = FinanceEntryTemplate.fromMap(baseline.toMap())
        ..note = '本地新备注';
      localEdit.markAsChanged();

      final remoteUpdate = FinanceEntryTemplate.fromMap(baseline.toMap())
        ..name = '远端新名称'
        ..amountMinor = 20000
        ..useCount = 3
        ..lastUsedAt = 9000
        ..version = baseline.version + 1
        ..updatedAt = localEdit.updatedAt + 1000;
      await FinanceStorage.mergeRemoteBundle({
        'templates': [remoteUpdate.toMap()],
      });

      await expectLater(
        FinanceStorage.saveTemplate(localEdit),
        throwsStateError,
      );
      expect((await FinanceStorage.getTemplate(original.uuid))!.name, '远端新名称');
      await FinanceStorage.saveTemplate(localEdit, original: baseline);

      final saved = (await FinanceStorage.getTemplate(original.uuid))!;
      expect(saved.name, '远端新名称');
      expect(saved.amountMinor, 20000);
      expect(saved.note, '本地新备注');
      expect(saved.useCount, 3);
      expect(saved.lastUsedAt, 9000);
    });
  });
}
