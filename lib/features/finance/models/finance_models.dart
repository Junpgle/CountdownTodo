import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../utils/json_value_parser.dart';
import '../../../utils/time_utils.dart';
import '../../../utils/calendar_date_math.dart';

part 'parts/finance_loan_models.dart';
part 'parts/finance_catalog_models.dart';
part 'parts/finance_transaction_and_budget_models.dart';
part 'parts/finance_automation_and_summary_models.dart';

/// 账单的现金流类型。
///
/// 金额在模型中始终保存为正整数（人民币分），方向由该枚举决定。
enum FinanceTransactionType { expense, income, refund, transfer }

/// Reserved ledger filter value for transactions without a category.
const String financeUncategorizedCategoryFilterUuid =
    '__finance_uncategorized__';

enum FinanceCategoryType { expense, income }

enum FinanceEntrySource { manual, import, ai, automation }

/// Largest amount in minor units that remains exact on every supported
/// platform and in JSON/SQLite storage.
const int maxFinanceAmountMinor = 9007199254740991;

final _financeInterestRateDisplayPattern = RegExp(r'\.?0+$');
final _financeInterestRateInputPattern = RegExp(r'^\d+(\.\d{0,2})?$');
final _financeDisplayWhitespacePattern = RegExp(r'\s+');
final _financePaymentLeadingPunctuationPattern = RegExp(
  r'^[^\u4e00-\u9fffA-Za-z0-9]+',
);
final _financeDraftTransactionDatePattern = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2})(?=$|[Tt ])',
);
final _financeDraftAmountLeadingCurrencyPattern = RegExp(r'^[¥￥$€£]');
final _financeDraftAmountTrailingUnitPattern = RegExp(
  r'\s*(?:元|块|人民币|CNY)\s*$',
  caseSensitive: false,
);
final _financeDraftAmountPattern = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$');
final _financeYearlyGenerationPeriodPattern = RegExp(r'^\d{4}$');
final _financeMonthlyGenerationPeriodPattern = RegExp(
  r'^\d{4}-(0[1-9]|1[0-2])$',
);

bool isSafeFinanceAmountMinor(int amountMinor) =>
    amountMinor >= 0 && amountMinor <= maxFinanceAmountMinor;

FinanceCategoryType financeCategoryTypeForTransaction(
  FinanceTransactionType type,
) {
  return type == FinanceTransactionType.income
      ? FinanceCategoryType.income
      : FinanceCategoryType.expense;
}

String dateKey(DateTime date) => AppTimeFormats.date(date);

int financeDefaultOccurrenceTimezoneOffsetMinutes({
  required DateTime? occurrence,
  required DateTime now,
}) {
  if (occurrence == null || dateKey(occurrence) == dateKey(now)) {
    return now.timeZoneOffset.inMinutes;
  }
  return occurrence.timeZoneOffset.inMinutes;
}

DateTime financeCalendarDayOffset(DateTime value, int days) {
  if (value.isUtc) {
    return DateTime.utc(value.year, value.month, value.day + days);
  }
  return DateTime(value.year, value.month, value.day + days);
}

String financeMonthKey(DateTime date) => AppTimeFormats.format(date, 'yyyy-MM');

bool isFinanceDateKey(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed != null && dateKey(parsed) == value;
}

String financeTimezoneLabel(int offsetMinutes) =>
    'UTC${offsetMinutes < 0 ? '-' : '+'}'
    '${(offsetMinutes.abs() ~/ 60).toString().padLeft(2, '0')}:'
    '${(offsetMinutes.abs() % 60).toString().padLeft(2, '0')}';

DateTime dateFromKey(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return DateTime.now();
  return CalendarDateMath.dateOnly(parsed);
}

FinanceTransactionType _transactionType(dynamic raw) {
  if (raw is num) {
    final index = raw.toInt().clamp(
      0,
      FinanceTransactionType.values.length - 1,
    );
    return FinanceTransactionType.values[index];
  }
  final value = raw?.toString();
  final numericIndex = int.tryParse(value?.trim() ?? '');
  if (numericIndex != null) {
    return FinanceTransactionType.values[numericIndex.clamp(
      0,
      FinanceTransactionType.values.length - 1,
    )];
  }
  return FinanceTransactionType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceTransactionType.expense,
  );
}

FinanceRecurringFrequency _recurringFrequency(dynamic raw) {
  if (raw is num) {
    final index = raw.toInt().clamp(
      0,
      FinanceRecurringFrequency.values.length - 1,
    );
    return FinanceRecurringFrequency.values[index];
  }
  final value = raw?.toString();
  return FinanceRecurringFrequency.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceRecurringFrequency.monthly,
  );
}

FinanceLoanRepaymentMethod _loanRepaymentMethod(dynamic raw) {
  if (raw is num) {
    final index = raw.toInt().clamp(
      0,
      FinanceLoanRepaymentMethod.values.length - 1,
    );
    return FinanceLoanRepaymentMethod.values[index];
  }
  final value = raw?.toString();
  return FinanceLoanRepaymentMethod.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceLoanRepaymentMethod.equalPrincipalInterest,
  );
}

FinanceCategoryType _categoryType(dynamic raw) {
  if (raw is num) {
    final index = raw.toInt().clamp(0, FinanceCategoryType.values.length - 1);
    return FinanceCategoryType.values[index];
  }
  final value = raw?.toString();
  return FinanceCategoryType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceCategoryType.expense,
  );
}

FinanceEntrySource _entrySource(dynamic raw) {
  final value = raw?.toString();
  return FinanceEntrySource.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FinanceEntrySource.manual,
  );
}

String? _string(dynamic value) {
  if (value == null) return null;
  final result = value.toString().trim();
  return result.isEmpty || result == 'null' ? null : result;
}

String? _nullableString(dynamic value) => _string(value);

int _int(dynamic value, {int fallback = 0}) =>
    JsonValueParser.toInt(value, fallback: fallback);

int? _nullableInt(dynamic value) => JsonValueParser.toNullableInt(value);

int _timestamp(dynamic value) => JsonValueParser.epochMillisOrNow(value);

bool _bool(dynamic value) => value == true || value == 1 || value == '1';

bool _boolOrDefault(dynamic value, bool fallback) =>
    value == null ? fallback : _bool(value);
