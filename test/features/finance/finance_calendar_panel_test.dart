import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/widgets/finance_calendar_panel.dart';
import 'package:countdown_todo/features/finance/widgets/finance_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 27, 18);
  final expense = _transaction(
    uuid: 'expense-1',
    type: FinanceTransactionType.expense,
    date: DateTime(2026, 10, 12),
    amountMinor: 3600,
    merchant: '午餐',
  );
  final income = _transaction(
    uuid: 'income-1',
    type: FinanceTransactionType.income,
    date: DateTime(2026, 10, 12),
    amountMinor: 10000,
    merchant: '报销',
  );
  final refund = _transaction(
    uuid: 'refund-1',
    type: FinanceTransactionType.refund,
    date: DateTime(2026, 10, 12),
    amountMinor: 600,
    merchant: '退款',
  );

  Widget buildSubject({
    Future<void> Function(DateTime date, GlobalKey sourceKey)? onAdd,
    Future<void> Function(FinanceTransaction, GlobalKey)? onOpenTransaction,
    ValueChanged<DateTime>? onMonthChanged,
    VoidCallback? onShowReport,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FinanceCalendarPanel(
          month: DateTime(2026, 10),
          clock: () => now,
          transactions: [expense, income, refund],
          cumulativeBalanceEvents: [
            FinanceCumulativeBalanceEvent(
              transactionDate: expense.transactionDate,
              eventAt: expense.balanceEventAt(),
              changeMinor: -expense.amountMinor,
            ),
            FinanceCumulativeBalanceEvent(
              transactionDate: income.transactionDate,
              eventAt: income.balanceEventAt(),
              changeMinor: income.amountMinor,
            ),
            FinanceCumulativeBalanceEvent(
              transactionDate: refund.transactionDate,
              eventAt: refund.balanceEventAt(),
              changeMinor: refund.amountMinor,
            ),
          ]..sort((a, b) => a.eventAt.compareTo(b.eventAt)),
          openingBalanceMinor: 20000,
          openingBalanceStartDate: null,
          categories: const {},
          onRefresh: () async {},
          onMonthChanged: onMonthChanged ?? (_) {},
          onShowReport: onShowReport ?? () {},
          onAdd: onAdd,
          onOpenTransaction: onOpenTransaction,
        ),
      ),
    );
  }

  testWidgets('shows daily totals and the selected day ledger', (tester) async {
    await tester.pumpWidget(buildSubject());
    final day = find.byKey(const ValueKey('finance-calendar-day-2026-10-12'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();

    expect(find.text('10月12日账单'), findsOneWidget);
    expect(find.text('净支出 ¥30.00'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('报销'), findsOneWidget);
    expect(find.text('退款'), findsOneWidget);
  });

  testWidgets('metric tabs switch the daily amount calculation', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    final day = find.byKey(const ValueKey('finance-calendar-day-2026-10-12'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入').first);
    await tester.pumpAndSettle();

    expect(find.text('100.00'), findsOneWidget);
  });

  testWidgets('selected date is passed to add and detail actions', (
    tester,
  ) async {
    DateTime? addedDate;
    FinanceTransaction? openedTransaction;
    await tester.pumpWidget(
      buildSubject(
        onAdd: (date, _) async {
          addedDate = date;
        },
        onOpenTransaction: (transaction, _) async {
          openedTransaction = transaction;
        },
      ),
    );
    final day = find.byKey(const ValueKey('finance-calendar-day-2026-10-12'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('finance-calendar-add-entry')),
    );
    await tester.tap(find.byKey(const ValueKey('finance-calendar-add-entry')));
    await tester.pumpAndSettle();

    expect(addedDate, DateTime(2026, 10, 12));
    final expenseTile = find.byKey(
      const ValueKey('finance-calendar-transaction-expense-1'),
    );
    await tester.ensureVisible(expenseTile);
    await tester.tap(expenseTile);
    await tester.pumpAndSettle();
    expect(openedTransaction?.uuid, 'expense-1');
  });

  testWidgets('month navigation and report switch notify the parent', (
    tester,
  ) async {
    DateTime? changedMonth;
    var showReport = false;
    await tester.pumpWidget(
      buildSubject(
        onMonthChanged: (value) => changedMonth = value,
        onShowReport: () => showReport = true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('finance-calendar-month-next')));
    await tester.pumpAndSettle();
    expect(changedMonth, DateTime(2026, 11));

    await tester.tap(find.text('报表'));
    await tester.pumpAndSettle();
    expect(showReport, isTrue);
  });

  testWidgets('overview switches between report and calendar modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinanceOverviewPanel(
            month: DateTime(2026, 10),
            clock: () => now,
            summary: FinanceSummary.fromTransactions([expense, income, refund]),
            transactions: [expense, income, refund],
            categories: const {},
            onAdd: () {},
            addActionKey: GlobalKey(),
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('finance-calendar-month-picker')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey('finance-calendar-mode-selector-calendar'),
            ),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey('finance-calendar-metric-selector-expense'),
            ),
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.text('报表'));
    await tester.pumpAndSettle();
    expect(find.text('时间视图'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('finance-overview-mode-selector-report')),
          )
          .properties
          .selected,
      isTrue,
    );
  });
}

FinanceTransaction _transaction({
  required String uuid,
  required FinanceTransactionType type,
  required DateTime date,
  required int amountMinor,
  required String merchant,
}) {
  final occurredAt = DateTime.utc(
    date.year,
    date.month,
    date.day,
    12,
  ).millisecondsSinceEpoch;
  return FinanceTransaction(
    uuid: uuid,
    type: type,
    amountMinor: amountMinor,
    transactionDate: dateKey(date),
    occurredAt: occurredAt,
    timezoneOffsetMinutes: 0,
    merchant: merchant,
    createdAt: occurredAt,
    updatedAt: occurredAt,
  );
}
