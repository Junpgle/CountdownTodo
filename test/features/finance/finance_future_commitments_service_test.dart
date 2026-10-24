import 'package:countdown_todo/features/finance/models/finance_models.dart';
import 'package:countdown_todo/features/finance/services/finance_future_commitments_service.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceRecurringRule _rule({
  required String uuid,
  required String name,
  required String startDate,
  int amountMinor = 10000,
  String currencyCode = 'CNY',
  FinanceTransactionType type = FinanceTransactionType.expense,
  FinanceRecurringFrequency frequency = FinanceRecurringFrequency.monthly,
  int day = 31,
  int month = 1,
  bool enabled = true,
  bool deleted = false,
}) => FinanceRecurringRule(
  uuid: uuid,
  name: name,
  amountMinor: amountMinor,
  currencyCode: currencyCode,
  type: type,
  frequency: frequency,
  dayOfMonth: day,
  monthOfYear: month,
  startDate: startDate,
  isEnabled: enabled,
  isDeleted: deleted,
);

FinanceLoan _loan({
  required String uuid,
  String currencyCode = 'CNY',
  bool deleted = false,
}) => FinanceLoan(
  uuid: uuid,
  name: '测试贷款 $uuid',
  principalMinor: 100000,
  currencyCode: currencyCode,
  termMonths: 12,
  startDate: '2026-01-01',
  repaymentDay: 15,
  isDeleted: deleted,
);

FinanceLoanInstallment _installment({
  required String uuid,
  required String loanUuid,
  required String dueDate,
  int index = 1,
  int paymentMinor = 5000,
  int principalMinor = 4500,
  int interestMinor = 500,
  bool paid = false,
  bool deleted = false,
}) => FinanceLoanInstallment(
  uuid: uuid,
  loanUuid: loanUuid,
  installmentIndex: index,
  dueDate: dueDate,
  paymentMinor: paymentMinor,
  principalMinor: principalMinor,
  interestMinor: interestMinor,
  remainingPrincipalMinor: 50000,
  isPaid: paid,
  isDeleted: deleted,
);

FinanceTransaction _transaction({
  required String uuid,
  required String transactionDate,
  int amountMinor = 10000,
  String currencyCode = 'CNY',
  FinanceTransactionType type = FinanceTransactionType.expense,
  int? occurredAt,
  int? createdAt,
  int? timezoneOffsetMinutes,
  bool deleted = false,
}) => FinanceTransaction(
  uuid: uuid,
  type: type,
  amountMinor: amountMinor,
  currencyCode: currencyCode,
  transactionDate: transactionDate,
  occurredAt: occurredAt,
  createdAt: createdAt,
  timezoneOffsetMinutes: timezoneOffsetMinutes,
  isDeleted: deleted,
);

int _localEpoch(String date, int hour, int minute, int offsetMinutes) {
  final day = dateFromKey(date);
  return DateTime.utc(
        day.year,
        day.month,
        day.day,
        hour,
        minute,
      ).millisecondsSinceEpoch -
      offsetMinutes * 60000;
}

