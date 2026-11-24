part of '../finance_models.dart';

/// 周期账单规则。
///
/// `dayOfMonth` 在每月/每年的目标月份中使用，遇到短月时自动落在该月
/// 最后一天。`lastGeneratedPeriod` 记录自动生成进度：同一周期只允许生成一笔
/// 自动账单；规则暂停、删除或切换为手动记账时也会推进进度，避免重新启用后
/// 补出暂停期间的账单。
class FinanceRecurringRule {
  static String transactionUuidForPeriod(String ruleUuid, String periodKey) {
    return const Uuid().v5(
      '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
      'countdown-todo/finance-recurring/v1/$ruleUuid/$periodKey',
    );
  }

  String uuid;
  String name;
  FinanceTransactionType type;
  int amountMinor;
  String currencyCode;
  String? categoryUuid;
  String? paymentMethodUuid;
  String? merchant;
  String? note;
  FinanceRecurringFrequency frequency;
  int dayOfMonth;
  int monthOfYear;
  String startDate;
  String? endDate;
  int reminderMinutes;
  bool autoGenerate;
  bool isEnabled;
  bool isDeleted;
  String? lastGeneratedPeriod;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceRecurringRule({
    String? uuid,
    required this.name,
    this.type = FinanceTransactionType.expense,
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.categoryUuid,
    this.paymentMethodUuid,
    this.merchant,
    this.note,
    this.frequency = FinanceRecurringFrequency.monthly,
    this.dayOfMonth = 1,
    this.monthOfYear = 1,
    required this.startDate,
    this.endDate,
    this.reminderMinutes = 1440,
    this.autoGenerate = true,
    this.isEnabled = true,
    this.isDeleted = false,
    this.lastGeneratedPeriod,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// The local due time in a month, constrained by this rule's date range.
  DateTime? dueDateFor(int year, int month) {
    if (month < 1 || month > 12) return null;
    if (frequency == FinanceRecurringFrequency.yearly && month != monthOfYear) {
      return null;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final due = DateTime(year, month, dayOfMonth.clamp(1, lastDay), 9);
    final start = dateFromKey(startDate);
    if (due.isBefore(DateTime(start.year, start.month, start.day))) return null;
    if (endDate != null) {
      final end = dateFromKey(endDate!);
      if (due.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) {
        return null;
      }
    }
    return due;
  }

  /// The last elapsed period in this schedule, used when changing frequency.
  /// A due time which has already passed must not become a new backdated bill.
  String generationPeriodBefore(DateTime at) {
    final month = frequency == FinanceRecurringFrequency.yearly
        ? monthOfYear
        : at.month;
    final lastDay = DateTime(at.year, month + 1, 0).day;
    final due = DateTime(at.year, month, dayOfMonth.clamp(1, lastDay), 9);
    if (frequency == FinanceRecurringFrequency.yearly) {
      return '${at.isBefore(due) ? at.year - 1 : at.year}';
    }
    return financeMonthKey(
      at.isBefore(due)
          ? DateTime(at.year, at.month - 1)
          : DateTime(at.year, at.month),
    );
  }

  /// Older clients retained a monthly marker after switching to yearly (or
  /// vice versa). Anchor those rows to their edit time instead of startDate.
  String? get effectiveLastGeneratedPeriod {
    final period = lastGeneratedPeriod;
    if (period == null) return null;
    final pattern = frequency == FinanceRecurringFrequency.yearly
        ? _financeYearlyGenerationPeriodPattern
        : _financeMonthlyGenerationPeriodPattern;
    return pattern.hasMatch(period)
        ? period
        : generationPeriodBefore(
            DateTime.fromMillisecondsSinceEpoch(updatedAt),
          );
  }

  void markAsChanged() {
    lastGeneratedPeriod = effectiveLastGeneratedPeriod;
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
    pendingSync = true;
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'name': name,
    'type': type.name,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'category_uuid': categoryUuid,
    'payment_method_uuid': paymentMethodUuid,
    'merchant': merchant,
    'note': note,
    'frequency': frequency.name,
    'day_of_month': dayOfMonth,
    'month_of_year': monthOfYear,
    'start_date': startDate,
    'end_date': endDate,
    'reminder_minutes': reminderMinutes,
    'auto_generate': autoGenerate ? 1 : 0,
    'is_enabled': isEnabled ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
    'last_generated_period': lastGeneratedPeriod,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'pending_sync': pendingSync ? 1 : 0,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceRecurringRule.fromMap(Map<String, dynamic> map) {
    return FinanceRecurringRule(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '未命名周期账单',
      type: _transactionType(map['type']),
      amountMinor: _int(map['amount_minor'] ?? map['amountMinor']).abs(),
      currencyCode:
          _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      categoryUuid: _nullableString(
        map['category_uuid'] ?? map['categoryUuid'],
      ),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      merchant: _nullableString(map['merchant']),
      note: _nullableString(map['note']),
      frequency: _recurringFrequency(map['frequency']),
      dayOfMonth: _int(map['day_of_month'] ?? map['dayOfMonth'], fallback: 1),
      monthOfYear: _int(
        map['month_of_year'] ?? map['monthOfYear'],
        fallback: 1,
      ),
      startDate:
          _string(map['start_date'] ?? map['startDate']) ??
          dateKey(DateTime.now()),
      endDate: _nullableString(map['end_date'] ?? map['endDate']),
      reminderMinutes: _int(
        map['reminder_minutes'] ?? map['reminderMinutes'],
        fallback: 1440,
      ),
      autoGenerate: _boolOrDefault(
        map['auto_generate'] ?? map['autoGenerate'],
        true,
      ),
      isEnabled: _boolOrDefault(map['is_enabled'] ?? map['isEnabled'], true),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      lastGeneratedPeriod: _nullableString(
        map['last_generated_period'] ?? map['lastGeneratedPeriod'],
      ),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

/// Adds a stable ordinal when non-deleted recurring rules share the same name.
String financeRecurringRuleDisplayName(
  FinanceRecurringRule rule,
  Iterable<FinanceRecurringRule> rules, {
  bool includeDeleted = false,
}) {
  final normalizedName = _normalizeFinanceDisplayName(rule.name);
  final sameNameRules =
      rules
          .where(
            (item) =>
                (includeDeleted || !item.isDeleted) &&
                _normalizeFinanceDisplayName(item.name) == normalizedName,
          )
          .toList()
        ..sort((left, right) {
          final createdAt = left.createdAt.compareTo(right.createdAt);
          return createdAt != 0 ? createdAt : left.uuid.compareTo(right.uuid);
        });
  if (sameNameRules.length < 2) return rule.name;
  final index = sameNameRules.indexWhere((item) => item.uuid == rule.uuid);
  if (index < 0) return rule.name;
  return '${rule.name}（同名周期账单 ${index + 1}/${sameNameRules.length}）';
}

/// Builds the display names for a rule collection in one grouping pass.
Map<String, String> financeRecurringRuleDisplayNames(
  Iterable<FinanceRecurringRule> rules, {
  bool includeDeleted = false,
}) {
  final rulesByName = <String, List<FinanceRecurringRule>>{};
  for (final rule in rules) {
    if (!includeDeleted && rule.isDeleted) continue;
    (rulesByName[_normalizeFinanceDisplayName(rule.name)] ??= []).add(rule);
  }

  final namesByUuid = <String, String>{};
  for (final sameNameRules in rulesByName.values) {
    if (sameNameRules.length > 1) {
      sameNameRules.sort((left, right) {
        final createdAt = left.createdAt.compareTo(right.createdAt);
        return createdAt != 0 ? createdAt : left.uuid.compareTo(right.uuid);
      });
    }
    for (var index = 0; index < sameNameRules.length; index++) {
      final rule = sameNameRules[index];
      final displayName = sameNameRules.length < 2
          ? rule.name
          : '${rule.name}（同名周期账单 ${index + 1}/${sameNameRules.length}）';
      namesByUuid.putIfAbsent(rule.uuid, () => displayName);
    }
  }
  return namesByUuid;
}

/// 快捷记账模板。模板只保存默认字段，不会直接产生账单。
class FinanceEntryTemplate {
  String uuid;
  String name;
  FinanceTransactionType type;
  int amountMinor;
  String currencyCode;
  String? categoryUuid;
  String? paymentMethodUuid;
  String? merchant;
  String? note;
  int useCount;
  int? lastUsedAt;
  bool isDeleted;
  int version;
  int createdAt;
  int updatedAt;
  String? deviceId;
  bool pendingSync;

  FinanceEntryTemplate({
    String? uuid,
    required this.name,
    this.type = FinanceTransactionType.expense,
    required this.amountMinor,
    this.currencyCode = FinanceDefaults.defaultCurrencyCode,
    this.categoryUuid,
    this.paymentMethodUuid,
    this.merchant,
    this.note,
    this.useCount = 0,
    this.lastUsedAt,
    this.isDeleted = false,
    this.version = 1,
    int? createdAt,
    int? updatedAt,
    this.deviceId,
    this.pendingSync = false,
  }) : uuid = uuid ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  void markAsChanged() {
    version++;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedAt = now > updatedAt ? now : updatedAt + 1;
    pendingSync = true;
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'name': name,
    'type': type.name,
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'category_uuid': categoryUuid,
    'payment_method_uuid': paymentMethodUuid,
    'merchant': merchant,
    'note': note,
    'use_count': useCount,
    'last_used_at': lastUsedAt,
    'is_deleted': isDeleted ? 1 : 0,
    'version': version,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'pending_sync': pendingSync ? 1 : 0,
  };

  Map<String, dynamic> toJson() => toMap();

  factory FinanceEntryTemplate.fromMap(Map<String, dynamic> map) {
    return FinanceEntryTemplate(
      uuid: _string(map['uuid'] ?? map['id']) ?? const Uuid().v4(),
      name: _string(map['name']) ?? '未命名模板',
      type: _transactionType(map['type']),
      amountMinor: _int(map['amount_minor'] ?? map['amountMinor']).abs(),
      currencyCode:
          _string(map['currency_code'] ?? map['currencyCode']) ??
          FinanceDefaults.defaultCurrencyCode,
      categoryUuid: _nullableString(
        map['category_uuid'] ?? map['categoryUuid'],
      ),
      paymentMethodUuid: _nullableString(
        map['payment_method_uuid'] ?? map['paymentMethodUuid'],
      ),
      merchant: _nullableString(map['merchant']),
      note: _nullableString(map['note']),
      useCount: _int(map['use_count'] ?? map['useCount']),
      lastUsedAt: _nullableInt(map['last_used_at'] ?? map['lastUsedAt']),
      isDeleted: _bool(map['is_deleted'] ?? map['isDeleted']),
      version: _int(map['version'], fallback: 1),
      createdAt: _timestamp(map['created_at'] ?? map['createdAt']),
      updatedAt: _timestamp(map['updated_at'] ?? map['updatedAt']),
      deviceId: _nullableString(map['device_id'] ?? map['deviceId']),
      pendingSync: _bool(map['pending_sync'] ?? map['pendingSync']),
    );
  }
}

/// Adds a stable ordinal when active entry templates share the same name.
String financeEntryTemplateDisplayName(
  FinanceEntryTemplate template,
  Iterable<FinanceEntryTemplate> templates, {
  bool includeDeleted = false,
}) {
  final normalizedName = _normalizeFinanceDisplayName(template.name);
  final sameNameTemplates =
      templates
          .where(
            (item) =>
                (includeDeleted || !item.isDeleted) &&
                _normalizeFinanceDisplayName(item.name) == normalizedName,
          )
          .toList()
        ..sort((left, right) {
          final createdAt = left.createdAt.compareTo(right.createdAt);
          return createdAt != 0 ? createdAt : left.uuid.compareTo(right.uuid);
        });
  if (sameNameTemplates.length < 2) return template.name;
  final index = sameNameTemplates.indexWhere(
    (item) => item.uuid == template.uuid,
  );
  if (index < 0) return template.name;
  return '${template.name}（同名模板 ${index + 1}/${sameNameTemplates.length}）';
}

/// Builds the display names for a template collection in one grouping pass.
Map<String, String> financeEntryTemplateDisplayNames(
  Iterable<FinanceEntryTemplate> templates, {
  bool includeDeleted = false,
}) {
  final templatesByName = <String, List<FinanceEntryTemplate>>{};
  for (final template in templates) {
    if (!includeDeleted && template.isDeleted) continue;
    (templatesByName[_normalizeFinanceDisplayName(template.name)] ??= []).add(
      template,
    );
  }

  final namesByUuid = <String, String>{};
  for (final sameNameTemplates in templatesByName.values) {
    if (sameNameTemplates.length > 1) {
      sameNameTemplates.sort((left, right) {
        final createdAt = left.createdAt.compareTo(right.createdAt);
        return createdAt != 0 ? createdAt : left.uuid.compareTo(right.uuid);
      });
    }
    for (var index = 0; index < sameNameTemplates.length; index++) {
      final template = sameNameTemplates[index];
      final displayName = sameNameTemplates.length < 2
          ? template.name
          : '${template.name}（同名模板 ${index + 1}/${sameNameTemplates.length}）';
      namesByUuid.putIfAbsent(template.uuid, () => displayName);
    }
  }
  return namesByUuid;
}

String _normalizeFinanceDisplayName(String value) =>
    value.replaceAll(_financeDisplayWhitespacePattern, '').trim().toLowerCase();

class FinanceCumulativeBalanceEvent {
  final String transactionDate;
  final int eventAt;
  final int changeMinor;

  const FinanceCumulativeBalanceEvent({
    required this.transactionDate,
    required this.eventAt,
    required this.changeMinor,
  });
}

class FinanceCumulativeBalancePoint {
  final DateTime month;
  final int balanceMinor;
  final bool isCurrentMonth;

  const FinanceCumulativeBalancePoint({
    required this.month,
    required this.balanceMinor,
    required this.isCurrentMonth,
  });
}

class FinanceSummary {
  final int incomeMinor;
  final int expenseMinor;
  final int refundMinor;
  final int transactionCount;
  final Map<String, int> expenseByCategory;
  final Map<String, int> incomeByCategory;
  final Map<String, int> expenseByDate;

  const FinanceSummary({
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.refundMinor = 0,
    this.transactionCount = 0,
    this.expenseByCategory = const {},
    this.incomeByCategory = const {},
    this.expenseByDate = const {},
  });

  static FinanceSummary fromTransactions(
    Iterable<FinanceTransaction> transactions, {
    int? asOfAt,
  }) {
    var income = 0;
    var expense = 0;
    var refund = 0;
    var transactionCount = 0;
    final expenseByCategory = <String, int>{};
    final incomeByCategory = <String, int>{};
    final expenseByDate = <String, int>{};

    for (final transaction in transactions) {
      if (asOfAt != null && transaction.balanceEventAt() > asOfAt) continue;
      transactionCount++;
      final categoryUuid = transaction.categoryUuid ?? '';
      switch (transaction.type) {
        case FinanceTransactionType.income:
          income += transaction.amountMinor;
          incomeByCategory[categoryUuid] =
              (incomeByCategory[categoryUuid] ?? 0) + transaction.amountMinor;
        case FinanceTransactionType.expense:
          expense += transaction.amountMinor;
          expenseByCategory[categoryUuid] =
              (expenseByCategory[categoryUuid] ?? 0) + transaction.amountMinor;
          expenseByDate[transaction.transactionDate] =
              (expenseByDate[transaction.transactionDate] ?? 0) +
              transaction.amountMinor;
        case FinanceTransactionType.refund:
          refund += transaction.amountMinor;
          expenseByCategory[categoryUuid] =
              (expenseByCategory[categoryUuid] ?? 0) - transaction.amountMinor;
          expenseByDate[transaction.transactionDate] =
              (expenseByDate[transaction.transactionDate] ?? 0) -
              transaction.amountMinor;
        case FinanceTransactionType.transfer:
          // 账户互转不计入月度收支与预算统计，仅影响转出/转入账户余额。
          break;
      }
    }

    return FinanceSummary(
      incomeMinor: income,
      expenseMinor: expense,
      refundMinor: refund,
      transactionCount: transactionCount,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      expenseByDate: expenseByDate,
    );
  }

  int get netExpenseMinor => expenseMinor - refundMinor;

  int get balanceMinor => incomeMinor - netExpenseMinor;

  /// Category budgets cover the category itself and all of its descendants.
  /// Sum refunds before clamping so the page, alerts and AI use one total.
  int spendingForBudget(
    FinanceBudget budget,
    Iterable<FinanceCategory> categories,
  ) {
    if (budget.isPaymentMethod) {
      throw ArgumentError('账户余额应按余额快照计算');
    }
    if (budget.isOverall) return math.max(0, netExpenseMinor);
    final categoryMap = {
      for (final category in categories) category.uuid: category,
    };
    var total = 0;
    for (final entry in expenseByCategory.entries) {
      String? uuid = entry.key;
      final visited = <String>{};
      while (uuid != null && visited.add(uuid)) {
        if (uuid == budget.categoryUuid) {
          total += entry.value;
          break;
        }
        final category = categoryMap[uuid];
        if (category == null || category.type != FinanceCategoryType.expense) {
          break;
        }
        uuid = category.parentUuid;
      }
    }
    return math.max(0, total);
  }

  /// Calculates several overall and category budget totals in one pass.
  /// Category budgets share one category index and one ancestor traversal per
  /// ledger category instead of rescanning the summary for every budget.
  Map<String, int> spendingForBudgets(
    Iterable<FinanceBudget> budgets,
    Iterable<FinanceCategory> categories,
  ) {
    final spendingByBudget = <String, int>{};
    final budgetUuidsByCategory = <String, Set<String>>{};
    for (final budget in budgets) {
      if (budget.isPaymentMethod) {
        throw ArgumentError('账户余额应按余额快照计算');
      }
      if (budget.isOverall) {
        spendingByBudget[budget.uuid] = math.max(0, netExpenseMinor);
        continue;
      }
      spendingByBudget[budget.uuid] = 0;
      final categoryUuid = budget.categoryUuid;
      if (categoryUuid == null) continue;
      (budgetUuidsByCategory[categoryUuid] ??= <String>{}).add(budget.uuid);
    }
    if (budgetUuidsByCategory.isEmpty) return spendingByBudget;

    final categoryMap = {
      for (final category in categories) category.uuid: category,
    };
    final totalsByBudget = <String, int>{};
    for (final entry in expenseByCategory.entries) {
      String? uuid = entry.key;
      final visited = <String>{};
      while (uuid != null && visited.add(uuid)) {
        final matchingBudgets = budgetUuidsByCategory[uuid];
        if (matchingBudgets != null) {
          for (final budgetUuid in matchingBudgets) {
            totalsByBudget[budgetUuid] =
                (totalsByBudget[budgetUuid] ?? 0) + entry.value;
          }
        }
        final category = categoryMap[uuid];
        if (category == null || category.type != FinanceCategoryType.expense) {
          break;
        }
        uuid = category.parentUuid;
      }
    }
    for (final budgetUuids in budgetUuidsByCategory.values) {
      for (final budgetUuid in budgetUuids) {
        spendingByBudget[budgetUuid] = math.max(
          0,
          totalsByBudget[budgetUuid] ?? 0,
        );
      }
    }
    return spendingByBudget;
  }
}
