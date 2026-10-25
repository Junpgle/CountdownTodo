import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/screens/finance_automation_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_future_commitments_screen.dart';
import 'package:countdown_todo/features/finance/screens/finance_loan_screen.dart';
import 'package:countdown_todo/features/finance/services/finance_future_commitments_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 24, 14);

FinanceFutureCommitmentForecast _forecast(DateTime now, int months) {
  final recurring = FinanceRecurringRule(
    uuid: 'screen-rent',
    name: '月度房租',
    amountMinor: 12345,
    startDate: '2026-01-01',
    dayOfMonth: 25,
    autoGenerate: false,
  );
  final refund = FinanceRecurringRule(
    uuid: 'screen-refund',
    name: '月度退款',
    type: FinanceTransactionType.refund,
    amountMinor: 2500,
    currencyCode: 'USD',
    startDate: '2026-01-01',
    dayOfMonth: 26,
  );
  final loan = FinanceLoan(
    uuid: 'screen-loan',
    name: '设备分期',
    principalMinor: 100000,
    currencyCode: 'USD',
    termMonths: 6,
    startDate: '2026-10-01',
    repaymentDay: 15,
  );
  final installment = FinanceLoanInstallment(
    uuid: 'screen-installment',
    loanUuid: loan.uuid,
    installmentIndex: 2,
    dueDate: '2026-11-15',
    paymentMinor: 8000,
    principalMinor: 7000,
    interestMinor: 1000,
    remainingPrincipalMinor: 50000,
  );
  final overdue = FinanceLoanInstallment(
    uuid: 'screen-overdue',
    loanUuid: loan.uuid,
    installmentIndex: 1,
    dueDate: '2026-10-22',
    paymentMinor: 8000,
    principalMinor: 7000,
    interestMinor: 1000,
    remainingPrincipalMinor: 57000,
  );
  final oneOffBill = FinanceTransaction(
    uuid: 'screen-one-off-bill',
    type: FinanceTransactionType.expense,
    amountMinor: 12345,
    transactionDate: '2026-10-25',
    occurredAt: DateTime(2026, 10, 25, 18).millisecondsSinceEpoch,
    timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
    createdAt: DateTime(2026, 10, 24, 12).millisecondsSinceEpoch,
    merchant: '临时房租',
    note: '一次性未来账单',
  );
  return FinanceFutureCommitmentsService.project(
    now: now,
    horizonMonths: months,
    recurringRules: [recurring, refund],
    loans: [loan],
    installmentsByLoan: {
      loan.uuid: [installment, overdue],
    },
    transactions: [oneOffBill],
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  FinanceFutureCommitmentLoader? loader,
  FinanceCategoriesLoader? categoriesLoader,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FinanceFutureCommitmentsScreen(
        clock: () => _now,
        loader: loader ?? (now, months) async => _forecast(now, months),
        paymentMethodsLoader: () async => const [],
        categoriesLoader: categoriesLoader ?? () async => const [],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('显示分币种合计、逾期提醒与自然月列表', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('未来3个月合计'), findsOneWidget);
    expect(find.text('CNY'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(find.text('逾期待还'), findsOneWidget);
    expect(find.text('2026年10月'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('2026年11月'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.text('月度房租'), findsWidgets);
    expect(find.textContaining('本金'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换期限会重新读取，并从条目直达现有规则和贷款页面', (tester) async {
    final requestedHorizons = <int>[];
    await _pumpScreen(
      tester,
      loader: (now, months) async {
        requestedHorizons.add(months);
        return _forecast(now, months);
      },
    );

    await tester.tap(find.text('6个月'));
    await tester.pumpAndSettle();
    expect(requestedHorizons.last, 6);
    expect(find.text('未来6个月合计'), findsOneWidget);

    final recurring = find.byKey(
      const ValueKey('future-commitment-recurring:screen-rent:2026-10'),
    );
    await Scrollable.ensureVisible(
      tester.element(recurring),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(recurring);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(FinanceAutomationScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      ModalRoute.of(
        tester.element(
          find.byType(FinanceAutomationScreen, skipOffstage: false),
        ),
      )!.isCurrent,
      isTrue,
    );
    Navigator.of(
      tester.element(find.byType(FinanceAutomationScreen, skipOffstage: false)),
    ).pop();
    await tester.pumpAndSettle();

    final installment = find.byKey(
      const ValueKey('future-commitment-loan:screen-installment'),
    );
    await Scrollable.ensureVisible(
      tester.element(installment),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(installment);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byType(FinanceLoanDetailScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      ModalRoute.of(
        tester.element(
          find.byType(FinanceLoanDetailScreen, skipOffstage: false),
        ),
      )!.isCurrent,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未来手工账单展示来源与重叠提示，并能直达账单详情后刷新', (tester) async {
    var loadCount = 0;
    await _pumpScreen(
      tester,
      loader: (now, months) async {
        loadCount++;
        return _forecast(now, months);
      },
    );

    final bill = find.byKey(
      const ValueKey('future-commitment-transaction:screen-one-off-bill'),
    );
    await Scrollable.ensureVisible(
      tester.element(bill),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    expect(find.text('临时房租'), findsOneWidget);
    expect(find.textContaining('已录入账单 · 手工录入'), findsOneWidget);
    expect(find.textContaining('可能与周期计划“月度房租”重叠'), findsOneWidget);

    await tester.tap(bill);
    await tester.pumpAndSettle();
    expect(find.text('账单详情'), findsOneWidget);
    expect(find.text('临时房租'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('finance-transaction-detail-edit')),
      findsOneWidget,
    );

    Navigator.of(tester.element(find.text('账单详情'))).pop();
    await tester.pumpAndSettle();
    expect(loadCount, 2);
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('未来3个月合计'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载失败可重试，失败状态不会显示成空数据', (tester) async {
    var attempts = 0;
    await _pumpScreen(
      tester,
      loader: (now, months) async {
        attempts++;
        if (attempts == 1) throw StateError('测试数据暂不可读');
        return _forecast(now, months);
      },
    );

    expect(find.text('未来收支加载失败'), findsOneWidget);
    expect(find.textContaining('测试数据暂不可读'), findsOneWidget);
    expect(find.text('本月没有已登记的固定收支。'), findsNothing);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('未来3个月合计'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('窄屏深色大字布局不溢出', (tester) async {
    await _pumpScreen(
      tester,
      size: const Size(320, 720),
      textScale: 1.7,
      brightness: Brightness.dark,
    );

    expect(find.text('未来收支'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
