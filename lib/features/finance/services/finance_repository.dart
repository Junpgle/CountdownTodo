import 'dart:async';

import 'package:intl/intl.dart';

import '../../../services/browser_file_service.dart';
import '../../../services/reminder_schedule_service.dart';
import '../models/finance_models.dart';
import 'finance_automation_service.dart';
import 'finance_storage.dart';

/// Moves a trusted occurrence wall time to another ledger date without
/// changing the transaction's recorded timezone. Unknown or mismatched legacy
/// occurrence times remain unknown.
int? financeOccurrenceTimestampForDate(
  FinanceTransaction transaction,
  String targetDate,
) {
  final occurrence = transaction.occurrenceLocalTime;
  if (occurrence == null ||
      dateKey(occurrence) != transaction.transactionDate) {
    return null;
  }
  final date = dateFromKey(targetDate);
  return DateTime.utc(
        date.year,
        date.month,
        date.day,
        occurrence.hour,
        occurrence.minute,
        occurrence.second,
        occurrence.millisecond,
        occurrence.microsecond,
      ).millisecondsSinceEpoch -
      transaction.timezoneOffsetMinutes * 60000;
}

abstract final class FinanceRepository {
  static Future<List<FinanceTransaction>> getTransactions({
    DateTime? from,
    DateTime? to,
    String? keyword,
    FinanceTransactionType? type,
    int? limit,
  }) {
    return FinanceStorage.getTransactions(
      from: from,
      to: to,
      keyword: keyword,
      type: type,
      limit: limit,
    );
  }

  static Future<List<FinanceTransaction>> getBalanceTransactions({
    required int snapshotAt,
    required DateTime before,
    required Iterable<String> paymentMethodUuids,
  }) {
    return FinanceStorage.getBalanceTransactions(
      snapshotAt: snapshotAt,
      before: before,
      paymentMethodUuids: paymentMethodUuids,
    );
  }

  static Future<FinanceTransaction?> getTransaction(String uuid) {
    return FinanceStorage.getTransaction(uuid);
  }

  static Future<List<FinanceTransaction>> getRefundsForTransaction(
    String transactionUuid, {
    bool includeDeleted = false,
  }) {
    return FinanceStorage.getRefundsForTransaction(
      transactionUuid,
      includeDeleted: includeDeleted,
    );
  }

  static Future<int> getRemainingRefundableMinor(
    String transactionUuid, {
    String? excludingRefundUuid,
  }) {
    return FinanceStorage.getRemainingRefundableMinor(
      transactionUuid,
      excludingRefundUuid: excludingRefundUuid,
    );
  }

  static Future<FinanceSummary> getSummary({
    required DateTime from,
    required DateTime to,
  }) {
    return FinanceStorage.getSummary(from: from, to: to);
  }

  static Future<List<FinanceCategory>> getCategories({
    FinanceCategoryType? type,
    bool includeArchived = false,
    bool includeDeleted = false,
  }) {
    return FinanceStorage.getCategories(
      type: type,
      includeArchived: includeArchived,
      includeDeleted: includeDeleted,
    );
  }

  static Future<List<FinancePaymentMethod>> getPaymentMethods({
    bool includeArchived = false,
  }) {
    return FinanceStorage.getPaymentMethods(includeArchived: includeArchived);
  }

  /// Builds the same summary used by the overview from an already loaded list.
  ///
  /// Keeping this computation separate lets callers that already need the
  /// overview range avoid issuing a second database query for the month.
  static FinanceSummary summarizeTransactions(
    Iterable<FinanceTransaction> transactions,
  ) {
    return FinanceSummary.fromTransactions(transactions);
  }

