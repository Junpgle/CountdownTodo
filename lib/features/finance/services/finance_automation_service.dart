import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../services/notification_service.dart';
import '../../../services/storage/app_settings_storage.dart';
import '../../../storage_service.dart';
import '../models/finance_models.dart';
import 'finance_storage.dart';

/// 一个周期账单在某个周期内的实际发生时间。
class FinanceRecurringDue {
  final FinanceRecurringRule rule;
  final DateTime dueAt;
  final String periodKey;

  const FinanceRecurringDue({
    required this.rule,
    required this.dueAt,
    required this.periodKey,
  });
}

/// 记账自动化服务：负责周期账单的计算、提醒、幂等生成和预算提醒。
abstract final class FinanceAutomationService {
  static const int recurringNotificationBaseId = 52001;
  static const int recurringNotificationRange = 7999;
  static const int maxRecurringCatchUpPeriods = 12;

  /// 计算规则在指定年月的发生时间。
  ///
  /// 账单统一按当地时间 09:00 发生；如果规则指定了 31 日而目标月份
  /// 没有 31 日，则自动落在该月最后一天。
  static DateTime? dueDateFor(
    FinanceRecurringRule rule,
    int year,
    int month,
  ) {
    if (month < 1 || month > 12) return null;
    if (rule.frequency == FinanceRecurringFrequency.yearly &&
        month != rule.monthOfYear) {
      return null;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = rule.dayOfMonth.clamp(1, lastDay);
    final due = DateTime(year, month, day, 9);
    if (!_isWithinRule(rule, due)) return null;
    return due;
  }

  static String periodKeyFor(FinanceRecurringRule rule, DateTime dueAt) {
    return rule.frequency == FinanceRecurringFrequency.yearly
        ? dueAt.year.toString()
        : financeMonthKey(dueAt);
  }

  /// 返回当前周期的到期项；尚未到 09:00 时不生成账单。
  static FinanceRecurringDue? currentDueFor(
    FinanceRecurringRule rule, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final due = dueDateFor(
      rule,
      current.year,
      rule.frequency == FinanceRecurringFrequency.yearly
          ? rule.monthOfYear
          : current.month,
    );
    if (due == null || due.isAfter(current)) return null;
    return FinanceRecurringDue(
      rule: rule,
      dueAt: due,
      periodKey: periodKeyFor(rule, due),
    );
  }

  /// Returns unmaterialized due periods through [now], oldest first.
  ///
  /// A newly-created or legacy rule without a generation marker only
  /// materializes the current period. Existing rules catch up at most the most
  /// recent 12 periods so an old start date cannot flood the ledger on launch.
  static List<FinanceRecurringDue> missedDuesFor(
    FinanceRecurringRule rule, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final start = dateFromKey(rule.startDate);
    final result = <FinanceRecurringDue>[];

    if (rule.lastGeneratedPeriod == null) {
      final due = currentDueFor(rule, now: current);
      return due == null ? const [] : [due];
    }

    if (rule.frequency == FinanceRecurringFrequency.yearly) {
      final lastYear = int.tryParse(rule.lastGeneratedPeriod!);
      final firstYear = lastYear == null ? start.year : lastYear + 1;
      for (var year = firstYear; year <= current.year; year++) {
        final due = dueDateFor(rule, year, rule.monthOfYear);
        if (due != null && !due.isAfter(current)) {
          result.add(FinanceRecurringDue(
            rule: rule,
            dueAt: due,
            periodKey: periodKeyFor(rule, due),
          ));
        }
      }
      return _latestCatchUpPeriods(result);
    }

    var cursor = DateTime(start.year, start.month);
    final lastPeriod = rule.lastGeneratedPeriod;
    if (lastPeriod != null &&
        RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(lastPeriod)) {
      final parts = lastPeriod.split('-');
      cursor = DateTime(int.parse(parts[0]), int.parse(parts[1]) + 1);
    }
    final currentMonth = DateTime(current.year, current.month);
    while (!cursor.isAfter(currentMonth)) {
      final due = dueDateFor(rule, cursor.year, cursor.month);
      if (due != null && !due.isAfter(current)) {
        result.add(FinanceRecurringDue(
          rule: rule,
          dueAt: due,
          periodKey: periodKeyFor(rule, due),
        ));
      }
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return _latestCatchUpPeriods(result);
  }

  static List<FinanceRecurringDue> _latestCatchUpPeriods(
    List<FinanceRecurringDue> dues,
  ) {
    if (dues.length <= maxRecurringCatchUpPeriods) return dues;
    return dues.sublist(dues.length - maxRecurringCatchUpPeriods);
  }

  /// 计算未来窗口中的周期账单提醒，不访问数据库，便于测试和复用。
  static List<FinanceRecurringDue> upcoming({
    required List<FinanceRecurringRule> rules,
    required DateTime now,
    required DateTime limit,
  }) {
    if (!limit.isAfter(now)) return const [];
    final result = <FinanceRecurringDue>[];
    final firstMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(limit.year, limit.month);

    for (final rule in rules) {
      if (rule.isDeleted || !rule.isEnabled) continue;
      var cursor = firstMonth;
      while (!cursor.isAfter(lastMonth)) {
        final due = dueDateFor(rule, cursor.year, cursor.month);
        if (due != null &&
            !due.isBefore(now) &&
            due.isBefore(limit) &&
            result.every(
              (item) =>
                  item.rule.uuid != rule.uuid ||
                  item.periodKey != periodKeyFor(rule, due),
            )) {
          result.add(
            FinanceRecurringDue(
              rule: rule,
              dueAt: due,
              periodKey: periodKeyFor(rule, due),
            ),
          );
        }
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
    }

    result.sort((left, right) => left.dueAt.compareTo(right.dueAt));
    return result;
  }

  static int notificationIdFor(String ruleUuid, String periodKey) {
    var hash = 0;
    for (final codeUnit in '$ruleUuid|$periodKey'.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return recurringNotificationBaseId + hash % recurringNotificationRange;
  }

  /// 生成当前已到期的自动账单。生成过程在存储层事务中完成，重复调用安全。
  static Future<int> reconcileCurrentPeriod({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final rules = await FinanceStorage.getRecurringRules(enabledOnly: true);
    var generated = 0;
    for (final rule in rules) {
      if (!rule.autoGenerate) continue;
      for (final due in missedDuesFor(rule, now: current)) {
        if (await FinanceStorage.materializeRecurringRule(
          rule,
          dueAt: due.dueAt,
          periodKey: due.periodKey,
        )) {
          generated++;
        }
      }
    }
    // 即使本次没有新生成账单，也要检查已有历史账单对应的本月预算，
    // 这样升级到第四阶段后首次打开应用即可得到提醒。
    await checkBudgetAlerts(now: current);
    return generated;
  }

  /// 生成未来提醒调度项。提醒提前量为 0 时表示关闭提醒。
  static Future<List<Map<String, dynamic>>> buildRecurringReminders({
    DateTime? now,
    DateTime? limit,
  }) async {
    final current = now ?? DateTime.now();
    final end = limit ?? current.add(const Duration(days: 7));
    final rules = await FinanceStorage.getRecurringRules(enabledOnly: true);
    final dues = upcoming(rules: rules, now: current, limit: end);
    return [
      for (final due in dues)
        if (due.rule.reminderMinutes > 0)
          _buildReminder(due, current: current, limit: end),
    ];
  }

  static Map<String, dynamic> _buildReminder(
    FinanceRecurringDue due, {
    required DateTime current,
    required DateTime limit,
  }) {
    final triggerAt = due.dueAt.subtract(
      Duration(minutes: due.rule.reminderMinutes),
    );
    return {
      'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
      'startAtMs': due.dueAt.toUtc().millisecondsSinceEpoch,
      'title': '💳 周期账单：${due.rule.name}',
      'text': '${dateKey(due.dueAt)} · ${_formatAmount(due.rule.amountMinor)}'
          '${due.rule.autoGenerate ? ' · 到期自动记账' : ' · 请确认是否记账'}',
      'notifId': notificationIdFor(due.rule.uuid, due.periodKey),
      'type': 'finance_recurring',
      'financeRuleUuid': due.rule.uuid,
      'financePeriodKey': due.periodKey,
      'financeAutoGenerate': due.rule.autoGenerate,
      'financeDueAtMs': due.dueAt.toUtc().millisecondsSinceEpoch,
      // 保留参数语义，调用方若扩展调度窗口可直接复用该构造器。
      'withinWindow': due.dueAt.isAfter(current) && due.dueAt.isBefore(limit),
    };
  }

  /// 检查本月预算的 80% 和 100% 阈值，并按预算版本去重通知。
  static Future<void> checkBudgetAlerts({DateTime? now}) async {
    if (!await AppSettingsStorage.isFinanceBudgetAlertEnabled()) return;
    if (!await AppSettingsStorage.isNormalNotificationEnabled()) return;

    final current = now ?? DateTime.now();
    final monthKey = financeMonthKey(current);
    final budgets = await FinanceStorage.getBudgets(monthKey: monthKey);
    if (budgets.isEmpty) return;
    final summary = await FinanceStorage.getSummary(
      from: DateTime(current.year, current.month),
      to: DateTime(current.year, current.month + 1),
    );
    final categories = await FinanceStorage.getCategories(
      includeArchived: true,
    );
    final categoryNames = {
      for (final category in categories) category.uuid: category.name,
    };
    final prefs = await SharedPreferences.getInstance();
    final accountKey =
        prefs.getString(StorageService.keyCurrentUser) ?? 'default';

    for (final budget in budgets) {
      final used = (budget.categoryUuid == null
              ? summary.netExpenseMinor
              : summary.expenseByCategory[budget.categoryUuid] ?? 0)
          .clamp(0, 0x7fffffff);
      if (used <= 0 || budget.amountMinor <= 0) continue;
      final ratio = used / budget.amountMinor;
      final threshold = ratio >= 1
          ? 100
          : ratio >= .8
              ? 80
              : 0;
      if (threshold == 0) continue;

      final alertKey =
          'finance-budget-v1-$accountKey-${budget.uuid}-${budget.monthKey}-${budget.version}-$threshold';
      if (prefs.getBool(alertKey) == true) continue;
      final scope = budget.categoryUuid == null
          ? '本月总支出'
          : '${categoryNames[budget.categoryUuid] ?? '分类'}支出';
      final title = threshold == 100 ? '预算已超支' : '预算已使用 80%';
      final body = '$scope ${_formatAmount(used)} / '
          '${_formatAmount(budget.amountMinor)}';
      try {
        await NotificationService.showFinanceBudgetAlert(
          title: title,
          body: body,
          alertKey: alertKey,
        );
        await prefs.setBool(alertKey, true);
      } catch (_) {
        // 系统通知不可用时保留下一次重试机会，但不影响记账流程。
      }
    }
  }

  static bool _isWithinRule(FinanceRecurringRule rule, DateTime date) {
    final start = dateFromKey(rule.startDate);
    if (date.isBefore(DateTime(start.year, start.month, start.day))) {
      return false;
    }
    if (rule.endDate != null) {
      final end = dateFromKey(rule.endDate!);
      if (date.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) {
        return false;
      }
    }
    return true;
  }

  static String _formatAmount(int amountMinor) {
    final value = NumberFormat('#,##0.00', 'zh_CN').format(amountMinor / 100);
    return '¥$value';
  }
}
