import '../models/finance_models.dart';
import 'finance_automation_service.dart';
import 'finance_repository.dart';

class FinanceFutureCommitment {
  const FinanceFutureCommitment._({
    required this.id,
    required this.dueAt,
    required this.currencyCode,
    required this.amountMinor,
    this.transactionType,
    this.recurringRule,
    this.periodKey,
    this.loan,
    this.installment,
  });

  factory FinanceFutureCommitment.recurring(FinanceRecurringDue due) =>
      FinanceFutureCommitment._(
        id: 'recurring:${due.rule.uuid}:${due.periodKey}',
        dueAt: due.dueAt,
        currencyCode: due.rule.currencyCode,
        amountMinor: due.rule.amountMinor,
        transactionType: due.rule.type,
        recurringRule: due.rule,
        periodKey: due.periodKey,
      );

  factory FinanceFutureCommitment.loanInstallment({
    required FinanceLoan loan,
    required FinanceLoanInstallment installment,
  }) => FinanceFutureCommitment._(
    id: 'loan:${installment.uuid}',
    dueAt: dateFromKey(installment.dueDate),
    currencyCode: loan.currencyCode,
    amountMinor: installment.paymentMinor,
    loan: loan,
    installment: installment,
  );

  final String id;
  final DateTime dueAt;
  final String currencyCode;
  final int amountMinor;
  final FinanceTransactionType? transactionType;
  final FinanceRecurringRule? recurringRule;
  final String? periodKey;
  final FinanceLoan? loan;
  final FinanceLoanInstallment? installment;

  bool get isLoanInstallment => installment != null;
  int get inflowMinor =>
      !isLoanInstallment && transactionType != FinanceTransactionType.expense
      ? amountMinor
      : 0;
  int get outflowMinor =>
      isLoanInstallment || transactionType == FinanceTransactionType.expense
      ? amountMinor
      : 0;
}

class FinanceFutureCommitmentTotals {
  const FinanceFutureCommitmentTotals({
    this.inflowMinor = 0,
    this.outflowMinor = 0,
  });

  final int inflowMinor;
  final int outflowMinor;
  int get netMinor => inflowMinor - outflowMinor;

  FinanceFutureCommitmentTotals add(FinanceFutureCommitment item) =>
      FinanceFutureCommitmentTotals(
        inflowMinor: inflowMinor + item.inflowMinor,
        outflowMinor: outflowMinor + item.outflowMinor,
      );
}

class FinanceFutureCommitmentForecast {
  const FinanceFutureCommitmentForecast({
    required this.now,
    required this.horizonMonths,
    required this.endExclusive,
    required this.commitments,
    required this.overdueLoanInstallments,
    required this.totalsByCurrency,
    required this.monthlyTotalsByCurrency,
  });

  final DateTime now;
  final int horizonMonths;
  final DateTime endExclusive;
  final List<FinanceFutureCommitment> commitments;
  final List<FinanceFutureCommitment> overdueLoanInstallments;
  final Map<String, FinanceFutureCommitmentTotals> totalsByCurrency;
  final Map<String, Map<String, FinanceFutureCommitmentTotals>>
  monthlyTotalsByCurrency;
}

abstract final class FinanceFutureCommitmentsService {
  static DateTime endExclusiveFor(DateTime now, int horizonMonths) {
    if (![3, 6, 12].contains(horizonMonths)) {
      throw ArgumentError.value(horizonMonths, 'horizonMonths');
    }
    return DateTime(now.year, now.month + horizonMonths);
  }

  static Future<FinanceFutureCommitmentForecast> read({
    required DateTime now,
    int horizonMonths = 3,
  }) async {
    final endExclusive = endExclusiveFor(now, horizonMonths);
    final today = DateTime(now.year, now.month, now.day);
    final values = await Future.wait<dynamic>([
      FinanceRepository.getRecurringRules(),
      FinanceRepository.getLoans(),
      FinanceRepository.getLoanInstallmentsForActiveLoans(
        toDueDate: dateKey(endExclusive),
      ),
    ]);
    final rules = values[0] as List<FinanceRecurringRule>;
    final upcoming = FinanceAutomationService.upcoming(
      rules: rules,
      now: today,
      limit: endExclusive,
    );
    final materializedUuids =
        await FinanceRepository.getExistingTransactionUuids([
          for (final due in upcoming)
            FinanceRecurringRule.transactionUuidForPeriod(
              due.rule.uuid,
              due.periodKey,
            ),
        ]);
    return project(
      now: now,
      horizonMonths: horizonMonths,
      recurringRules: rules,
      loans: values[1] as List<FinanceLoan>,
      installmentsByLoan:
          values[2] as Map<String, List<FinanceLoanInstallment>>,
      materializedRecurringTransactionUuids: materializedUuids,
    );
  }