  /// Loads the compact event history needed to calculate a carried-forward
  /// balance without retaining every transaction in the overview widget.
  static Future<List<FinanceCumulativeBalanceEvent>>
  getCumulativeBalanceEvents({required int throughAt}) async {
    final date = DateTime.fromMillisecondsSinceEpoch(throughAt);
    final transactions = await getTransactions(
      to: DateTime(date.year, date.month, date.day + 2),
    );
    final events =
        transactions
            .map((transaction) {
              final changeMinor = switch (transaction.type) {
                FinanceTransactionType.income ||
                FinanceTransactionType.refund => transaction.amountMinor,
                FinanceTransactionType.expense => -transaction.amountMinor,
              };
              return FinanceCumulativeBalanceEvent(
                transactionDate: transaction.transactionDate,
                eventAt: transaction.balanceEventAt(),
                changeMinor: changeMinor,
              );
            })
            .toList(growable: false)
          ..sort((left, right) => left.eventAt.compareTo(right.eventAt));
    return events;
  }

  /// Returns the opening balance plus ledger movements through [asOfAt].
  /// A configured opening date is inclusive: movements recorded on that date
  /// are applied on top of the opening amount.
  static int? cumulativeBalanceAt({
    required Iterable<FinanceCumulativeBalanceEvent> events,
    required int asOfAt,
    required int openingBalanceMinor,
    String? openingBalanceStartDate,
  }) {
    final startDate = openingBalanceStartDate;
    if (startDate != null && !isFinanceDateKey(startDate)) return null;
    final asOfDate = dateKey(DateTime.fromMillisecondsSinceEpoch(asOfAt));
    if (startDate != null && asOfDate.compareTo(startDate) < 0) return null;

    var balanceMinor = openingBalanceMinor;
    for (final event in events) {
      if (event.eventAt > asOfAt) break;
      if (startDate != null && event.transactionDate.compareTo(startDate) < 0) {
        continue;
      }
      balanceMinor += event.changeMinor;
    }
    return balanceMinor;
  }

  /// Picks the earliest recorded ledger date that has already occurred.
  /// Future scheduled bills must not become an opening date users can save.
  static String defaultCumulativeBalanceStartDate({
    required Iterable<FinanceCumulativeBalanceEvent> events,
    required int nowAt,
  }) {
    String? earliestDate;
    for (final event in events) {
      if (event.eventAt > nowAt || !isFinanceDateKey(event.transactionDate)) {
        continue;
      }
      if (earliestDate == null ||
          event.transactionDate.compareTo(earliestDate) < 0) {
        earliestDate = event.transactionDate;
      }
    }
    return earliestDate ?? dateKey(DateTime.fromMillisecondsSinceEpoch(nowAt));
  }

  /// Selects the latest usable account snapshot at [asOfAt] for every payment
  /// method. Snapshot month keys are kept because their epoch can cross a
  /// local month boundary after sync to a device in another timezone.
  static List<FinanceBudget> latestPaymentBalanceSnapshots(
    Iterable<FinanceBudget> budgets, {
    required int asOfAt,
    required int nowAt,
  }) {
    final asOfDate = DateTime.fromMillisecondsSinceEpoch(asOfAt);
    final asOfMonthKey = financeMonthKey(asOfDate);
    const snapshotTimezoneDriftMs = 28 * 60 * 60 * 1000;
    final nextMonthStartAt = DateTime(
      asOfDate.year,
      asOfDate.month + 1,
    ).millisecondsSinceEpoch;
    final latestByMethod = <String, FinanceBudget>{};
    for (final budget in budgets) {
      final paymentMethodUuid = budget.paymentMethodUuid;
      final snapshotAt = budget.effectiveBalanceSnapshotAt;
      final monthOrder = budget.monthKey.compareTo(asOfMonthKey);
      // A synced snapshot's month key and epoch can land on opposite sides of
      // the local month boundary. Accept either adjacent-month representation
      // only within the timezone drift window.
      final currentKeyTimestampInNextMonth =
          monthOrder == 0 &&
          snapshotAt >= nextMonthStartAt &&
          asOfAt >= nextMonthStartAt - snapshotTimezoneDriftMs &&
          snapshotAt <= asOfAt + snapshotTimezoneDriftMs;
      final nextKeyTimestampInCurrentMonth =
          monthOrder == 1 &&
          snapshotAt < nextMonthStartAt &&
          snapshotAt >= nextMonthStartAt - snapshotTimezoneDriftMs &&
          snapshotAt <= asOfAt;
      if (paymentMethodUuid == null ||
          paymentMethodUuid.isEmpty ||
          (monthOrder > 0 && !nextKeyTimestampInCurrentMonth) ||
          (monthOrder == 0 &&
              snapshotAt > asOfAt &&
              !currentKeyTimestampInNextMonth) ||
          (monthOrder < 0 && snapshotAt > asOfAt) ||
          snapshotAt > nowAt) {
        continue;
      }
      final current = latestByMethod[paymentMethodUuid];
      if (current == null) {
        latestByMethod[paymentMethodUuid] = budget;
        continue;
      }
      final currentSnapshotAt = current.effectiveBalanceSnapshotAt;
      final snapshotMonthOrder = budget.monthKey.compareTo(current.monthKey);
      final isLaterSnapshot =
          snapshotAt > currentSnapshotAt ||
          (snapshotAt == currentSnapshotAt &&
              (snapshotMonthOrder > 0 ||
                  (snapshotMonthOrder == 0 &&
                      budget.updatedAt > current.updatedAt)));
      if (isLaterSnapshot) {
        latestByMethod[paymentMethodUuid] = budget;
      }
    }
    return latestByMethod.values.toList(growable: false);
  }

