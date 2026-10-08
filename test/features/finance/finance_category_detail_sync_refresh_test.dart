@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_category_detail_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openDatabase(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  return (await tester.runAsync(() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await DatabaseHelper.ensureFinanceSchema(db);
    FinanceStorage.databaseOverride = db;
    await FinanceStorage.ensureReady();
    return db;
  }))!;
}

void _closeDatabase(Database db) {
  addTearDown(() async {
    FinanceStorage.databaseOverride = null;
    await db.close();
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  fail('分类详情未在限定时间内刷新');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('未来周期分类详情标记计划并在周期开始后切换为实际', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    var now = DateTime(2026, 11, 30, 23, 59);
    final periodStart = DateTime(2026, 12);
    final periodEnd = DateTime(2027, 1);
    final root = FinanceCategory(uuid: 'planned-detail-root', name: '日常支出');
    final child = FinanceCategory(
      uuid: 'planned-detail-food',
      name: '食品',
      parentUuid: root.uuid,
    );
    final transaction = FinanceTransaction(
      uuid: 'planned-detail-expense',
      amountMinor: 2500,
      categoryUuid: child.uuid,
      transactionDate: '2026-12-15',
      occurredAt: DateTime(2026, 12, 15, 12).millisecondsSinceEpoch,
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveCategory(root);
      await FinanceStorage.saveCategory(child);
      await FinanceStorage.saveTransaction(transaction);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceCategoryDetailScreen(
          periodTitle: '2026年12月',
          periodStart: periodStart,
          periodEnd: periodEnd,
          clock: () => now,
          isPlanned: true,
          rootCategoryUuid: root.uuid,
          transactions: [transaction],
          categories: {root.uuid: root, child.uuid: child},
        ),
      ),
    );

    await _waitFor(tester, () => find.text('计划净支出').evaluate().isNotEmpty);
    expect(find.text('计划支出分类详情'), findsOneWidget);
    expect(find.text('计划小类'), findsOneWidget);
    expect(find.text('1 笔计划账单 · 点击查看'), findsOneWidget);

    now = DateTime(2026, 12, 1, 0, 0, 2);
    await tester.pump(const Duration(seconds: 62));
    await _waitFor(tester, () => find.text('计划净支出').evaluate().isEmpty);

    expect(find.text('支出分类详情'), findsOneWidget);
    expect(find.text('净支出'), findsOneWidget);
    expect(find.text('计划小类'), findsNothing);
    expect(find.text('1 笔计划账单 · 点击查看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('云同步更新分类和账单后刷新已打开的分类详情', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month);
    final root = FinanceCategory(uuid: 'detail-root', name: '日常支出');
    final child = FinanceCategory(
      uuid: 'detail-food',
      name: '食品',
      parentUuid: root.uuid,
    );
    final transaction = FinanceTransaction(
      uuid: 'detail-expense',
      amountMinor: 1000,
      categoryUuid: child.uuid,
      transactionDate: dateKey(now),
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveCategory(root);
      await FinanceStorage.saveCategory(child);
      await FinanceStorage.saveTransaction(transaction);
    });

    List<FinanceTransaction>? selectedTransactions;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceOverviewPanel(
            month: periodStart,
            clock: DateTime.now,
            summary: FinanceSummary.fromTransactions([transaction]),
            transactions: [transaction],
            categories: {root.uuid: root, child.uuid: child},
            onAdd: () {},
            addActionKey: GlobalKey(),
            onRefresh: () async {},
            onCategorySelected: (_, _, periodTransactions) async {
              selectedTransactions = periodTransactions;
            },
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(ValueKey('finance-overview-category-${root.uuid}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('日常支出 - 食品'), findsOneWidget);
    expect(find.text('¥10.00'), findsNWidgets(2));

    final remoteChild = FinanceCategory.fromMap(child.toMap())
      ..name = '餐饮'
      ..version = child.version + 1
      ..updatedAt = child.updatedAt + 10000;
    final remoteTransaction = FinanceTransaction.fromMap(transaction.toMap())
      ..amountMinor = 2500
      ..version = transaction.version + 1
      ..updatedAt = transaction.updatedAt + 10000;
    final revisionBeforeSync = FinanceStorage.revision.value;
    final mergedCount = await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'categories': [remoteChild.toMap()],
        'transactions': [remoteTransaction.toMap()],
      }),
    );
    expect(mergedCount, greaterThan(0));
    expect(FinanceStorage.revision.value, greaterThan(revisionBeforeSync));
    final storedCategories = await tester.runAsync(
      () => FinanceStorage.getCategories(includeArchived: true),
    );
    expect(
      storedCategories!.singleWhere((item) => item.uuid == child.uuid).name,
      '餐饮',
    );

    await _waitFor(
      tester,
      () => find.text('日常支出 - 餐饮').evaluate().isNotEmpty,
    );
    expect(find.text('日常支出 - 食品'), findsNothing);
    expect(find.text('¥25.00'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('finance-category-detail-detail-food')),
    );
    await tester.pump();
    expect(selectedTransactions, hasLength(1));
    expect(selectedTransactions!.single.amountMinor, 2500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同步删除分类后不会把旧分类账单显示成未分类', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month);
    final periodEnd = DateTime(now.year, now.month + 1);
    final root = FinanceCategory(uuid: 'deleted-detail-root', name: '待删除分类');
    final transaction = FinanceTransaction(
      uuid: 'deleted-detail-transaction',
      amountMinor: 3200,
      categoryUuid: root.uuid,
      transactionDate: dateKey(now),
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveCategory(root);
      await FinanceStorage.saveTransaction(transaction);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceCategoryDetailScreen(
          periodTitle: '${now.year}年${now.month}月',
          periodStart: periodStart,
          periodEnd: periodEnd,
          clock: DateTime.now,
          rootCategoryUuid: root.uuid,
          transactions: [transaction],
          categories: {root.uuid: root},
        ),
      ),
    );
    expect(find.text('待删除分类'), findsWidgets);

    final deletedRoot = FinanceCategory.fromMap(root.toMap())
      ..isDeleted = true
      ..version = root.version + 1
      ..updatedAt = root.updatedAt + 10000;
    final mergedCount = await tester.runAsync(
      () => FinanceStorage.mergeRemoteBundle({
        'categories': [deletedRoot.toMap()],
      }),
    );
    expect(mergedCount, greaterThan(0));

    await _waitFor(tester, () => find.text('分类已删除').evaluate().isNotEmpty);
    expect(find.text('未分类'), findsNothing);
    expect(find.text('这个分类已删除或不可用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已打开的分类详情会在计划账单发生时刷新', (tester) async {
    final db = await _openDatabase(tester);
    _closeDatabase(db);
    var now = DateTime.now();
    final dueAt = now.add(const Duration(seconds: 3));
    final periodStart = DateTime(now.year, now.month);
    final periodEnd = DateTime(now.year, now.month + 1);
    final root = FinanceCategory(uuid: 'due-detail-root', name: '固定支出');
    final child = FinanceCategory(
      uuid: 'due-detail-child',
      name: '网络费',
      parentUuid: root.uuid,
    );
    final transaction = FinanceTransaction(
      uuid: 'due-detail-transaction',
      amountMinor: 1200,
      categoryUuid: child.uuid,
      transactionDate: dateKey(now),
      occurredAt: dueAt.millisecondsSinceEpoch,
      timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
      createdAt: now.millisecondsSinceEpoch,
      updatedAt: now.millisecondsSinceEpoch,
    );
    await tester.runAsync(() async {
      await FinanceStorage.saveCategory(root);
      await FinanceStorage.saveCategory(child);
      await FinanceStorage.saveTransaction(transaction);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceCategoryDetailScreen(
          periodTitle: '${now.year}年${now.month}月',
          periodStart: periodStart,
          periodEnd: periodEnd,
          clock: () => now,
          rootCategoryUuid: root.uuid,
          transactions: const [],
          categories: {root.uuid: root, child.uuid: child},
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    expect(find.text('固定支出 - 网络费'), findsNothing);
    expect(find.text('这个大类下暂无可展示的小类账单'), findsOneWidget);

    now = dueAt;
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 4)),
    );
    await tester.pump();
    await _waitFor(
      tester,
      () => find.text('固定支出 - 网络费').evaluate().isNotEmpty,
    );

    expect(find.text('¥12.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
