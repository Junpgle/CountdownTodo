import 'dart:convert';

class WidgetSnapshot {
  final DateTime updatedAt;
  final List<WidgetCountdownItem> countdowns;
  final List<WidgetTodoItem> todos;
  final List<WidgetCourseItem> courses;
  final WidgetFocusState focus;
  final List<WidgetRecurrenceSeriesItem> recurrenceSeries;
  final List<WidgetHabitItem> habits;
  final WidgetFinanceSummary finance;

  const WidgetSnapshot({
    required this.updatedAt,
    this.countdowns = const [],
    this.todos = const [],
    this.courses = const [],
    this.focus = const WidgetFocusState(),
    this.recurrenceSeries = const [],
    this.habits = const [],
    this.finance = const WidgetFinanceSummary(),
  });

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'countdowns': countdowns.map((e) => e.toJson()).toList(),
      'todos': todos.map((e) => e.toJson()).toList(),
      'courses': courses.map((e) => e.toJson()).toList(),
      'focus': focus.toJson(),
      'recurrenceSeries': recurrenceSeries.map((e) => e.toJson()).toList(),
      'habits': habits.map((e) => e.toJson()).toList(),
      'finance': finance.toJson(),
    };
  }

  factory WidgetSnapshot.fromJson(Map<String, dynamic> json) {
    return WidgetSnapshot(
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      countdowns: (json['countdowns'] as List<dynamic>?)
              ?.map((e) =>
                  WidgetCountdownItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      todos: (json['todos'] as List<dynamic>?)
              ?.map((e) => WidgetTodoItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      courses: (json['courses'] as List<dynamic>?)
              ?.map((e) => WidgetCourseItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      focus: json['focus'] != null
          ? WidgetFocusState.fromJson(json['focus'] as Map<String, dynamic>)
          : const WidgetFocusState(),
      recurrenceSeries: (json['recurrenceSeries'] as List<dynamic>?)
              ?.map((e) => WidgetRecurrenceSeriesItem.fromJson(
                    e as Map<String, dynamic>,
                  ))
              .toList() ??
          [],
      habits: (json['habits'] as List<dynamic>?)
              ?.map((e) => WidgetHabitItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      finance: json['finance'] is Map
          ? WidgetFinanceSummary.fromJson(
              Map<String, dynamic>.from(json['finance'] as Map),
            )
          : const WidgetFinanceSummary(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static WidgetSnapshot empty() {
    return WidgetSnapshot(updatedAt: DateTime.now());
  }
}

/// 小组件中的本月记账摘要。
///
/// 金额统一使用人民币分，平台侧只负责展示，录入和数据变更仍由 Flutter
/// 记账模块处理。
class WidgetFinanceSummary {
  final String monthLabel;
  final int incomeMinor;
  final int netExpenseMinor;
  final int balanceMinor;
  final int transactionCount;
  final String latestTitle;
  final int latestAmountMinor;
  final String latestType;
  final String latestDate;

  const WidgetFinanceSummary({
    this.monthLabel = '',
    this.incomeMinor = 0,
    this.netExpenseMinor = 0,
    this.balanceMinor = 0,
    this.transactionCount = 0,
    this.latestTitle = '',
    this.latestAmountMinor = 0,
    this.latestType = '',
    this.latestDate = '',
  });

  bool get hasData =>
      transactionCount > 0 ||
      incomeMinor != 0 ||
      netExpenseMinor != 0 ||
      balanceMinor != 0;

  Map<String, dynamic> toJson() {
    return {
      'monthLabel': monthLabel,
      'incomeMinor': incomeMinor,
      'netExpenseMinor': netExpenseMinor,
      'balanceMinor': balanceMinor,
      'transactionCount': transactionCount,
      'latestTitle': latestTitle,
      'latestAmountMinor': latestAmountMinor,
      'latestType': latestType,
      'latestDate': latestDate,
    };
  }

  factory WidgetFinanceSummary.fromJson(Map<String, dynamic> json) {
    return WidgetFinanceSummary(
      monthLabel: json['monthLabel'] as String? ?? '',
      incomeMinor: (json['incomeMinor'] as num?)?.toInt() ?? 0,
      netExpenseMinor: (json['netExpenseMinor'] as num?)?.toInt() ?? 0,
      balanceMinor: (json['balanceMinor'] as num?)?.toInt() ?? 0,
      transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      latestTitle: json['latestTitle'] as String? ?? '',
      latestAmountMinor: (json['latestAmountMinor'] as num?)?.toInt() ?? 0,
      latestType: json['latestType'] as String? ?? '',
      latestDate: json['latestDate'] as String? ?? '',
    );
  }

  Map<String, dynamic> toAndroidWidgetData() {
    final latestSign = latestType == 'expense' ? '-' : '+';
    final latestAmount = latestAmountMinor == 0
        ? ''
        : '$latestSign${_formatAmount(latestAmountMinor)}';
    return {
      'finance_month_label': monthLabel,
      'finance_income': _formatAmount(incomeMinor),
      'finance_expense': _formatSignedAmount(netExpenseMinor),
      'finance_balance': _formatSignedAmount(balanceMinor),
      'finance_transaction_count': '$transactionCount 笔',
      'finance_latest_title': latestTitle.isEmpty ? '本月还没有账单' : latestTitle,
      'finance_latest_amount': latestAmount,
      'finance_latest_date': latestDate,
    };
  }

  String _formatAmount(int amountMinor) {
    final amount = (amountMinor.abs() / 100).toStringAsFixed(2);
    final parts = amount.split('.');
    final whole = parts.first;
    final grouped = whole.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (match) => ',',
    );
    return '¥$grouped.${parts.last}';
  }

  String _formatSignedAmount(int amountMinor) {
    final sign = amountMinor < 0 ? '-' : '';
    return '$sign${_formatAmount(amountMinor)}';
  }
}

/// 小组件中的今日习惯条目（设计文档 §20）。
class WidgetHabitItem {
  final String habitId;
  final String title;
  final String icon;
  final String sourceType;
  final double currentValue;
  final double targetValue;
  final String unit;
  final bool goalMet;
  final List<double> quickValues;

  const WidgetHabitItem({
    required this.habitId,
    required this.title,
    this.icon = '',
    this.sourceType = 'quantityCheckIn',
    this.currentValue = 0,
    this.targetValue = 0,
    this.unit = '',
    this.goalMet = false,
    this.quickValues = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'habitId': habitId,
      'title': title,
      'icon': icon,
      'sourceType': sourceType,
      'currentValue': currentValue,
      'targetValue': targetValue,
      'unit': unit,
      'goalMet': goalMet,
      'quickValues': quickValues,
    };
  }

  factory WidgetHabitItem.fromJson(Map<String, dynamic> json) {
    return WidgetHabitItem(
      habitId: json['habitId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? 'quantityCheckIn',
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0,
      targetValue: (json['targetValue'] as num?)?.toDouble() ?? 0,
      unit: json['unit'] as String? ?? '',
      goalMet: json['goalMet'] as bool? ?? false,
      quickValues: (json['quickValues'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
    );
  }
}

class WidgetRecurrenceSeriesItem {
  final String seriesId;
  final String title;
  final String recurrenceType;
  final String recurrenceText;
  final int? customIntervalDays;
  final int anchorStartMs;
  final int? anchorDueMs;
  final int? recurrenceEndMs;
  final bool isActive;
  final String? contextText;
  final int completedCount;
  final int overdueCount;
  final int elapsedCount;
  final int? totalCount;
  final List<WidgetRecurrenceOccurrenceItem> occurrences;

  const WidgetRecurrenceSeriesItem({
    required this.seriesId,
    required this.title,
    required this.recurrenceType,
    required this.recurrenceText,
    required this.anchorStartMs,
    this.anchorDueMs,
    this.recurrenceEndMs,
    this.customIntervalDays,
    this.isActive = true,
    this.contextText,
    this.completedCount = 0,
    this.overdueCount = 0,
    this.elapsedCount = 0,
    this.totalCount,
    this.occurrences = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'seriesId': seriesId,
      'title': title,
      'recurrenceType': recurrenceType,
      'recurrenceText': recurrenceText,
      'customIntervalDays': customIntervalDays,
      'anchorStartMs': anchorStartMs,
      'anchorDueMs': anchorDueMs,
      'recurrenceEndMs': recurrenceEndMs,
      'isActive': isActive,
      'contextText': contextText ?? '',
      'completedCount': completedCount,
      'overdueCount': overdueCount,
      'elapsedCount': elapsedCount,
      'totalCount': totalCount,
      'occurrences': occurrences.map((e) => e.toJson()).toList(),
    };
  }

  factory WidgetRecurrenceSeriesItem.fromJson(Map<String, dynamic> json) {
    return WidgetRecurrenceSeriesItem(
      seriesId: json['seriesId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      recurrenceType: json['recurrenceType'] as String? ?? 'none',
      recurrenceText: json['recurrenceText'] as String? ?? '循环待办',
      customIntervalDays: (json['customIntervalDays'] as num?)?.toInt(),
      anchorStartMs: (json['anchorStartMs'] as num?)?.toInt() ?? 0,
      anchorDueMs: (json['anchorDueMs'] as num?)?.toInt(),
      recurrenceEndMs: (json['recurrenceEndMs'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? true,
      contextText: json['contextText'] as String?,
      completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdueCount'] as num?)?.toInt() ?? 0,
      elapsedCount: (json['elapsedCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt(),
      occurrences: (json['occurrences'] as List<dynamic>?)
              ?.map((e) => WidgetRecurrenceOccurrenceItem.fromJson(
                    e as Map<String, dynamic>,
                  ))
              .toList() ??
          [],
    );
  }
}

class WidgetRecurrenceOccurrenceItem {
  final String occurrenceId;
  final int startAtMs;
  final int? dueAtMs;
  final bool isDone;
  final bool isDateOnly;
  final bool isProjected;

  const WidgetRecurrenceOccurrenceItem({
    required this.occurrenceId,
    required this.startAtMs,
    this.dueAtMs,
    this.isDone = false,
    this.isDateOnly = false,
    this.isProjected = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'occurrenceId': occurrenceId,
      'startAtMs': startAtMs,
      'dueAtMs': dueAtMs,
      'isDone': isDone,
      'isDateOnly': isDateOnly,
      'isProjected': isProjected,
    };
  }

  factory WidgetRecurrenceOccurrenceItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return WidgetRecurrenceOccurrenceItem(
      occurrenceId: json['occurrenceId'] as String? ?? '',
      startAtMs: (json['startAtMs'] as num?)?.toInt() ?? 0,
      dueAtMs: (json['dueAtMs'] as num?)?.toInt(),
      isDone: json['isDone'] as bool? ?? false,
      isDateOnly: json['isDateOnly'] as bool? ?? false,
      isProjected: json['isProjected'] as bool? ?? false,
    );
  }
}

class WidgetCountdownItem {
  final String title;
  final int daysLeft;
  final String dateText;
  final String? subtitle;

  const WidgetCountdownItem({
    required this.title,
    required this.daysLeft,
    required this.dateText,
    this.subtitle,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'daysLeft': daysLeft,
      'dateText': dateText,
      'subtitle': subtitle ?? '',
    };
  }

  factory WidgetCountdownItem.fromJson(Map<String, dynamic> json) {
    return WidgetCountdownItem(
      title: json['title'] as String? ?? '',
      daysLeft: json['daysLeft'] as int? ?? 0,
      dateText: json['dateText'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
    );
  }
}

class WidgetTodoItem {
  final String title;
  final String? timeText;
  final int priority;
  final bool isDone;
  final int? visibleUntilMs;

  const WidgetTodoItem({
    required this.title,
    this.timeText,
    this.priority = 0,
    this.isDone = false,
    this.visibleUntilMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'timeText': timeText ?? '',
      'priority': priority,
      'isDone': isDone,
      'visibleUntilMs': visibleUntilMs,
    };
  }

  factory WidgetTodoItem.fromJson(Map<String, dynamic> json) {
    return WidgetTodoItem(
      title: json['title'] as String? ?? '',
      timeText: json['timeText'] as String?,
      priority: json['priority'] as int? ?? 0,
      isDone: json['isDone'] as bool? ?? false,
      visibleUntilMs: (json['visibleUntilMs'] as num?)?.toInt(),
    );
  }
}

class WidgetCourseItem {
  final String title;
  final String timeText;
  final String location;
  final String? statusText;

  const WidgetCourseItem({
    required this.title,
    required this.timeText,
    required this.location,
    this.statusText,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'timeText': timeText,
      'location': location,
      'statusText': statusText ?? '',
    };
  }

  factory WidgetCourseItem.fromJson(Map<String, dynamic> json) {
    return WidgetCourseItem(
      title: json['title'] as String? ?? '',
      timeText: json['timeText'] as String? ?? '',
      location: json['location'] as String? ?? '',
      statusText: json['statusText'] as String?,
    );
  }
}

class WidgetFocusState {
  final bool isRunning;
  final String? currentTitle;
  final int todayMinutes;
  final int sessionMinutes;
  final int remainingSeconds;

  const WidgetFocusState({
    this.isRunning = false,
    this.currentTitle,
    this.todayMinutes = 0,
    this.sessionMinutes = 0,
    this.remainingSeconds = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'isRunning': isRunning,
      'currentTitle': currentTitle ?? '',
      'todayMinutes': todayMinutes,
      'sessionMinutes': sessionMinutes,
      'remainingSeconds': remainingSeconds,
    };
  }

  factory WidgetFocusState.fromJson(Map<String, dynamic> json) {
    return WidgetFocusState(
      isRunning: json['isRunning'] as bool? ?? false,
      currentTitle: json['currentTitle'] as String?,
      todayMinutes: json['todayMinutes'] as int? ?? 0,
      sessionMinutes: json['sessionMinutes'] as int? ?? 0,
      remainingSeconds: json['remainingSeconds'] as int? ?? 0,
    );
  }
}