  /// Reconstructs an account's current balance from its saved snapshot,
  /// transaction movements and separately stored loan repayments.
  static int paymentMethodBalanceAt({
    required FinanceBudget snapshot,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinanceLoanInstallment> loanRepayments,
    required Set<String> loanInterestTransactionUuids,
    required int asOfAt,
  }) {
    final paymentMethodUuid = snapshot.paymentMethodUuid;
    if (paymentMethodUuid == null || paymentMethodUuid.isEmpty) {
      throw ArgumentError.value(snapshot, 'snapshot', '必须是付款方式余额快照');
    }
    return paymentMethodBalancesAt(
      snapshots: [snapshot],
      transactions: transactions,
      loanRepayments: loanRepayments,
      loanInterestTransactionUuids: loanInterestTransactionUuids,
      asOfAt: asOfAt,
    )[paymentMethodUuid]!;
  }

  /// Reconstructs multiple account balances while visiting each transaction
  /// and repayment only once. Callers should pass the latest snapshot for
  /// each payment method; if duplicates are present, the last one wins.
  static Map<String, int> paymentMethodBalancesAt({
    required Iterable<FinanceBudget> snapshots,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinanceLoanInstallment> loanRepayments,
    required Set<String> loanInterestTransactionUuids,
    required int asOfAt,
  }) {
    final snapshotsByMethod = <String, FinanceBudget>{};
    for (final snapshot in snapshots) {
      final paymentMethodUuid = snapshot.paymentMethodUuid;
      if (paymentMethodUuid == null || paymentMethodUuid.isEmpty) {
        throw ArgumentError.value(snapshot, 'snapshot', '必须是付款方式余额快照');
      }
      snapshotsByMethod[paymentMethodUuid] = snapshot;
    }
    if (snapshotsByMethod.isEmpty) return const <String, int>{};

    final balanceChanges = <String, int>{};
    for (final transaction in transactions) {
      final paymentMethodUuid = transaction.paymentMethodUuid;
      final snapshot = snapshotsByMethod[paymentMethodUuid];
      if (snapshot == null ||
          loanInterestTransactionUuids.contains(transaction.uuid)) {
        continue;
      }
      final snapshotAt = snapshot.effectiveBalanceSnapshotAt;
      final eventAt = transaction.balanceEventAt(snapshotAt: snapshotAt);
      if (eventAt <= snapshotAt || eventAt > asOfAt) continue;
      final amount = transaction.type == FinanceTransactionType.expense
          ? -transaction.amountMinor
          : transaction.amountMinor;
      balanceChanges[paymentMethodUuid!] =
          (balanceChanges[paymentMethodUuid] ?? 0) + amount;
    }

    final repaymentChanges = <String, int>{};
    for (final repayment in loanRepayments) {
      final paymentMethodUuid = repayment.paymentMethodUuid;
      final snapshot = snapshotsByMethod[paymentMethodUuid];
      final paidAt = repayment.paidAt;
      if (snapshot == null || paidAt == null) continue;
      final snapshotAt = snapshot.effectiveBalanceSnapshotAt;
      // Match transaction.balanceEventAt: when a repayment is recorded after
      // a balance snapshot in the same minute, its paidAt can equal the
      // snapshot time because the picker stores minute precision. Use the
      // repayment edit time so it applies only from when it became available.
      final eventAt =
          paidAt <= snapshotAt &&
              paidAt ~/ 60000 == snapshotAt ~/ 60000 &&
              repayment.updatedAt > snapshotAt
          ? repayment.updatedAt
          : paidAt;
      if (eventAt <= snapshotAt || eventAt > asOfAt) continue;
      repaymentChanges[paymentMethodUuid!] =
          (repaymentChanges[paymentMethodUuid] ?? 0) +
          repayment.paymentMinor;
    }

    return {
      for (final entry in snapshotsByMethod.entries)
        entry.key:
            entry.value.amountMinor +
            (balanceChanges[entry.key] ?? 0) -
            (repaymentChanges[entry.key] ?? 0),
    };
  }

