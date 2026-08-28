import 'package:intl/intl.dart';

import '../../../services/browser_file_service.dart';
import '../models/finance_models.dart';
import 'finance_automation_service.dart';
import 'finance_storage.dart';

abstract final class FinanceRepository {
  static Future<List<FinanceTransaction>> getTransactions({
    DateTime? from,
    DateTime? to,
    String? keyword,
    FinanceTransactionType? type,
  }) {
    return FinanceStorage.getTransactions(
      from: from,
      to: to,
      keyword: keyword,
      type: type,
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
  }) {
    return FinanceStorage.getCategories(
      type: type,
      includeArchived: includeArchived,
    );
  }

  static Future<List<FinancePaymentMethod>> getPaymentMethods({
    bool includeArchived = false,
  }) {
    return FinanceStorage.getPaymentMethods(
      includeArchived: includeArchived,
    );
  }

  static Future<void> saveTransaction(FinanceTransaction transaction) async {
    await FinanceStorage.saveTransaction(transaction);
    try {
      await FinanceAutomationService.checkBudgetAlerts(
        now: dateFromKey(transaction.transactionDate),
      );
    } catch (_) {
      // 预算通知失败不能回滚已经保存成功的账单。
    }
  }

  static Future<void> deleteTransaction(String uuid) {
    return FinanceStorage.deleteTransaction(uuid);
  }

  static Future<void> saveCategory(FinanceCategory category) {
    return FinanceStorage.saveCategory(category);
  }

  static Future<void> archiveCategory(String uuid) {
    return FinanceStorage.archiveCategory(uuid);
  }

  static Future<void> unarchiveCategory(String uuid) {
    return FinanceStorage.unarchiveCategory(uuid);
  }

  static Future<bool> hasTransactionsForCategory(String uuid) {
    return FinanceStorage.hasTransactionsForCategory(uuid);
  }

  static Future<void> savePaymentMethod(FinancePaymentMethod method) {
    return FinanceStorage.savePaymentMethod(method);
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

  static Future<void> saveBudget(FinanceBudget budget) {
    return FinanceStorage.saveBudget(budget);
  }

  static Future<void> deleteBudget(String uuid) {
    return FinanceStorage.deleteBudget(uuid);
  }

  static Future<void> restoreBudget(String uuid) {
    return FinanceStorage.restoreBudget(uuid);
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

  static Future<void> saveRecurringRule(FinanceRecurringRule rule) {
    return FinanceStorage.saveRecurringRule(rule);
  }

  static Future<void> deleteRecurringRule(String uuid) {
    return FinanceStorage.deleteRecurringRule(uuid);
  }

  static Future<void> restoreRecurringRule(String uuid) {
    return FinanceStorage.restoreRecurringRule(uuid);
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

  static Future<void> saveTemplate(FinanceEntryTemplate template) {
    return FinanceStorage.saveTemplate(template);
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
      [
        '日期',
        '类型',
        '金额',
        '分类',
        '付款方式',
        '商家',
        '备注',
        '来源',
      ],
      ...transactions.map((transaction) {
        final category = categories[transaction.categoryUuid];
        final payment = paymentMethods[transaction.paymentMethodUuid];
        final amount = transaction.type == FinanceTransactionType.expense
            ? -transaction.amountMinor
            : transaction.amountMinor;
        return [
          transaction.transactionDate,
          transaction.type.label,
          (amount / 100).toStringAsFixed(2),
          category == null ? '未分类' : '${category.icon} ${category.name}',
          payment == null ? '未指定' : '${payment.icon} ${payment.name}',
          transaction.merchant ?? '',
          transaction.note ?? '',
          transaction.source.label,
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

/// 将用户输入的人民币金额转换为分，拒绝负数和超过两位小数的值。
int? parseFinanceAmount(String raw) {
  final input = raw.trim();
  final validNumber = RegExp(r'^\d+(\.\d{0,2})?$');
  final validThousands = RegExp(r'^\d{1,3}(,\d{3})+(\.\d{0,2})?$');
  if (input.isEmpty ||
      (!validNumber.hasMatch(input) && !validThousands.hasMatch(input))) {
    return null;
  }
  final value = input.replaceAll(',', '');
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final cents = int.tryParse(fraction.padRight(2, '0')) ?? 0;
  final result = whole * 100 + cents;
  return result > 0 ? result : null;
}

String formatFinanceAmount(int amountMinor, {bool withSymbol = true}) {
  final value =
      NumberFormat('#,##0.00', 'zh_CN').format(amountMinor.abs() / 100);
  final sign = amountMinor < 0 ? '-' : '';
  return withSymbol ? '$sign¥$value' : '$sign$value';
}

String formatSignedFinanceAmount(
  int amountMinor,
  FinanceTransactionType type,
) {
  return '${type.signedPrefix}${formatFinanceAmount(amountMinor)}';
}