  static FinanceFutureCommitmentForecast project({
    required DateTime now,
    required int horizonMonths,
    required Iterable<FinanceRecurringRule> recurringRules,
    required Iterable<FinanceLoan> loans,
    required Map<String, List<FinanceLoanInstallment>> installmentsByLoan,
    Set<String> materializedRecurringTransactionUuids = const {},
  }) {
    final endExclusive = endExclusiveFor(now, horizonMonths);
    final today = DateTime(now.year, now.month, now.day);
    final dues = FinanceAutomationService.upcoming(
      rules: recurringRules.toList(growable: false),
      now: today,
      limit: endExclusive,
    );
    final materialized = materializedRecurringTransactionUuids;
    final commitments = <FinanceFutureCommitment>[
      for (final due in dues)
        if (!materialized.contains(
          FinanceRecurringRule.transactionUuidForPeriod(
            due.rule.uuid,
            due.periodKey,
          ),
        ))
          FinanceFutureCommitment.recurring(due),
    ];
    final loansByUuid = {
      for (final loan in loans)
        if (!loan.isDeleted) loan.uuid: loan,
    };
    final overdue = <FinanceFutureCommitment>[];
    final seenInstallments = <String>{};
    for (final entry in installmentsByLoan.entries) {
      final loan = loansByUuid[entry.key];
      if (loan == null) continue;
      for (final installment in entry.value) {
        if (installment.isDeleted ||
            installment.isPaid ||
            installment.loanUuid != loan.uuid ||
            !seenInstallments.add(installment.uuid)) {
          continue;
        }
        final dueDate = dateFromKey(installment.dueDate);
        final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
        final item = FinanceFutureCommitment.loanInstallment(
          loan: loan,
          installment: installment,
        );
        if (dueDay.isBefore(today)) {
          overdue.add(item);
        } else if (dueDay.isBefore(endExclusive)) {
          commitments.add(item);
        }
      }
    }
    commitments.sort(_compareCommitments);
    overdue.sort(_compareCommitments);

    final totalsByCurrency = <String, FinanceFutureCommitmentTotals>{};
    final monthlyTotalsByCurrency =
        <String, Map<String, FinanceFutureCommitmentTotals>>{};
    for (final item in commitments) {
      final currency = item.currencyCode;
      totalsByCurrency[currency] =
          (totalsByCurrency[currency] ?? const FinanceFutureCommitmentTotals())
              .add(item);
      final month = financeMonthKey(item.dueAt);
      final monthly = monthlyTotalsByCurrency.putIfAbsent(
        month,
        () => <String, FinanceFutureCommitmentTotals>{},
      );
      monthly[currency] =
          (monthly[currency] ?? const FinanceFutureCommitmentTotals()).add(
            item,
          );
    }
    return FinanceFutureCommitmentForecast(
      now: now,
      horizonMonths: horizonMonths,
      endExclusive: endExclusive,
      commitments: List.unmodifiable(commitments),
      overdueLoanInstallments: List.unmodifiable(overdue),
      totalsByCurrency: Map.unmodifiable(totalsByCurrency),
      monthlyTotalsByCurrency: Map.unmodifiable({
        for (final entry in monthlyTotalsByCurrency.entries)
          entry.key: Map<String, FinanceFutureCommitmentTotals>.unmodifiable(
            entry.value,
          ),
      }),
    );
  }

  static int _compareCommitments(
    FinanceFutureCommitment left,
    FinanceFutureCommitment right,
  ) {
    final date = left.dueAt.compareTo(right.dueAt);
    return date != 0 ? date : left.id.compareTo(right.id);
  }
}