  /// Returns net monthly spending grouped by payment method; linked refunds
  /// reduce the amount used by the method they were recorded under.
  static Map<String, int> summarizePaymentMethodSpending(
    Iterable<FinanceTransaction> transactions,
  ) {
    final spending = <String, int>{};
    for (final transaction in transactions) {
      final methodUuid = transaction.paymentMethodUuid;
      if (methodUuid == null || methodUuid.isEmpty) continue;
      switch (transaction.type) {
        case FinanceTransactionType.expense:
          spending[methodUuid] =
              (spending[methodUuid] ?? 0) + transaction.amountMinor;
        case FinanceTransactionType.refund:
          spending[methodUuid] =
              (spending[methodUuid] ?? 0) - transaction.amountMinor;
        case FinanceTransactionType.income:
          break;
      }
    }
    return spending;
  }

  /// Returns the signed change to each payment method's recorded balance.
  /// Income and refunds add to the balance; expenses reduce it.
  static Map<String, int> summarizePaymentMethodBalanceChanges(
    Iterable<FinanceTransaction> transactions,
  ) {
    final changes = <String, int>{};
    for (final transaction in transactions) {
      final methodUuid = transaction.paymentMethodUuid;
      if (methodUuid == null || methodUuid.isEmpty) continue;
      final amount = transaction.type == FinanceTransactionType.expense
          ? -transaction.amountMinor
          : transaction.amountMinor;
      changes[methodUuid] = (changes[methodUuid] ?? 0) + amount;
    }
    return changes;
  }

  static Future<void> saveTransaction(
    FinanceTransaction transaction, {
    FinanceTransaction? original,
  }) async {
    await FinanceStorage.saveTransaction(transaction, original: original);
    await _checkBudgetAlertsSafely();
  }

  static Future<void> _checkBudgetAlertsSafely() async {
    try {
      await FinanceAutomationService.checkBudgetAlerts();
    } catch (_) {
      // Notification failures must not roll back a successful finance change.
    }
  }

  static Future<List<FinanceTransaction>> saveInstallmentPlan({
    required FinanceTransaction transaction,
    FinanceTransaction? original,
    required int totalAmountMinor,
    required int installmentCount,
    required DateTime startDate,
    List<FinanceTransaction> existingInstallments = const [],
  }) async {
    final saved = await FinanceStorage.saveInstallmentPlan(
      transaction: transaction,
      original: original,
      totalAmountMinor: totalAmountMinor,
      installmentCount: installmentCount,
      startDate: startDate,
      existingInstallments: existingInstallments,
    );
    await _checkBudgetAlertsSafely();
    return saved;
  }

  static Future<List<FinanceTransaction>> getInstallmentGroup(
    String groupUuid, {
    bool includeDeleted = false,
  }) {
    return FinanceStorage.getInstallmentGroup(
      groupUuid,
      includeDeleted: includeDeleted,
    );
  }

