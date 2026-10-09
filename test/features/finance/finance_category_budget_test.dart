@TestOn('vm')
library;

import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_budget_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_ai_context_service.dart';
import 'package:countdown_todo/features/finance/services/finance_storage.dart';
import 'package:countdown_todo/services/database_helper.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openDatabase() async {
  SharedPreferences.setMockInitialValues({});
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await DatabaseHelper.ensureFinanceSchema(db);
  FinanceStorage.databaseOverride = db;
  await FinanceStorage.ensureReady();
  await AppSettingsStorage.setFinanceBudgetAlertEnabled(false);
  return db;
}

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (ready() && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('UI did not settle');
}

void configureView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<String> visibleText() => find.byType(Text).evaluate().map((element) {
  final widget = element.widget as Text;
  return widget.data ?? widget.textSpan?.toPlainText() ?? '';
}).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('分类预算层级与汇总', () {
    late Database db;
    setUp(() async => db = await openDatabase());
    tearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });

    test('汇总只计入最外层预算范围，互不重叠的细分类仍独立汇总', () {
      final categories = [
        FinanceCategory(uuid: 'root', name: '大类'),
        FinanceCategory(uuid: 'child', name: '细类', parentUuid: 'root'),
        FinanceCategory(uuid: 'leaf', name: '三级', parentUuid: 'child'),
        FinanceCategory(uuid: 'other', name: '其他'),
      ];
      FinanceBudget budget(String uuid) => FinanceBudget(
        monthKey: '2026-09',
        categoryUuid: uuid,
        amountMinor: 10000,
      );
      final scopes = FinanceBudget.nonOverlappingCategories([
        budget('leaf'),
        budget('other'),
        budget('root'),
        budget('child'),
      ], categories);
      expect(scopes.map((item) => item.categoryUuid).toSet(), {
        'root',
        'other',
      });
      final leafScopes = FinanceBudget.nonOverlappingCategories([
        budget('leaf'),
        budget('other'),
      ], categories);
      expect(leafScopes.map((item) => item.categoryUuid).toSet(), {
        'leaf',
        'other',
      });
    });

    test('循环分类的重叠预算稳定保留一个，不会清空整个汇总', () {
      final categories = [
        FinanceCategory(uuid: 'a', name: 'A', parentUuid: 'b'),
        FinanceCategory(uuid: 'b', name: 'B', parentUuid: 'a'),
      ];
      final scopes = FinanceBudget.nonOverlappingCategories([
        FinanceBudget(
          monthKey: '2026-09',
          categoryUuid: 'b',
          amountMinor: 10000,
        ),
        FinanceBudget(
          monthKey: '2026-09',
          categoryUuid: 'a',
          amountMinor: 20000,
        ),
      ], categories);
      expect(scopes.single.categoryUuid, 'a');
    });

    test('多层分类及已归档子分类纳入预算，退款按范围净额抵扣', () {
      final categories = [
        FinanceCategory(
          uuid: 'root',
          name: '餐饮',
          type: FinanceCategoryType.expense,
        ),
        FinanceCategory(
          uuid: 'child',
          name: '外卖',
          type: FinanceCategoryType.expense,
          parentUuid: 'root',
        ),
        FinanceCategory(
          uuid: 'grandchild',
          name: '旧平台',
          type: FinanceCategoryType.expense,
          parentUuid: 'child',
          isArchived: true,
        ),
      ];
      final summary = const FinanceSummary(
        expenseMinor: 19000,
        refundMinor: 3000,
        expenseByCategory: {
          'root': 1000,
          'child': 6000,
          'grandchild': 2000,
          'other': 7000,
        },
      );
      final budget = FinanceBudget(
        monthKey: '2026-09',
        categoryUuid: 'root',
        amountMinor: 10000,
      );
      expect(summary.spendingForBudget(budget, categories), 9000);
      budget.categoryUuid = 'child';
      expect(summary.spendingForBudget(budget, categories), 8000);
      budget.categoryUuid = null;
      expect(summary.spendingForBudget(budget, categories), 16000);
    });

    test('损坏的分类环不会重复计算，退款净额为负时预算使用量归零', () {
      final categories = [
        FinanceCategory(
          uuid: 'a',
          name: 'A',
          type: FinanceCategoryType.expense,
          parentUuid: 'b',
        ),
        FinanceCategory(
          uuid: 'b',
          name: 'B',
          type: FinanceCategoryType.expense,
          parentUuid: 'a',
        ),
      ];
      final budget = FinanceBudget(
        monthKey: '2026-09',
        categoryUuid: 'a',
        amountMinor: 10000,
      );
      expect(
        const FinanceSummary(expenseByCategory: {'a': 400, 'b': 600})
            .spendingForBudget(budget, categories),
        1000,
      );
      expect(
        const FinanceSummary(expenseByCategory: {'a': -1400, 'b': 600})
            .spendingForBudget(budget, categories),
        0,
      );
      budget.categoryUuid = 'missing-category';
      expect(
        const FinanceSummary(
          expenseByCategory: {'missing-category': 500, 'a': 400},
        ).spendingForBudget(budget, categories),
        500,
      );
    });
  });

  testWidgets('餐饮大类预算计入外卖子分类支出', (tester) async {
    configureView(tester);
    final db = (await tester.runAsync(openDatabase))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await tester.runAsync(() async {
      await db.insert(
        'finance_budgets',
        FinanceBudget(
          uuid: 'food-root-budget',
          monthKey: '2026-09',
          categoryUuid: 'finance-system-category-food',
          amountMinor: 10000,
        ).toMap(),
      );
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'direct-food',
          categoryUuid: 'finance-system-category-food',
          amountMinor: 1000,
          transactionDate: '2026-09-02',
          occurredAt: DateTime(2026, 9, 2, 12).millisecondsSinceEpoch,
        ),
      );
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          uuid: 'child-takeout',
          categoryUuid: 'finance-system-category-food-takeout',
          amountMinor: 9000,
          transactionDate: '2026-09-03',
          occurredAt: DateTime(2026, 9, 3, 12).millisecondsSinceEpoch,
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceBudgetScreen(
          initialMonth: DateTime(2026, 9),
          clock: () => DateTime(2026, 10, 1, 12),
        ),
      ),
    );
    final card = find.byKey(
      const ValueKey('finance-budget-card-food-root-budget'),
    );
    await waitFor(tester, () => card.evaluate().isNotEmpty);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: card, matching: find.text('剩余 ¥0.00')),
      findsOneWidget,
    );
    final context = (await tester.runAsync(
      () => FinanceAiContextService.buildContext(
        userMessage: '统计上月餐饮预算',
        now: DateTime(2026, 10, 1, 12),
      ),
    ))!;
    expect(context, contains('餐饮: 额度 ¥100.00 | 已用 ¥100.00 | 剩余 ¥0.00'));
  });

  testWidgets('父子分类预算合计不应重复计算同一笔支出', (tester) async {
    configureView(tester);
    final db = (await tester.runAsync(openDatabase))!;
    addTearDown(() async {
      FinanceStorage.databaseOverride = null;
      await db.close();
    });
    await tester.runAsync(() async {
      await FinanceStorage.saveCategory(
        FinanceCategory(uuid: 'audit-food', name: '审查餐饮'),
      );
      await FinanceStorage.saveCategory(
        FinanceCategory(
          uuid: 'audit-takeout',
          name: '审查外卖',
          parentUuid: 'audit-food',
        ),
      );
      for (final category in ['audit-food', 'audit-takeout']) {
        await FinanceStorage.saveBudget(
          FinanceBudget(
            monthKey: '2026-09',
            categoryUuid: category,
            amountMinor: 10000,
          ),
        );
      }
      await FinanceStorage.saveTransaction(
        FinanceTransaction(
          amountMinor: 9000,
          categoryUuid: 'audit-takeout',
          transactionDate: '2026-09-15',
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceBudgetScreen(
          initialMonth: DateTime(2026, 9),
          clock: () => DateTime(2026, 10, 1),
        ),
      ),
    );
    await waitFor(
      tester,
      () => find.text('2026年9月分类预算合计').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
    final usedLine = visibleText().singleWhere(
      (text) => text.startsWith('已使用 '),
    );
    expect(usedLine, '已使用 ¥90.00 / ¥100.00');
  });
}