void main() {
  group('FinanceFutureCommitmentsService', () {
    test('自然月范围包含今天并严格排除结束月', () {
      final now = DateTime(2026, 10, 31, 20);
      final rule = _rule(
        uuid: 'monthly-rent',
        name: '月末房租',
        startDate: '2026-01-01',
      );

      final forecast = FinanceFutureCommitmentsService.project(
        now: now,
        horizonMonths: 3,
        recurringRules: [rule],
        loans: const [],
        installmentsByLoan: const {},
      );

      expect(forecast.endExclusive, DateTime(2027, 1, 1));
      expect(forecast.commitments.map((item) => item.dueAt), [
        DateTime(2026, 10, 31, 9),
        DateTime(2026, 11, 30, 9),
        DateTime(2026, 12, 31, 9),
      ]);
    });

    test('年度规则遵循闰年和规则起止日，停用或删除规则不展开', () {
      final leapYear = _rule(
        uuid: 'leap',
        name: '年度保险',
        startDate: '2024-02-29',
        frequency: FinanceRecurringFrequency.yearly,
        month: 2,
        day: 29,
      );
      final futureStart = _rule(
        uuid: 'future-start',
        name: '未来才开始',
        startDate: '2029-01-01',
      );
      final disabled = _rule(
        uuid: 'disabled',
        name: '暂停规则',
        startDate: '2026-01-01',
        enabled: false,
      );
      final deleted = _rule(
        uuid: 'deleted',
        name: '删除规则',
        startDate: '2026-01-01',
        deleted: true,
      );

      final leapForecast = FinanceFutureCommitmentsService.project(
        now: DateTime(2028, 1, 1),
        horizonMonths: 12,
        recurringRules: [leapYear, futureStart, disabled, deleted],
        loans: const [],
        installmentsByLoan: const {},
      );
      final nextYearForecast = FinanceFutureCommitmentsService.project(
        now: DateTime(2029, 1, 1),
        horizonMonths: 3,
        recurringRules: [leapYear],
        loans: const [],
        installmentsByLoan: const {},
      );

      expect(leapForecast.commitments.single.dueAt, DateTime(2028, 2, 29, 9));
      expect(
        nextYearForecast.commitments.single.dueAt,
        DateTime(2029, 2, 28, 9),
      );
      expect(leapForecast.commitments.single.recurringRule!.uuid, 'leap');
    });

    test('已物化周期按稳定账单 UUID 去重，退款计入流入', () {
      final rent = _rule(
        uuid: 'rent',
        name: '房租',
        startDate: '2026-01-01',
        day: 25,
      );
      final refund = _rule(
        uuid: 'refund',
        name: '月度退款',
        startDate: '2026-01-01',
        day: 26,
        amountMinor: 1200,
        type: FinanceTransactionType.refund,
        currencyCode: 'USD',
      );
      final materialized = FinanceRecurringRule.transactionUuidForPeriod(
        'rent',
        '2026-10',
      );

      final forecast = FinanceFutureCommitmentsService.project(
        now: DateTime(2026, 10, 24, 18),
        horizonMonths: 3,
        recurringRules: [rent, refund],
        loans: const [],
        installmentsByLoan: const {},
        materializedRecurringTransactionUuids: {materialized},
      );

      expect(
        forecast.commitments.any((item) => item.id == 'recurring:rent:2026-10'),
        isFalse,
      );
      expect(forecast.totalsByCurrency['USD']!.inflowMinor, 3600);
      expect(forecast.totalsByCurrency['USD']!.outflowMinor, 0);
      expect(forecast.totalsByCurrency['CNY']!.outflowMinor, 20000);
    });

    test('逾期待还单列，已还删除及删除贷款期次排除，月度合计分币种', () {
      final cnyLoan = _loan(uuid: 'cny-loan');
      final usdLoan = _loan(uuid: 'usd-loan', currencyCode: 'USD');
      final deletedLoan = _loan(uuid: 'deleted-loan', deleted: true);
      final overdue = _installment(
        uuid: 'overdue',
        loanUuid: cnyLoan.uuid,
        dueDate: '2026-10-23',
        paymentMinor: 9000,
      );
      final dueToday = _installment(
        uuid: 'due-today',
        loanUuid: usdLoan.uuid,
        dueDate: '2026-10-24',
        paymentMinor: 7000,
      );
      final paid = _installment(
        uuid: 'paid',
        loanUuid: cnyLoan.uuid,
        dueDate: '2026-10-25',
        paid: true,
      );
      final trashed = _installment(
        uuid: 'trashed',
        loanUuid: cnyLoan.uuid,
        dueDate: '2026-10-26',
        deleted: true,
      );
      final linkedToDeletedLoan = _installment(
        uuid: 'deleted-loan-plan',
        loanUuid: deletedLoan.uuid,
        dueDate: '2026-10-27',
      );
      final outside = _installment(
        uuid: 'outside',
        loanUuid: cnyLoan.uuid,
        dueDate: '2027-01-01',
      );

      final forecast = FinanceFutureCommitmentsService.project(
        now: DateTime(2026, 10, 24, 12),
        horizonMonths: 3,
        recurringRules: const [],
        loans: [cnyLoan, usdLoan, deletedLoan],
        installmentsByLoan: {
          cnyLoan.uuid: [overdue, paid, trashed, outside],
          usdLoan.uuid: [dueToday, dueToday],
          deletedLoan.uuid: [linkedToDeletedLoan],
        },
      );

      expect(forecast.overdueLoanInstallments.map((item) => item.id), [
        'loan:overdue',
      ]);
      expect(forecast.commitments.map((item) => item.id), ['loan:due-today']);
      expect(forecast.totalsByCurrency.keys, ['USD']);
      expect(forecast.totalsByCurrency['USD']!.outflowMinor, 7000);
      expect(
        forecast.monthlyTotalsByCurrency['2026-10']!['USD']!.netMinor,
        -7000,
      );
    });

    test('只允许3、6、12个月的自然月范围', () {
      expect(
        FinanceFutureCommitmentsService.endExclusiveFor(
          DateTime(2026, 10, 24),
          6,
        ),
        DateTime(2027, 4, 1),
      );
      expect(
        () => FinanceFutureCommitmentsService.endExclusiveFor(
          DateTime(2026, 10, 24),
          4,
        ),
        throwsArgumentError,
      );
    });

    test('纳入范围内未来手工账单，排除今天已发生、软删除和窗口外账单', () {
      final now = DateTime(2026, 10, 24, 14);
      final offset = now.timeZoneOffset.inMinutes;
      final todayUnknownTime = _transaction(
        uuid: 'today-unknown-time',
        transactionDate: '2026-10-24',
        createdAt: now.millisecondsSinceEpoch - 60000,
        timezoneOffsetMinutes: offset,
      )..occurredAt = null;
      final forecast = FinanceFutureCommitmentsService.project(
        now: now,
        horizonMonths: 3,
        recurringRules: const [],
        loans: const [],
        installmentsByLoan: const {},
        transactions: [
          _transaction(
            uuid: 'today-upcoming',
            transactionDate: '2026-10-24',
            occurredAt: now.millisecondsSinceEpoch + 3600000,
            createdAt: now.millisecondsSinceEpoch - 60000,
            timezoneOffsetMinutes: offset + 120,
          ),
          _transaction(
            uuid: 'today-past',
            transactionDate: '2026-10-24',
            occurredAt: _localEpoch('2026-10-24', 13, 0, offset),
            createdAt: now.millisecondsSinceEpoch - 60000,
            timezoneOffsetMinutes: offset,
          ),
          _transaction(
            uuid: 'tomorrow',
            transactionDate: '2026-10-25',
            occurredAt: now.millisecondsSinceEpoch - 3600000,
            createdAt: now.millisecondsSinceEpoch - 3600000,
            timezoneOffsetMinutes: offset,
          ),
          _transaction(
            uuid: 'deleted',
            transactionDate: '2026-10-26',
            deleted: true,
          ),
          _transaction(uuid: 'outside-window', transactionDate: '2027-01-01'),
          _transaction(uuid: 'yesterday', transactionDate: '2026-10-23'),
          todayUnknownTime,
        ],
      );

      expect(forecast.commitments.map((item) => item.id).toSet(), {
        'transaction:today-upcoming',
        'transaction:tomorrow',
      });
      expect(forecast.totalsByCurrency['CNY']!.outflowMinor, 20000);
    });

    test('收入与退款按流入统计，可能重叠只提示而不静默去重', () {
      final now = DateTime(2026, 10, 24, 10);
      final rent = _rule(
        uuid: 'overlap-rent',
        name: '房租规则',
        startDate: '2026-01-01',
        day: 25,
        amountMinor: 10000,
      );
      final loan = _loan(uuid: 'overlap-loan');
      final installment = _installment(
        uuid: 'overlap-installment',
        loanUuid: loan.uuid,
        dueDate: '2026-10-25',
        paymentMinor: 10000,
      );
      final matchingExpense = _transaction(
        uuid: 'matching-expense',
        transactionDate: '2026-10-25',
      );
      final nearMatch = _transaction(
        uuid: 'near-match',
        transactionDate: '2026-10-25',
        amountMinor: 10001,
      );
      final income = _transaction(
        uuid: 'future-income',
        transactionDate: '2026-10-27',
        type: FinanceTransactionType.income,
        amountMinor: 2500,
      );
      final refund = _transaction(
        uuid: 'future-refund',
        transactionDate: '2026-10-28',
        type: FinanceTransactionType.refund,
        amountMinor: 500,
      );
      final wrongCurrency = _transaction(
        uuid: 'wrong-currency',
        transactionDate: '2026-10-25',
        amountMinor: 10000,
        currencyCode: 'USD',
      );
      final wrongDirection = _transaction(
        uuid: 'wrong-direction',
        transactionDate: '2026-10-25',
        amountMinor: 10000,
        type: FinanceTransactionType.income,
      );
      final wrongDate = _transaction(
        uuid: 'wrong-date',
        transactionDate: '2026-10-26',
        amountMinor: 10000,
      );

      final forecast = FinanceFutureCommitmentsService.project(
        now: now,
        horizonMonths: 3,
        recurringRules: [rent],
        loans: [loan],
        installmentsByLoan: {
          loan.uuid: [installment],
        },
        transactions: [
          matchingExpense,
          nearMatch,
          income,
          refund,
          wrongCurrency,
          wrongDirection,
          wrongDate,
        ],
      );

      final matching = forecast.commitments.singleWhere(
        (item) => item.id == 'transaction:matching-expense',
      );
      expect(matching.possibleOverlapLabels, [
        '周期计划“房租规则”',
        '贷款计划“测试贷款 overlap-loan”',
      ]);
      expect(
        forecast.commitments
            .singleWhere((item) => item.id == 'transaction:near-match')
            .possibleOverlapLabels,
        isEmpty,
      );
      expect(forecast.totalsByCurrency['CNY']!.inflowMinor, 13000);
      expect(forecast.totalsByCurrency['CNY']!.outflowMinor, 70001);
      expect(forecast.totalsByCurrency['USD']!.outflowMinor, 10000);
      for (final id in [
        'transaction:wrong-currency',
        'transaction:wrong-direction',
        'transaction:wrong-date',
      ]) {
        expect(
          forecast.commitments
              .singleWhere((item) => item.id == id)
              .possibleOverlapLabels,
          isEmpty,
        );
      }
    });

    test('已生成的周期账单以真实账单行显示且只计一次', () {
      final rent = _rule(
        uuid: 'materialized-rent',
        name: '已生成房租',
        startDate: '2026-01-01',
        day: 25,
      );
      final uuid = FinanceRecurringRule.transactionUuidForPeriod(
        rent.uuid,
        '2026-10',
      );
      final forecast = FinanceFutureCommitmentsService.project(
        now: DateTime(2026, 10, 24, 10),
        horizonMonths: 3,
        recurringRules: [rent],
        loans: const [],
        installmentsByLoan: const {},
        transactions: [_transaction(uuid: uuid, transactionDate: '2026-10-25')],
        materializedRecurringTransactionUuids: {uuid},
      );

      expect(forecast.commitments, hasLength(3));
      expect(
        forecast.commitments.where(
          (item) => dateKey(item.dueAt) == '2026-10-25',
        ),
        hasLength(1),
      );
      expect(forecast.commitments.first.id, 'transaction:$uuid');
      expect(forecast.totalsByCurrency['CNY']!.outflowMinor, 30000);
    });
  });
}