  static Future<void> deleteInstallmentGroup(String groupUuid) async {
    final containsRefund = (await FinanceStorage.getInstallmentGroup(groupUuid))
        .any((item) => item.type == FinanceTransactionType.refund);
    await FinanceStorage.deleteInstallmentGroup(groupUuid);
    if (containsRefund) await _checkBudgetAlertsSafely();
  }

  static Future<void> restoreInstallmentGroup(String groupUuid) async {
    await FinanceStorage.restoreInstallmentGroup(groupUuid);
    await _checkBudgetAlertsSafely();
  }

  static Future<List<FinanceLoan>> getLoans({bool includeDeleted = false}) {
    return FinanceStorage.getLoans(includeDeleted: includeDeleted);
  }

  static Future<FinanceLoan?> getLoan(
    String uuid, {
    bool includeDeleted = false,
  }) {
    return FinanceStorage.getLoan(uuid, includeDeleted: includeDeleted);
  }

  static Future<List<FinanceLoanInstallment>> getLoanInstallments(
    String loanUuid, {
    bool includeDeleted = false,
    String? fromDueDate,
    String? toDueDate,
  }) {
    return FinanceStorage.getLoanInstallments(
      loanUuid,
      includeDeleted: includeDeleted,
      fromDueDate: fromDueDate,
      toDueDate: toDueDate,
    );
  }

  static Future<Map<String, List<FinanceLoanInstallment>>>
  getLoanInstallmentsForActiveLoans({String? fromDueDate, String? toDueDate}) {
    return FinanceStorage.getLoanInstallmentsForActiveLoans(
      fromDueDate: fromDueDate,
      toDueDate: toDueDate,
    );
  }

  static Future<void> saveLoan(FinanceLoan loan, {FinanceLoan? original}) {
    return FinanceStorage.saveLoan(loan, original: original);
  }

  static Future<void> setLoanInstallmentPaid(
    String installmentUuid,
    bool paid, {
    String? paymentMethodUuid,
    DateTime? paidAt,
  }) async {
    final installment = paid
        ? await FinanceStorage.getLoanInstallment(installmentUuid)
        : null;
    await FinanceStorage.setLoanInstallmentPaid(
      installmentUuid,
      paid,
      paymentMethodUuid: paymentMethodUuid,
      paidAt: paidAt,
    );
    if (installment != null && installment.interestMinor > 0) {
      unawaited(_checkBudgetAlertsSafely());
    }
  }

  static Future<List<FinanceLoanInstallment>> getPaidLoanInstallments() {
    return FinanceStorage.getPaidLoanInstallments();
  }

  static Future<void> deleteLoan(String uuid) {
    return FinanceStorage.deleteLoan(uuid);
  }

  static Future<void> restoreLoan(String uuid) {
    return FinanceStorage.restoreLoan(uuid);
  }

  static Future<void> deleteTransaction(String uuid) async {
    final transaction = await FinanceStorage.getTransaction(uuid);
    await FinanceStorage.deleteTransaction(uuid);
    if (transaction != null &&
        !transaction.isDeleted &&
        transaction.type == FinanceTransactionType.refund) {
      await _checkBudgetAlertsSafely();
    }
  }

  static Future<void> saveCategory(
    FinanceCategory category, {
    FinanceCategory? original,
  }) {
    return FinanceStorage.saveCategory(category, original: original);
  }

  static Future<void> archiveCategory(String uuid) {
    return FinanceStorage.archiveCategory(uuid);
  }

  static Future<bool> unarchiveCategory(String uuid) {
    return FinanceStorage.unarchiveCategory(uuid);
  }

  static Future<bool> hasTransactionsForCategory(String uuid) {
    return FinanceStorage.hasTransactionsForCategory(uuid);
  }

  static Future<void> savePaymentMethod(
    FinancePaymentMethod method, {
    FinancePaymentMethod? original,
  }) {
    return FinanceStorage.savePaymentMethod(method, original: original);
  }

  static Future<void> archivePaymentMethod(String uuid) {
    return FinanceStorage.archivePaymentMethod(uuid);
  }

  static Future<void> unarchivePaymentMethod(String uuid) {
    return FinanceStorage.unarchivePaymentMethod(uuid);
  }

