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
    this.transaction,
    this.possibleOverlapLabels = const [],
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

  factory FinanceFutureCommitment.transaction(FinanceTransaction transaction) =>
      FinanceFutureCommitment._(
        id: 'transaction:${transaction.uuid}',
        dueAt: dateFromKey(transaction.transactionDate),
        currencyCode: transaction.currencyCode,
        amountMinor: transaction.amountMinor,
        transactionType: transaction.type,
        transaction: transaction,
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
  final FinanceTransaction? transaction;
  final List<String> possibleOverlapLabels;

  bool get isLoanInstallment => installment != null;
  bool get isTransaction => transaction != null;
  int get inflowMinor =>
      !isLoanInstallment && transactionType != FinanceTransactionType.expense
      ? amountMinor
      : 0;
  int get outflowMinor =>
      isLoanInstallment || transactionType == FinanceTransactionType.expense
      ? amountMinor
      : 0;

  FinanceFutureCommitment withPossibleOverlapLabels(Iterable<String> labels) =>
      FinanceFutureCommitment._(
        id: id,
        dueAt: dueAt,
        currencyCode: currencyCode,
        amountMinor: amountMinor,
        transactionType: transactionType,
        recurringRule: recurringRule,
        periodKey: periodKey,
        loan: loan,
        installment: installment,
        transaction: transaction,
        possibleOverlapLabels: List.unmodifiable(labels),
      );
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
      FinanceRepository.getTransactions(from: today, to: endExclusive),
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
      transactions: values[3] as List<FinanceTransaction>,
      materializedRecurringTransactionUuids: materializedUuids,
    );
  }

  static FinanceFutureCommitmentForecast project({
    required DateTime now,
    required int horizonMonths,
    required Iterable<FinanceRecurringRule> recurringRules,
    required Iterable<FinanceLoan> loans,
    required Map<String, List<FinanceLoanInstallment>> installmentsByLoan,
    Iterable<FinanceTransaction> transactions = const [],
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
      for (final transaction in transactions)
        if (_isFutureTransaction(transaction, now, today, endExclusive))
          FinanceFutureCommitment.transaction(transaction),
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

    final commitmentsWithOverlapHints = [
      for (final item in commitments)
        if (item.isTransaction)
          item.withPossibleOverlapLabels(
            _possibleOverlapLabels(item, commitments),
          )
        else
          item,
    ];

    final totalsByCurrency = <String, FinanceFutureCommitmentTotals>{};
    final monthlyTotalsByCurrency =
        <String, Map<String, FinanceFutureCommitmentTotals>>{};
    for (final item in commitmentsWithOverlapHints) {
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
      commitments: List.unmodifiable(commitmentsWithOverlapHints),
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

  static bool _isFutureTransaction(
    FinanceTransaction transaction,
    DateTime now,
    DateTime today,
    DateTime endExclusive,
  ) {
    if (transaction.isDeleted ||
        !isFinanceDateKey(transaction.transactionDate)) {
      return false;
    }
    final ledgerDay = dateFromKey(transaction.transactionDate);
    final day = DateTime(ledgerDay.year, ledgerDay.month, ledgerDay.day);
    if (day.isBefore(today) || !day.isBefore(endExclusive)) return false;
    if (dateKey(day) == dateKey(today)) {
      return transaction.balanceEventAt() > now.millisecondsSinceEpoch;
    }
    return true;
  }

  static List<String> _possibleOverlapLabels(
    FinanceFutureCommitment transaction,
    List<FinanceFutureCommitment> allCommitments,
  ) {
    final labels = <String>{};
    for (final planned in allCommitments) {
      if (planned.isTransaction ||
          dateKey(planned.dueAt) != dateKey(transaction.dueAt) ||
          planned.currencyCode.toUpperCase() !=
              transaction.currencyCode.toUpperCase() ||
          planned.amountMinor != transaction.amountMinor ||
          (planned.inflowMinor > 0) != (transaction.inflowMinor > 0)) {
        continue;
      }
      final ruleName = planned.recurringRule?.name.trim();
      if (ruleName != null && ruleName.isNotEmpty) {
        labels.add('周期计划“$ruleName”');
        continue;
      }
      final loanName = planned.loan?.name.trim();
      if (loanName != null && loanName.isNotEmpty) {
        labels.add('贷款计划“$loanName”');
      }
    }
    return labels.toList()..sort();
  }

  static int _compareCommitments(
    FinanceFutureCommitment left,
    FinanceFutureCommitment right,
  ) {
    final date = left.dueAt.compareTo(right.dueAt);
    return date != 0 ? date : left.id.compareTo(right.id);
  }
}
