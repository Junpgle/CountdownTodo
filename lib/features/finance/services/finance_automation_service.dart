import 'dart:async';

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
  static final Set<String> _budgetAlertInFlight = {};
  static Timer? _autoGenerationTimer;
  static int _autoGenerationTimerRevision = 0;

  /// 计算规则在指定年月的发生时间。
  ///
  /// 账单统一按当地时间 09:00 发生；如果规则指定了 31 日而目标月份
  /// 没有 31 日，则自动落在该月最后一天。
  static DateTime? dueDateFor(
    FinanceRecurringRule rule,
    int year,
    int month,
  ) => rule.dueDateFor(year, month);

  static String periodKeyFor(FinanceRecurringRule rule, DateTime dueAt) {
    return rule.frequency == FinanceRecurringFrequency.yearly
        ? dueAt.year.toString()
        : financeMonthKey(dueAt);
  }

  /// Returns the next future due time that should materialize an automatic
  /// bill while the app remains open.
  static DateTime? nextAutoGenerationDueAfter(
    Iterable<FinanceRecurringRule> rules, {
    required DateTime now,
  }) {
    DateTime? nextDue;
    for (final rule in rules) {
      if (rule.isDeleted || !rule.isEnabled || !rule.autoGenerate) continue;

      final start = dateFromKey(rule.startDate);
      final lastGenerated = rule.effectiveLastGeneratedPeriod;
      DateTime? due;
      if (rule.frequency == FinanceRecurringFrequency.yearly) {
        var year = now.year > start.year ? now.year : start.year;
        final lastYear = int.tryParse(lastGenerated ?? '');
        if (lastYear != null && year <= lastYear) year = lastYear + 1;
        final endYear = rule.endDate == null
            ? null
            : dateFromKey(rule.endDate!).year;
        var attempts = 0;
        while (year <= 9999 &&
            attempts < 2 &&
            (endYear == null || year <= endYear)) {
          final candidate = dueDateFor(rule, year, rule.monthOfYear);
          if (candidate != null && candidate.isAfter(now)) {
            due = candidate;
            break;
          }
          year++;
          attempts++;
        }
      } else {
        var cursor = DateTime(now.year, now.month);
        final startMonth = DateTime(start.year, start.month);
        if (cursor.isBefore(startMonth)) cursor = startMonth;
        if (RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(lastGenerated ?? '')) {
          final parts = lastGenerated!.split('-');
          final monthAfterLast = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]) + 1,
          );
          if (cursor.isBefore(monthAfterLast)) cursor = monthAfterLast;
        }
        final end = rule.endDate == null ? null : dateFromKey(rule.endDate!);
        while (cursor.year <= 9999) {
          final candidate = dueDateFor(rule, cursor.year, cursor.month);
          if (candidate != null && candidate.isAfter(now)) {
            due = candidate;
            break;
          }
          if (end != null &&
              (cursor.year > end.year ||
                  (cursor.year == end.year && cursor.month >= end.month))) {
            break;
          }
          cursor = DateTime(cursor.year, cursor.month + 1);
        }
      }

      if (due != null && (nextDue == null || due.isBefore(nextDue))) {
        nextDue = due;
      }
    }
    return nextDue;
  }

  /// Keeps automatic bills materialized while the app is open, even when the
  /// finance screen is not the active route.
  static Future<void> scheduleNextAutoGeneration({
    DateTime? now,
    DateTime Function()? clock,
  }) async {
    final current = now ?? clock?.call() ?? DateTime.now();
    final revision = ++_autoGenerationTimerRevision;
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = null;
    try {
      final rules = await FinanceStorage.getRecurringRules(enabledOnly: true);
      if (revision != _autoGenerationTimerRevision) return;
      scheduleAutoGenerationForRules(rules, now: current, clock: clock);
    } catch (_) {
      if (revision == _autoGenerationTimerRevision) {
        _scheduleAutoGenerationRetry(clock: clock);
      }
    }
  }

  /// Reconciles elapsed due bills before calculating the next future timer.
  /// Called when the app starts or returns to the foreground.
  static Future<void> resumeAutoGenerationSchedule({
    DateTime Function()? clock,
  }) async {
    try {
      await reconcileCurrentPeriod(now: clock?.call());
    } catch (_) {
      _scheduleAutoGenerationRetry(clock: clock);
      return;
    }
    await scheduleNextAutoGeneration(clock: clock);
  }

  /// Arms the shared timer from a loaded rule list. Kept separate so callers
  /// that already loaded rules can avoid a second database query.
  static void scheduleAutoGenerationForRules(
    Iterable<FinanceRecurringRule> rules, {
    required DateTime now,
    DateTime Function()? clock,
    Duration retryBaseDelay = const Duration(minutes: 1),
  }) {
    final revision = ++_autoGenerationTimerRevision;
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = null;
    final dueAt = nextAutoGenerationDueAfter(rules, now: now);
    if (dueAt == null) return;

    final delayMs =
        (dueAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch + 1)
            .clamp(1, const Duration(days: 24).inMilliseconds)
            .toInt();
    _autoGenerationTimer = Timer(Duration(milliseconds: delayMs), () {
      _autoGenerationTimer = null;
      if (revision != _autoGenerationTimerRevision) return;
      unawaited(_runScheduledAutoGeneration(
        revision,
        clock: clock,
        retryBaseDelay: retryBaseDelay,
      ));
    });
  }

  static void cancelScheduledAutoGeneration() {
    _autoGenerationTimerRevision++;
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = null;
  }

  static void _scheduleAutoGenerationRetry({
    DateTime Function()? clock,
    Duration delay = const Duration(minutes: 1),
  }) {
    final revision = ++_autoGenerationTimerRevision;
    _autoGenerationTimer?.cancel();
    _autoGenerationTimer = Timer(delay, () {
      _autoGenerationTimer = null;
      if (revision != _autoGenerationTimerRevision) return;
      unawaited(resumeAutoGenerationSchedule(clock: clock));
    });
  }

  static Future<void> _runScheduledAutoGeneration(
    int revision, {
    DateTime Function()? clock,
    int retryAttempt = 0,
    Duration retryBaseDelay = const Duration(minutes: 1),
  }) async {
    try {
      await reconcileCurrentPeriod(now: clock?.call());
    } catch (_) {
      if (revision != _autoGenerationTimerRevision) return;
      if (retryAttempt < 3) {
        _autoGenerationTimer = Timer(
          retryBaseDelay * (1 << retryAttempt),
          () {
            _autoGenerationTimer = null;
            if (revision != _autoGenerationTimerRevision) return;
            unawaited(_runScheduledAutoGeneration(
              revision,
              clock: clock,
              retryAttempt: retryAttempt + 1,
              retryBaseDelay: retryBaseDelay,
            ));
          },
        );
        return;
      }
      // Keep the current due period pending after transient failures. Scheduling
      // only the next future due here would otherwise skip this period until
      // the app is opened again.
      _scheduleAutoGenerationRetry(
        clock: clock,
        delay: retryBaseDelay * 15,
      );
      return;
    }
    if (revision != _autoGenerationTimerRevision) return;
    await scheduleNextAutoGeneration(now: clock?.call(), clock: clock);
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
    final lastPeriod = rule.effectiveLastGeneratedPeriod;

    if (lastPeriod == null) {
      final due = currentDueFor(rule, now: current);
      return due == null ? const [] : [due];
    }

    if (rule.frequency == FinanceRecurringFrequency.yearly) {
      final lastYear = int.tryParse(lastPeriod);
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
    if (RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(lastPeriod)) {
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
    if (!end.isAfter(current)) return const [];
    final allRules = await FinanceStorage.getRecurringRules();
    final enabledRules = allRules.where((rule) => rule.isEnabled);
    final reminders = <Map<String, dynamic>>[];
    for (final rule in enabledRules) {
      if (rule.reminderMinutes <= 0) continue;
      final calendarLeadDays = (rule.reminderMinutes + 1439) ~/ 1440;
      // The due time is later than its reminder trigger. Scan the current
      // window plus the lead, then filter by the exact trigger below.
      final dues = upcoming(
        rules: [rule],
        now: current,
        limit: _calendarDateTimeOffset(end, calendarLeadDays + 1),
      );
      for (final due in dues) {
        final reminder = _buildReminder(
          due,
          rules: allRules,
          current: current,
          limit: end,
        );
        if (reminder['withinWindow'] == true) reminders.add(reminder);
      }
    }
    _resolveRecurringNotificationIdCollisions(reminders);
    reminders.sort(
      (left, right) =>
          (left['triggerAtMs'] as int).compareTo(right['triggerAtMs'] as int),
    );
    return reminders;
  }

  static void _resolveRecurringNotificationIdCollisions(
    List<Map<String, dynamic>> reminders,
  ) {
    final assignmentOrder = [...reminders]
      ..sort((left, right) {
        final leftKey =
            '${left['financeRuleUuid']}|${left['financePeriodKey']}';
        final rightKey =
            '${right['financeRuleUuid']}|${right['financePeriodKey']}';
        return leftKey.compareTo(rightKey);
      });
    final assigned = <int>{};
    for (final reminder in assignmentOrder) {
      final hashedId = (reminder['notifId'] as num).toInt();
      final startOffset = hashedId - recurringNotificationBaseId;
      for (var probe = 0; probe < recurringNotificationRange; probe++) {
        final candidate = recurringNotificationBaseId +
            (startOffset + probe) % recurringNotificationRange;
        if (!assigned.add(candidate)) continue;
        reminder['notifId'] = candidate;
        break;
      }
    }
  }

  static Map<String, dynamic> _buildReminder(
    FinanceRecurringDue due, {
    required Iterable<FinanceRecurringRule> rules,
    required DateTime current,
    required DateTime limit,
  }) {
    final usesCalendarDays = due.rule.reminderMinutes % 1440 == 0;
    final calendarLeadDays =
        usesCalendarDays ? due.rule.reminderMinutes ~/ 1440 : 0;
    final remainingLeadMinutes =
        usesCalendarDays ? 0 : due.rule.reminderMinutes;
    final localTriggerAt = _calendarDateTimeOffset(
      due.dueAt,
      -calendarLeadDays,
    );
    final triggerAt = localTriggerAt.subtract(
      Duration(minutes: remainingLeadMinutes),
    );
    return {
      'triggerAtMs': triggerAt.toUtc().millisecondsSinceEpoch,
      'startAtMs': due.dueAt.toUtc().millisecondsSinceEpoch,
      'title':
          '💳 周期账单：${financeRecurringRuleDisplayName(due.rule, rules)}',
      'text': '${dateKey(due.dueAt)} · ${_formatAmount(due.rule.amountMinor)}'
          '${due.rule.autoGenerate ? ' · 到期自动记账' : ' · 请确认是否记账'}',
      'notifId': notificationIdFor(due.rule.uuid, due.periodKey),
      'type': 'finance_recurring',
      'financeRuleUuid': due.rule.uuid,
      'financePeriodKey': due.periodKey,
      'financeAutoGenerate': due.rule.autoGenerate,
      'financeDueAtMs': due.dueAt.toUtc().millisecondsSinceEpoch,
      'withinWindow': triggerAt.isAfter(current) && triggerAt.isBefore(limit),
    };
  }

  static DateTime _calendarDateTimeOffset(DateTime value, int days) {
    if (value.isUtc) {
      return DateTime.utc(
        value.year,
        value.month,
        value.day + days,
        value.hour,
        value.minute,
        value.second,
        value.millisecond,
        value.microsecond,
      );
    }
    return DateTime(
      value.year,
      value.month,
      value.day + days,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  /// 检查本月预算的 80% 和 100% 阈值，并按预算版本去重通知。
  static Future<void> checkBudgetAlerts({DateTime? now}) async {
    if (!await AppSettingsStorage.isFinanceBudgetAlertEnabled()) return;
    if (!await AppSettingsStorage.isNormalNotificationEnabled()) return;

    final current = now ?? DateTime.now();
    final monthKey = financeMonthKey(current);
    final budgets = await FinanceStorage.getBudgets(monthKey: monthKey);
    if (budgets.isEmpty) return;
    final transactions = await FinanceStorage.getTransactions(
      from: DateTime(current.year, current.month),
      to: DateTime(current.year, current.month + 1),
    );
    final summary = FinanceSummary.fromTransactions(
      transactions,
      asOfAt: current.millisecondsSinceEpoch,
    );
    final categories = await FinanceStorage.getCategories(
      includeArchived: true,
    );
    final categoryNames = {
      for (final category in categories)
        category.uuid: financeCategoryDisplayName(category, categories),
    };
    final prefs = await SharedPreferences.getInstance();
    final accountKey =
        prefs.getString(StorageService.keyCurrentUser) ?? 'default';

    for (final budget in budgets) {
      if (budget.isPaymentMethod) continue;
      final used = summary.spendingForBudget(budget, categories);
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
      if (prefs.getBool(alertKey) == true ||
          !_budgetAlertInFlight.add(alertKey)) {
        continue;
      }
      final scope = budget.categoryUuid == null
          ? '本月总支出'
          : '${categoryNames[budget.categoryUuid] ?? '分类'}支出';
      final title = threshold == 100 ? '预算已超支' : '预算已使用 80%';
      final body = '$scope ${_formatAmount(used)} / '
          '${_formatAmount(budget.amountMinor)}';
      try {
        final delivered = await NotificationService.showFinanceBudgetAlert(
          title: title,
          body: body,
          alertKey: alertKey,
        );
        if (delivered) await prefs.setBool(alertKey, true);
      } catch (_) {
        // 系统通知不可用时保留下一次重试机会，但不影响记账流程。
      } finally {
        _budgetAlertInFlight.remove(alertKey);
      }
    }
  }

  /// Turns budget reminders on and immediately evaluates the current month.
  /// A failed notification must not undo the user's preference change.
  static Future<void> setBudgetAlertsEnabled(bool enabled) async {
    await AppSettingsStorage.setFinanceBudgetAlertEnabled(enabled);
    if (!enabled) return;
    try {
      await checkBudgetAlerts();
    } catch (_) {
      // The next finance mutation or app launch will retry the alert check.
    }
  }

  static String _formatAmount(int amountMinor) {
    final absolute = amountMinor.abs();
    final whole = NumberFormat('#,##0', 'zh_CN').format(absolute ~/ 100);
    final cents = (absolute % 100).toString().padLeft(2, '0');
    final sign = amountMinor < 0 ? '-' : '';
    return '¥$sign$whole.$cents';
  }
}