  static Future<List<FinanceBudget>> getBudgets({
    String? monthKey,
    bool includeDeleted = false,
  }) {
    return FinanceStorage.getBudgets(
      monthKey: monthKey,
      includeDeleted: includeDeleted,
    );
  }

  static Future<void> saveBudget(
    FinanceBudget budget, {
    FinanceBudget? original,
    bool resetBalanceSnapshot = false,
    int? balanceSnapshotAt,
  }) async {
    await FinanceStorage.saveBudget(
      budget,
      original: original,
      resetBalanceSnapshot: resetBalanceSnapshot,
      balanceSnapshotAt: balanceSnapshotAt,
    );
    await _checkBudgetAlertsSafely();
  }

  static Future<void> deleteBudget(String uuid) {
    return FinanceStorage.deleteBudget(uuid);
  }

  static Future<void> restoreBudget(String uuid) async {
    await FinanceStorage.restoreBudget(uuid);
    await _checkBudgetAlertsSafely();
  }

  static Future<void> restoreTransaction(String uuid) async {
    await FinanceStorage.restoreTransaction(uuid);
    await _checkBudgetAlertsSafely();
  }

  static Future<List<FinanceRecurringRule>> getRecurringRules({
    bool includeDeleted = false,
    bool enabledOnly = false,
  }) {
    return FinanceStorage.getRecurringRules(
      includeDeleted: includeDeleted,
      enabledOnly: enabledOnly,
    );
  }

  static Future<FinanceRecurringRule?> getRecurringRule(String uuid) {
    return FinanceStorage.getRecurringRule(uuid);
  }

  static Future<void> saveRecurringRule(
    FinanceRecurringRule rule, {
    FinanceRecurringRule? original,
  }) {
    return FinanceStorage.saveRecurringRule(rule, original: original);
  }

  static Future<void> deleteRecurringRule(String uuid) {
    return FinanceStorage.deleteRecurringRule(uuid);
  }

  static Future<void> restoreRecurringRule(String uuid) async {
    await FinanceStorage.restoreRecurringRule(uuid);
    try {
      await ReminderScheduleService.scheduleCurrentUser();
    } catch (_) {
      // Reminder scheduling must not undo a restored recurring rule.
    }
  }

  static Future<void> setRecurringRuleEnabled(String uuid, bool enabled) {
    return FinanceStorage.setRecurringRuleEnabled(uuid, enabled);
  }

  static Future<List<FinanceEntryTemplate>> getTemplates({
    bool includeDeleted = false,
  }) {
    return FinanceStorage.getTemplates(includeDeleted: includeDeleted);
  }

  static Future<FinanceEntryTemplate?> getTemplate(String uuid) {
    return FinanceStorage.getTemplate(uuid);
  }

  static Future<void> saveTemplate(
    FinanceEntryTemplate template, {
    FinanceEntryTemplate? original,
  }) {
    return FinanceStorage.saveTemplate(template, original: original);
  }

  static Future<void> deleteTemplate(String uuid) {
    return FinanceStorage.deleteTemplate(uuid);
  }

  static Future<void> restoreTemplate(String uuid) {
    return FinanceStorage.restoreTemplate(uuid);
  }

  static Future<void> markTemplateUsed(String uuid) {
    return FinanceStorage.markTemplateUsed(uuid);
  }

