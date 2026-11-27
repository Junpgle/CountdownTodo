import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_category_detail_screen.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpOverview(
  WidgetTester tester, {
  required DateTime month,
  required DateTime now,
  required List<FinanceTransaction> transactions,
  required Map<String, FinanceCategory> categories,
  bool categoryTapOpensLedger = true,
  Size size = const Size(420, 900),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: FinanceOverviewPanel(
          month: month,
          clock: () => now,
          summary: FinanceSummary.fromTransactions(transactions),
          transactions: transactions,
          categories: categories,
          categoryTapOpensLedger: categoryTapOpensLedger,
          onAdd: () {},
          addActionKey: GlobalKey(),
          onRefresh: () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      maxScrolls: 20,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(
    finder.evaluate().first,
    alignment: 0.25,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FinanceOverviewPanel income/expense donut chart toggle', () {
    testWidgets('默认显示支出饼状图，切换至收入后展示合并子类的收入饼状图并支持切片交互', (tester) async {
      final now = DateTime(2026, 10, 15, 12);
      final month = DateTime(2026, 10);
      final food = FinanceCategory(
        uuid: 'exp-food',
        name: '餐饮',
        icon: '🍜',
        type: FinanceCategoryType.expense,
      );
      final salaryRoot = FinanceCategory(
        uuid: 'inc-salary',
        name: '薪资',
        icon: '💼',
        type: FinanceCategoryType.income,
      );
      final bonusChild = FinanceCategory(
        uuid: 'inc-bonus',
        name: '绩效奖金',
        icon: '🎁',
        type: FinanceCategoryType.income,
        parentUuid: salaryRoot.uuid,
      );
      final investRoot = FinanceCategory(
        uuid: 'inc-invest',
        name: '理财',
        icon: '📈',
        type: FinanceCategoryType.income,
      );
      final categories = {
        food.uuid: food,
        salaryRoot.uuid: salaryRoot,
        bonusChild.uuid: bonusChild,
        investRoot.uuid: investRoot,
      };
      final transactions = [
        FinanceTransaction(
          uuid: 'tx-exp-1',
          type: FinanceTransactionType.expense,
          amountMinor: 5000,
          categoryUuid: food.uuid,
          transactionDate: '2026-10-03',
          occurredAt: DateTime(2026, 10, 3, 12).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'tx-refund-1',
          type: FinanceTransactionType.refund,
          amountMinor: 1000,
          categoryUuid: food.uuid,
          transactionDate: '2026-10-04',
          occurredAt: DateTime(2026, 10, 4, 12).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'tx-transfer-1',
          type: FinanceTransactionType.transfer,
          amountMinor: 20000,
          transactionDate: '2026-10-05',
          occurredAt: DateTime(2026, 10, 5, 12).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'tx-inc-salary',
          type: FinanceTransactionType.income,
          amountMinor: 50000,
          categoryUuid: salaryRoot.uuid,
          transactionDate: '2026-10-06',
          occurredAt: DateTime(2026, 10, 6, 10).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'tx-inc-bonus',
          type: FinanceTransactionType.income,
          amountMinor: 30000,
          categoryUuid: bonusChild.uuid,
          transactionDate: '2026-10-07',
          occurredAt: DateTime(2026, 10, 7, 10).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'tx-inc-invest',
          type: FinanceTransactionType.income,
          amountMinor: 15000,
          categoryUuid: investRoot.uuid,
          transactionDate: '2026-10-08',
          occurredAt: DateTime(2026, 10, 8, 10).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'tx-inc-uncat',
          type: FinanceTransactionType.income,
          amountMinor: 5000,
          categoryUuid: null,
          transactionDate: '2026-10-09',
          occurredAt: DateTime(2026, 10, 9, 10).millisecondsSinceEpoch,
        ),
      ];

      await _pumpOverview(
        tester,
        month: month,
        now: now,
        transactions: transactions,
        categories: categories,
      );

      // 默认处于支出视图
      expect(find.text('支出分类'), findsOneWidget);
      expect(find.text('总净支出'), findsOneWidget);
      expect(
        find.byKey(ValueKey('finance-overview-category-${food.uuid}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('finance-overview-category-${salaryRoot.uuid}')),
        findsNothing,
      );

      // 切换到收入
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );

      expect(find.text('收入分类'), findsOneWidget);
      expect(find.text('总收入'), findsOneWidget);
      expect(find.text('共 3 项分类'), findsOneWidget);
      // 薪资与绩效奖金合并到根分类薪资（800 / 1000 = 80.0%）
      expect(
        find.byKey(ValueKey('finance-overview-category-${salaryRoot.uuid}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('finance-overview-category-${investRoot.uuid}')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('finance-overview-category-uncategorized')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('finance-overview-category-${food.uuid}')),
        findsNothing,
      );
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('15.0%'), findsOneWidget);
      expect(find.text('5.0%'), findsOneWidget);

      // 点击薪资分类图标选中该切片
      await _scrollAndTap(
        tester,
        find.descendant(
          of: find.byKey(
            ValueKey('finance-overview-category-${salaryRoot.uuid}'),
          ),
          matching: find.text('💼'),
        ),
      );
      expect(find.text('占比 80.0%'), findsOneWidget);

      // 切回支出时重置选中状态
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-expense'),
        ),
      );
      expect(find.text('支出分类'), findsOneWidget);
      expect(find.text('总净支出'), findsOneWidget);
      expect(find.text('占比 80.0%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('处理仅收入、仅支出与未来计划月份的空状态与文案', (tester) async {
      final now = DateTime(2026, 10, 15, 12);
      final salaryRoot = FinanceCategory(
        uuid: 'inc-salary',
        name: '工资',
        icon: '💼',
        type: FinanceCategoryType.income,
      );
      final food = FinanceCategory(
        uuid: 'exp-food',
        name: '餐饮',
        icon: '🍜',
        type: FinanceCategoryType.expense,
      );

      // 1. 仅存在收入时，支出空卡片与收入饼状图可正常切换
      await _pumpOverview(
        tester,
        month: DateTime(2026, 10),
        now: now,
        transactions: [
          FinanceTransaction(
            uuid: 'only-inc',
            type: FinanceTransactionType.income,
            amountMinor: 12000,
            categoryUuid: salaryRoot.uuid,
            transactionDate: '2026-10-10',
            occurredAt: DateTime(2026, 10, 10, 9).millisecondsSinceEpoch,
          ),
        ],
        categories: {salaryRoot.uuid: salaryRoot, food.uuid: food},
      );

      expect(find.text('本月没有可展示的净支出分类'), findsOneWidget);
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );
      expect(find.text('本月没有可展示的净支出分类'), findsNothing);
      expect(find.text('总收入'), findsOneWidget);
      expect(
        find.byKey(ValueKey('finance-overview-category-${salaryRoot.uuid}')),
        findsOneWidget,
      );

      // 2. 仅存在支出时，切换收入显示收入空状态提示
      await _pumpOverview(
        tester,
        month: DateTime(2026, 10),
        now: now,
        transactions: [
          FinanceTransaction(
            uuid: 'only-exp',
            type: FinanceTransactionType.expense,
            amountMinor: 5000,
            categoryUuid: food.uuid,
            transactionDate: '2026-10-10',
            occurredAt: DateTime(2026, 10, 10, 9).millisecondsSinceEpoch,
          ),
        ],
        categories: {salaryRoot.uuid: salaryRoot, food.uuid: food},
      );
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );
      expect(find.text('本月没有可展示的收入分类'), findsOneWidget);

      // 3. 未来计划月份显示计划收入文案及空状态
      await _pumpOverview(
        tester,
        month: DateTime(2026, 11),
        now: now,
        transactions: [
          FinanceTransaction(
            uuid: 'planned-inc',
            type: FinanceTransactionType.income,
            amountMinor: 90000,
            categoryUuid: salaryRoot.uuid,
            transactionDate: '2026-11-10',
            occurredAt: DateTime(2026, 11, 10, 9).millisecondsSinceEpoch,
          ),
        ],
        categories: {salaryRoot.uuid: salaryRoot},
      );
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );
      expect(find.text('计划收入分类'), findsOneWidget);
      expect(find.text('计划总收入'), findsOneWidget);

      await _pumpOverview(
        tester,
        month: DateTime(2026, 11),
        now: now,
        transactions: const [],
        categories: {salaryRoot.uuid: salaryRoot},
      );
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );
      expect(find.text('2026年11月没有可展示的计划收入分类'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击收入根分类进入收入分类详情，展示小类环形图与正向入账金额', (tester) async {
      final now = DateTime(2026, 10, 15, 12);
      final salaryRoot = FinanceCategory(
        uuid: 'inc-salary',
        name: '薪资收入',
        icon: '💼',
        type: FinanceCategoryType.income,
      );
      final basePay = FinanceCategory(
        uuid: 'inc-base',
        name: '基本工资',
        icon: '🪙',
        type: FinanceCategoryType.income,
        parentUuid: salaryRoot.uuid,
      );
      final bonusPay = FinanceCategory(
        uuid: 'inc-bonus',
        name: '季度奖金',
        icon: '🎁',
        type: FinanceCategoryType.income,
        parentUuid: salaryRoot.uuid,
      );
      final transactions = [
        FinanceTransaction(
          uuid: 'inc-t1',
          type: FinanceTransactionType.income,
          amountMinor: 75000,
          categoryUuid: basePay.uuid,
          transactionDate: '2026-10-05',
          occurredAt: DateTime(2026, 10, 5, 10).millisecondsSinceEpoch,
          merchant: '发薪日',
        ),
        FinanceTransaction(
          uuid: 'inc-t2',
          type: FinanceTransactionType.income,
          amountMinor: 25000,
          categoryUuid: bonusPay.uuid,
          transactionDate: '2026-10-12',
          occurredAt: DateTime(2026, 10, 12, 16).millisecondsSinceEpoch,
          merchant: '季度激励',
        ),
      ];

      await _pumpOverview(
        tester,
        month: DateTime(2026, 10),
        now: now,
        transactions: transactions,
        categories: {
          salaryRoot.uuid: salaryRoot,
          basePay.uuid: basePay,
          bonusPay.uuid: bonusPay,
        },
        categoryTapOpensLedger: false,
      );

      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );

      await _scrollAndTap(
        tester,
        find.byKey(ValueKey('finance-overview-category-${salaryRoot.uuid}')),
      );

      expect(find.byType(FinanceCategoryDetailScreen), findsOneWidget);
      expect(find.text('收入分类详情'), findsOneWidget);
      expect(find.text('总收入'), findsOneWidget);
      expect(find.text('小类收入'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);

      await _scrollAndTap(
        tester,
        find.byKey(ValueKey('finance-category-detail-${basePay.uuid}')),
      );
      expect(find.text('+¥750.00'), findsOneWidget);
      expect(find.text('发薪日'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏与窄屏大字号下切换收入饼状图均无溢出异常', (tester) async {
      final now = DateTime(2026, 10, 15, 12);
      final salaryRoot = FinanceCategory(
        uuid: 'inc-salary',
        name: '非常长的工资与奖金收入根分类名称测试',
        icon: '💼',
        type: FinanceCategoryType.income,
      );
      final investRoot = FinanceCategory(
        uuid: 'inc-invest',
        name: '投资理财收益',
        icon: '📈',
        type: FinanceCategoryType.income,
      );
      final transactions = [
        FinanceTransaction(
          uuid: 'inc-wide-1',
          type: FinanceTransactionType.income,
          amountMinor: 100000,
          categoryUuid: salaryRoot.uuid,
          transactionDate: '2026-10-08',
          occurredAt: DateTime(2026, 10, 8, 9).millisecondsSinceEpoch,
        ),
        FinanceTransaction(
          uuid: 'inc-wide-2',
          type: FinanceTransactionType.income,
          amountMinor: 25000,
          categoryUuid: investRoot.uuid,
          transactionDate: '2026-10-09',
          occurredAt: DateTime(2026, 10, 9, 9).millisecondsSinceEpoch,
        ),
      ];
      final categories = {
        salaryRoot.uuid: salaryRoot,
        investRoot.uuid: investRoot,
      };

      // 宽屏桌面布局
      await _pumpOverview(
        tester,
        month: DateTime(2026, 10),
        now: now,
        transactions: transactions,
        categories: categories,
        size: const Size(1200, 900),
      );
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );
      expect(find.text('总收入'), findsOneWidget);
      final donutX = tester.getCenter(find.text('总收入')).dx;
      final listX = tester.getCenter(find.text('投资理财收益')).dx;
      expect(listX, greaterThan(donutX));
      expect(tester.takeException(), isNull);

      // 窄屏大字号布局
      await _pumpOverview(
        tester,
        month: DateTime(2026, 10),
        now: now,
        transactions: transactions,
        categories: categories,
        size: const Size(360, 780),
        textScale: 1.6,
      );
      await _scrollAndTap(
        tester,
        find.byKey(
          const ValueKey('finance-overview-category-type-selector-income'),
        ),
      );
      expect(find.text('总收入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
