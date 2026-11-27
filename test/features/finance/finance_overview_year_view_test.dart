import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _foodUuid = 'exp-food';

FinanceCategory _foodCategory() => FinanceCategory(
  uuid: _foodUuid,
  name: '日常餐饮',
  icon: '🍜',
  type: FinanceCategoryType.expense,
);

FinanceTransaction _transaction({
  required String uuid,
  required FinanceTransactionType type,
  required int amountMinor,
  required DateTime occurredAt,
  String? categoryUuid,
}) {
  return FinanceTransaction(
    uuid: uuid,
    type: type,
    amountMinor: amountMinor,
    categoryUuid: categoryUuid,
    transactionDate: dateKey(occurredAt),
    occurredAt: occurredAt.millisecondsSinceEpoch,
    createdAt: occurredAt.millisecondsSinceEpoch,
  );
}

List<FinanceTransaction> _yearTransactions() => [
  _transaction(
    uuid: 'jan-expense',
    type: FinanceTransactionType.expense,
    amountMinor: 10000,
    categoryUuid: _foodUuid,
    occurredAt: DateTime(2026, 1, 5, 12),
  ),
  _transaction(
    uuid: 'mar-expense',
    type: FinanceTransactionType.expense,
    amountMinor: 20000,
    categoryUuid: _foodUuid,
    occurredAt: DateTime(2026, 3, 10, 12),
  ),
  _transaction(
    uuid: 'oct-refund',
    type: FinanceTransactionType.refund,
    amountMinor: 5000,
    categoryUuid: _foodUuid,
    occurredAt: DateTime(2026, 10, 1, 12),
  ),
  _transaction(
    uuid: 'mar-income',
    type: FinanceTransactionType.income,
    amountMinor: 50000,
    occurredAt: DateTime(2026, 3, 15, 9),
  ),
  // 上一年账单不应计入 2026 年视图
  _transaction(
    uuid: 'prev-year-expense',
    type: FinanceTransactionType.expense,
    amountMinor: 99900,
    categoryUuid: _foodUuid,
    occurredAt: DateTime(2025, 12, 30, 12),
  ),
];

Future<void> _pumpOverview(
  WidgetTester tester, {
  required DateTime month,
  required DateTime now,
  required List<FinanceTransaction> transactions,
  required Map<String, FinanceCategory> categories,
  List<FinanceBudget> budgets = const [],
  ValueChanged<DateTime>? onMonthChanged,
  Size size = const Size(420, 1200),
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
          budgets: budgets,
          onOpenBudgets: () {},
          onMonthChanged: onMonthChanged,
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
      250,
      maxScrolls: 30,
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

final _yearTooltipFinder = find.byWidgetPredicate(
  (widget) => widget is Tooltip && (widget.message ?? '').contains('年'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('年视图按自然年汇总全年收支、分类占比与 12 个月柱状图', (tester) async {
    final now = DateTime(2026, 10, 15, 12);
    await _pumpOverview(
      tester,
      month: DateTime(2026, 10),
      now: now,
      transactions: _yearTransactions(),
      categories: {_foodUuid: _foodCategory()},
      budgets: [
        FinanceBudget(
          uuid: 'budget-jan',
          monthKey: '2026-01',
          amountMinor: 100000,
        ),
        FinanceBudget(
          uuid: 'budget-feb',
          monthKey: '2026-02',
          amountMinor: 200000,
        ),
      ],
    );

    // 月视图起步，本月净支出只有 10/01 的退款
    expect(find.text('2026年10月'), findsOneWidget);

    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-view-selector-year')),
    );

    // 统计周期标题与副标题切换到自然年
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('按自然年'), findsOneWidget);
    expect(find.text('2026 年'), findsOneWidget);
    // 全年：支出 300，退款 50，收入 500 → 净支出 250，结余 250
    expect(find.text('¥250.00'), findsWidgets);
    expect(find.text('收入'), findsWidgets);
    expect(find.text('总支出'), findsOneWidget);
    expect(find.text('本期结余'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('本年消费节奏与洞察'),
      250,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('本年消费节奏与洞察'), findsOneWidget);
    // 年视图以月均口径替代环比上月
    expect(find.text('月均净支出'), findsOneWidget);
    expect(find.text('按 10 个月均摊'), findsOneWidget);
    expect(find.text('环比上月'), findsNothing);

    // 年度预算汇总两个已设月份的月度总预算
    expect(find.text('2026年总预算'), findsOneWidget);
    expect(find.text('总额 ¥3,000.00'), findsOneWidget);
    expect(find.textContaining('已设 2 个月度预算'), findsOneWidget);

    // 柱状图为 12 个月份而不是 31 天
    await tester.scrollUntilVisible(
      find.text('本年每月净支出'),
      250,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('本年每月净支出'), findsOneWidget);
    expect(_yearTooltipFinder, findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && (widget.message ?? '').contains('2026年1月'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message ?? '').contains('2026年1月 · 净支出 ¥100.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && (widget.message ?? '').contains('2026年3月'),
      ),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('31'), findsNothing);

    // 切回月视图后恢复按月统计
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('finance-overview-view-selector-month')),
      -250,
      maxScrolls: 40,
      scrollable: find.byType(Scrollable).first,
    );
    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-view-selector-month')),
    );
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2026年总预算'), findsNothing);
    expect(find.text('10月未设定总预算'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('年视图支持上一年/下一年翻页与年份选择器，并保留所选月份', (tester) async {
    final now = DateTime(2026, 10, 15, 12);
    final changed = <DateTime>[];
    await _pumpOverview(
      tester,
      month: DateTime(2026, 10),
      now: now,
      transactions: _yearTransactions(),
      categories: {_foodUuid: _foodCategory()},
      onMonthChanged: changed.add,
    );

    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-view-selector-year')),
    );

    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-period-previous')),
    );
    expect(changed.last, DateTime(2025, 10));

    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-period-next')),
    );
    expect(changed.last, DateTime(2027, 10));

    // 点击周期标题打开年份选择器
    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-period-picker')),
    );
    expect(find.text('选择年份'), findsOneWidget);
    await _scrollAndTap(tester, find.text('2024'));
    expect(changed.last, DateTime(2024, 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('未来年份显示计划口径空状态，窄屏大字号下年视图无溢出', (tester) async {
    final now = DateTime(2026, 10, 15, 12);
    await _pumpOverview(
      tester,
      month: DateTime(2027, 10),
      now: now,
      transactions: const [],
      categories: {_foodUuid: _foodCategory()},
      size: const Size(360, 780),
      textScale: 1.6,
    );

    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('finance-overview-view-selector-year')),
    );

    expect(find.text('2027年'), findsOneWidget);
    expect(find.text('计划净支出'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('2027年没有可展示的计划净支出分类'),
      250,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2027年没有可展示的计划净支出分类'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
