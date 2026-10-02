@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
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
    expect(find.text('食品'), findsOneWidget);
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

    await _waitFor(tester, () => find.text('餐饮').evaluate().isNotEmpty);
    expect(find.text('食品'), findsNothing);
    expect(find.text('¥25.00'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('finance-category-detail-detail-food')),
    );
    await tester.pump();
    expect(selectedTransactions, hasLength(1));
    expect(selectedTransactions!.single.amountMinor, 2500);
    expect(tester.takeException(), isNull);
  });
}
