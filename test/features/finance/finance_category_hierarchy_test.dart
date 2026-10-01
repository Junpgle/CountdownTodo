@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_catalog_editor.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late FinanceCategory root;
  late FinanceCategory other;
  late FinanceCategory child;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    root = FinanceCategory(uuid: 'root', name: '大类');
    other = FinanceCategory(uuid: 'other', name: '另一个大类');
    child = FinanceCategory(uuid: 'child', name: '细分类', parentUuid: root.uuid);
    for (final category in [root, other, child]) {
      await FinanceStorage.saveCategory(category);
    }
  });
  tearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });

  for (final archived in [false, true]) {
    test('带二级分类的大类不能变成二级分类，已归档子类=$archived', () async {
      if (archived) await FinanceStorage.archiveCategory(child.uuid);
      root.parentUuid = other.uuid;
      await expectLater(FinanceStorage.saveCategory(root), throwsArgumentError);
      final rows = await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [root.uuid],
      );
      expect(rows.single['parent_uuid'], isNull);
    });
  }

  test('移走子类后可以改层级，普通子类可以换一级大类', () async {
    child.parentUuid = other.uuid;
    await FinanceStorage.saveCategory(child);
    root.parentUuid = other.uuid;
    await FinanceStorage.saveCategory(root);
    expect(
      (await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [root.uuid],
      )).single['parent_uuid'],
      other.uuid,
    );
  });

  for (final hasChildren in [false, true]) {
    testWidgets('编辑分类上级选择正确锁定，含二级分类=$hasChildren', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinanceCatalogEditor(
              initialName: root.name,
              initialIcon: root.icon,
              categoryType: root.type,
              isEditing: true,
              editingCategoryUuid: root.uuid,
              availableParents: [root, other, if (hasChildren) child],
              onSave: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('finance-catalog-parent')),
      );
      expect(field.onChanged == null, hasChildren);
      if (hasChildren) {
        expect(find.text('已有二级分类，请先移动二级分类后再调整上级'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
