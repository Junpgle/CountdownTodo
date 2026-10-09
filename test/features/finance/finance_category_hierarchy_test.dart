@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_category_detail_screen.dart';
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

  test('同步合并拒绝伪造的内置分类 UUID', () async {
    final fakeSystemCategory = FinanceCategory(
      uuid: 'finance-system-category-fake',
      name: '伪造系统分类',
      isSystem: true,
      nameCustomized: true,
    );

    expect(
      await FinanceStorage.mergeRemoteBundle({
        'categories': [fakeSystemCategory.toMap()],
      }),
      0,
    );
    expect(
      await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [fakeSystemCategory.uuid],
      ),
      isEmpty,
    );
  });

  testWidgets('未分类净额为负时仍显示并打开账单明细', (tester) async {
    final transactions = [
      FinanceTransaction(
        uuid: 'uncategorized-expense',
        amountMinor: 1000,
        transactionDate: '2026-10-01',
        categoryUuid: null,
      ),
      FinanceTransaction(
        uuid: 'uncategorized-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 1500,
        transactionDate: '2026-10-02',
        categoryUuid: null,
      ),
    ];
    String? selectedCategoryUuid;
    List<FinanceTransaction>? selectedTransactions;

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceCategoryDetailScreen(
          periodTitle: '2026年10月',
          rootCategoryUuid: null,
          transactions: transactions,
          categories: const {},
          onCategorySelected: (categoryUuid, _, periodTransactions) async {
            selectedCategoryUuid = categoryUuid;
            selectedTransactions = periodTransactions;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 笔账单 · 点击查看'), findsOneWidget);
    expect(find.text('没有可筛选的分类账单'), findsNothing);
    await tester.tap(
      find.byKey(
        ValueKey(
          'finance-category-detail-$financeUncategorizedCategoryFilterUuid',
        ),
      ),
    );
    await tester.pump();

    expect(selectedCategoryUuid, financeUncategorizedCategoryFilterUuid);
    expect(selectedTransactions, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前页展开分类时只展示对应支出和退款明细', (tester) async {
    final transactions = [
      FinanceTransaction(
        uuid: 'detail-expense',
        amountMinor: 1200,
        transactionDate: '2026-10-01',
        merchant: '奶茶店',
        categoryUuid: child.uuid,
      ),
      FinanceTransaction(
        uuid: 'detail-refund',
        type: FinanceTransactionType.refund,
        amountMinor: 200,
        transactionDate: '2026-10-02',
        note: '退款',
        categoryUuid: child.uuid,
      ),
      FinanceTransaction(
        uuid: 'other-child-expense',
        amountMinor: 800,
        transactionDate: '2026-10-03',
        merchant: '咖啡店',
        categoryUuid: 'coffee',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceCategoryDetailScreen(
          periodTitle: '2026年10月',
          rootCategoryUuid: root.uuid,
          categoryTapOpensLedger: false,
          transactions: transactions,
          categories: {
            root.uuid: root,
            child.uuid: child,
            'coffee': FinanceCategory(
              uuid: 'coffee',
              name: '咖啡',
              parentUuid: root.uuid,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('finance-category-detail-${child.uuid}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('奶茶店'), findsOneWidget);
    expect(find.text('退款'), findsOneWidget);
    expect(find.text('咖啡店'), findsNothing);
    expect(find.text('+¥2.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  test('从已归档分类中恢复二级分类时同时恢复所属大类', () async {
    await FinanceStorage.archiveCategory(root.uuid);

    await FinanceStorage.unarchiveCategory(child.uuid);

    final rows = await db.query(
      'finance_categories',
      where: 'uuid IN (?, ?)',
      whereArgs: [root.uuid, child.uuid],
    );
    final archivedByUuid = {
      for (final row in rows) row['uuid'] as String: row['is_archived'] as int,
    };
    expect(archivedByUuid[root.uuid], 0);
    expect(archivedByUuid[child.uuid], 0);
  });

  test('恢复大类只恢复级联归档的细分类', () async {
    final previouslyArchivedChild = FinanceCategory(
      uuid: 'previously-archived-child',
      name: '此前归档的小类',
      parentUuid: root.uuid,
    );
    final cascadedChild = FinanceCategory(
      uuid: 'cascaded-child',
      name: '随大类归档的小类',
      parentUuid: root.uuid,
    );
    await FinanceStorage.saveCategory(previouslyArchivedChild);
    await FinanceStorage.saveCategory(cascadedChild);
    await FinanceStorage.archiveCategory(child.uuid);
    await FinanceStorage.archiveCategory(previouslyArchivedChild.uuid);
    await FinanceStorage.archiveCategory(root.uuid);

    expect(await FinanceStorage.unarchiveCategory(root.uuid), isTrue);

    final rows = await db.query(
      'finance_categories',
      where: 'uuid IN (?, ?, ?, ?)',
      whereArgs: [
        root.uuid,
        child.uuid,
        previouslyArchivedChild.uuid,
        cascadedChild.uuid,
      ],
    );
    final archivedByUuid = {
      for (final row in rows) row['uuid'] as String: row['is_archived'] as int,
    };
    expect(archivedByUuid[root.uuid], 0);
    expect(archivedByUuid[child.uuid], 1);
    expect(archivedByUuid[previouslyArchivedChild.uuid], 1);
    expect(archivedByUuid[cascadedChild.uuid], 0);
  });

  test('从细分类入口恢复时不恢复此前单独归档的其他小类', () async {
    final previouslyArchivedSibling = FinanceCategory(
      uuid: 'previously-archived-sibling',
      name: '此前归档的另一小类',
      parentUuid: root.uuid,
    );
    await FinanceStorage.saveCategory(previouslyArchivedSibling);
    await FinanceStorage.archiveCategory(child.uuid);
    await FinanceStorage.archiveCategory(previouslyArchivedSibling.uuid);
    await FinanceStorage.archiveCategory(root.uuid);

    expect(await FinanceStorage.unarchiveCategory(child.uuid), isTrue);

    final rows = await db.query(
      'finance_categories',
      where: 'uuid IN (?, ?, ?)',
      whereArgs: [root.uuid, child.uuid, previouslyArchivedSibling.uuid],
    );
    final archivedByUuid = {
      for (final row in rows) row['uuid'] as String: row['is_archived'] as int,
    };
    expect(archivedByUuid[root.uuid], 0);
    expect(archivedByUuid[child.uuid], 0);
    expect(archivedByUuid[previouslyArchivedSibling.uuid], 1);
  });

  test('旧数据中父类已归档的活跃小类不会进入可用列表，并可从子类入口修复', () async {
    await db.update(
      'finance_categories',
      {'is_archived': 1},
      where: 'uuid = ?',
      whereArgs: [root.uuid],
    );

    final activeCategories = await FinanceStorage.getCategories();
    expect(activeCategories.any((item) => item.uuid == child.uuid), isFalse);
    expect(await FinanceStorage.unarchiveCategory(child.uuid), isTrue);

    final rows = await db.query(
      'finance_categories',
      where: 'uuid IN (?, ?)',
      whereArgs: [root.uuid, child.uuid],
    );
    expect(rows.every((row) => row['is_archived'] == 0), isTrue);
  });

  test('不能在已归档大类下保存活跃二级分类', () async {
    await FinanceStorage.archiveCategory(root.uuid);
    final archivedParentChild = FinanceCategory(
      uuid: 'child-under-archived-root',
      name: '归档父类下的新小类',
      parentUuid: root.uuid,
    );

    await expectLater(
      FinanceStorage.saveCategory(archivedParentChild),
      throwsArgumentError,
    );
    expect(
      await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [archivedParentChild.uuid],
      ),
      isEmpty,
    );
  });

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

  test('编辑分类图标时保留同步到的名称排序和归档状态', () async {
    final baseline = FinanceCategory.fromMap(child.toMap());
    final localEdit = FinanceCategory.fromMap(baseline.toMap())..icon = '🧾';
    localEdit.markAsChanged();
    final remoteUpdate = FinanceCategory.fromMap(baseline.toMap())
      ..name = '远端分类名称'
      ..sortOrder = 90
      ..isArchived = true;
    remoteUpdate.markAsChanged();
    await FinanceStorage.saveCategory(remoteUpdate);

    await FinanceStorage.saveCategory(localEdit, original: baseline);

    final saved = (await FinanceStorage.getCategories(includeArchived: true))
        .singleWhere((item) => item.uuid == child.uuid);
    expect(saved.name, '远端分类名称');
    expect(saved.icon, '🧾');
    expect(saved.sortOrder, 90);
    expect(saved.isArchived, true);
  });

  for (final remote in [false, true]) {
    for (final reverse in [false, true]) {
      test('分类批量写入拒绝三级层级，云端=$remote，反序=$reverse', () async {
        final importedRoot = FinanceCategory(
          uuid: 'batch-root-$remote-$reverse',
          name: '批量大类',
        );
        final importedChild = FinanceCategory(
          uuid: 'batch-child-$remote-$reverse',
          name: '批量小类',
          parentUuid: importedRoot.uuid,
        );
        final importedGrandchild = FinanceCategory(
          uuid: 'batch-grandchild-$remote-$reverse',
          name: '批量三级分类',
          parentUuid: importedChild.uuid,
        );
        final rows = [
          importedGrandchild.toMap(),
          importedChild.toMap(),
          importedRoot.toMap(),
        ];
        final categories = reverse ? rows.reversed.toList() : rows;

        if (remote) {
          expect(
            await FinanceStorage.mergeRemoteBundle({'categories': categories}),
            2,
          );
        } else {
          expect(
            await FinanceStorage.importBundle({'categories': categories}),
            {'imported': 2, 'updated': 0, 'skipped': 1},
          );
        }

        final stored = await db.query(
          'finance_categories',
          where: 'uuid IN (?, ?, ?)',
          whereArgs: [
            importedRoot.uuid,
            importedChild.uuid,
            importedGrandchild.uuid,
          ],
        );
        expect(stored.map((row) => row['uuid']), contains(importedRoot.uuid));
        expect(stored.map((row) => row['uuid']), contains(importedChild.uuid));
        expect(
          stored.map((row) => row['uuid']),
          isNot(contains(importedGrandchild.uuid)),
        );
      });
    }
  }

  for (final remote in [false, true]) {
    test('分类批量写入拒绝活跃子类挂在归档大类下，云端=$remote', () async {
      final archivedRoot = FinanceCategory(
        uuid: 'archived-root-$remote',
        name: '已归档大类',
        isArchived: true,
      );
      final activeChild = FinanceCategory(
        uuid: 'active-child-$remote',
        name: '不应活跃的小类',
        parentUuid: archivedRoot.uuid,
      );
      final categories = [activeChild.toMap(), archivedRoot.toMap()];

      if (remote) {
        expect(
          await FinanceStorage.mergeRemoteBundle({'categories': categories}),
          1,
        );
      } else {
        expect(await FinanceStorage.importBundle({'categories': categories}), {
          'imported': 1,
          'updated': 0,
          'skipped': 1,
        });
      }

      final rows = await db.query(
        'finance_categories',
        where: 'uuid IN (?, ?)',
        whereArgs: [archivedRoot.uuid, activeChild.uuid],
      );
      expect(rows, hasLength(1));
      expect(rows.single['uuid'], archivedRoot.uuid);
      expect(rows.single['is_archived'], 1);
    });
  }

  for (final remote in [false, true]) {
    test('批量写入不能把仍有子类的大类移到另一个大类下，云端=$remote', () async {
      final movedRoot = FinanceCategory(
        uuid: root.uuid,
        name: root.name,
        parentUuid: other.uuid,
        createdAt: root.createdAt,
        updatedAt: root.updatedAt + 100,
        version: root.version + 1,
      );
      if (remote) {
        expect(
          await FinanceStorage.mergeRemoteBundle({
            'categories': [movedRoot.toMap()],
          }),
          0,
        );
      } else {
        expect(
          await FinanceStorage.importBundle({
            'categories': [movedRoot.toMap()],
          }),
          {'imported': 0, 'updated': 0, 'skipped': 1},
        );
      }
      final storedRoot = (await db.query(
        'finance_categories',
        where: 'uuid = ?',
        whereArgs: [root.uuid],
      )).single;
      expect(storedRoot['parent_uuid'], isNull);
    });
  }

  for (final remote in [false, true]) {
    for (final reverse in [false, true]) {
      test('同批移走子类后允许调整大类层级，云端=$remote，反序=$reverse', () async {
        final movedRoot = FinanceCategory(
          uuid: root.uuid,
          name: root.name,
          parentUuid: other.uuid,
          createdAt: root.createdAt,
          updatedAt: root.updatedAt + 100,
          version: root.version + 1,
        );
        final movedChild = FinanceCategory(
          uuid: child.uuid,
          name: child.name,
          parentUuid: other.uuid,
          createdAt: child.createdAt,
          updatedAt: child.updatedAt + 100,
          version: child.version + 1,
        );
        final rows = [movedRoot.toMap(), movedChild.toMap()];
        final categories = reverse ? rows.reversed.toList() : rows;

        if (remote) {
          expect(
            await FinanceStorage.mergeRemoteBundle({'categories': categories}),
            2,
          );
        } else {
          expect(
            await FinanceStorage.importBundle({'categories': categories}),
            {'imported': 0, 'updated': 2, 'skipped': 0},
          );
        }

        final savedRoot = (await db.query(
          'finance_categories',
          where: 'uuid = ?',
          whereArgs: [root.uuid],
        )).single;
        final savedChild = (await db.query(
          'finance_categories',
          where: 'uuid = ?',
          whereArgs: [child.uuid],
        )).single;
        expect(savedRoot['parent_uuid'], other.uuid);
        expect(savedChild['parent_uuid'], other.uuid);
      });
    }
  }

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