  static Future<String?> exportCsv({
    required List<FinanceTransaction> transactions,
    required Map<String, FinanceCategory> categories,
    required Map<String, FinancePaymentMethod> paymentMethods,
  }) async {
    final rows = <List<String>>[
      ['日期', '类型', '金额', '分类', '关联账户', '商家', '备注', '来源', '分期', '分期总额'],
      ...transactions.map((transaction) {
        final category = categories[transaction.categoryUuid];
        final payment = paymentMethods[transaction.paymentMethodUuid];
        final paymentLabel = payment != null
            ? '${payment.icon} ${financePaymentMethodDisplayName(payment, paymentMethods.values)}'
            : transaction.paymentMethodUuid?.trim().isNotEmpty == true
            ? switch (transaction.type) {
                FinanceTransactionType.expense => '已删除或未知付款方式',
                FinanceTransactionType.income => '已删除或未知到账账户',
                FinanceTransactionType.refund => '已删除或未知退款到账账户',
              }
            : '未指定';
        final amount = transaction.type == FinanceTransactionType.expense
            ? -transaction.amountMinor
            : transaction.amountMinor;
        return [
          sanitizeFinanceCsvText(transaction.transactionDate),
          transaction.type.label,
          formatFinanceAmount(amount, withSymbol: false),
          sanitizeFinanceCsvText(
            category == null
                ? financeCategoryReferenceDisplayName(
                    transaction.categoryUuid,
                    categories.values,
                  )
                : '${category.icon} ${financeCategoryReferenceDisplayName(transaction.categoryUuid, categories.values)}',
          ),
          sanitizeFinanceCsvText(paymentLabel),
          sanitizeFinanceCsvText(transaction.merchant ?? ''),
          sanitizeFinanceCsvText(transaction.note ?? ''),
          transaction.source.label,
          transaction.installmentLabel ?? '',
          transaction.isInstallment && transaction.installmentTotalMinor != null
              ? formatFinanceAmount(
                  transaction.installmentTotalMinor!,
                  withSymbol: false,
                )
              : '',
        ];
      }),
    ];
    final csv = rows.map((row) => row.map(_escapeCsv).join(',')).join('\n');
    return BrowserFileService.saveTextFile(
      '\uFEFF$csv',
      'countdown_todo_finance_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  static String _escapeCsv(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\n') &&
        !value.contains('\r')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}

/// Prevent spreadsheet programs from interpreting user-controlled cells as
/// formulas when a CSV export is opened.
String sanitizeFinanceCsvText(String value) {
  final leading = value.trimLeft();
  if (leading.isEmpty) return value;
  const formulaPrefixes = {'=', '+', '-', '@'};
  return formulaPrefixes.contains(leading[0]) ? "'$value" : value;
}

/// 将用户输入的人民币金额转换为分，拒绝负数和超过两位小数的值。
final RegExp _financeAmountPlainPattern = RegExp(r'^\d+(\.\d{0,2})?$');
final RegExp _financeAmountThousandsPattern = RegExp(
  r'^\d{1,3}(,\d{3})+(\.\d{0,2})?$',
);
final RegExp _financeAmountTrimZeroCentsPattern = RegExp(r'\.00$');

int? parseFinanceAmount(String raw, {bool allowZero = false}) {
  final input = raw.trim();
  if (input.isEmpty ||
      (!_financeAmountPlainPattern.hasMatch(input) &&
          !_financeAmountThousandsPattern.hasMatch(input))) {
    return null;
  }
  final value = input.replaceAll(',', '');
  final parts = value.split('.');
  final whole = BigInt.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final cents = BigInt.tryParse(fraction.padRight(2, '0')) ?? BigInt.zero;
  final amountMinor = whole * BigInt.from(100) + cents;
  if (amountMinor > BigInt.from(maxFinanceAmountMinor)) return null;
  final result = amountMinor.toInt();
  return result > 0 || (allowZero && result == 0) ? result : null;
}

String formatFinanceAmount(int amountMinor, {bool withSymbol = true}) {
  final absolute = amountMinor.abs();
  final whole = absolute ~/ 100;
  final cents = (absolute % 100).toString().padLeft(2, '0');
  final groupedWhole = NumberFormat('#,##0', 'zh_CN').format(whole);
  final value = '$groupedWhole.$cents';
  final sign = amountMinor < 0 ? '-' : '';
  return withSymbol ? '$sign¥$value' : '$sign$value';
}

String formatFinanceAmountInput(int amountMinor) => formatFinanceAmount(
  amountMinor,
  withSymbol: false,
).replaceFirst(_financeAmountTrimZeroCentsPattern, '');

String formatSignedFinanceAmount(int amountMinor, FinanceTransactionType type) {
  return '${type.signedPrefix}${formatFinanceAmount(amountMinor)}';
}
