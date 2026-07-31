import 'dart:convert';

class WidgetSnapshot {
  final DateTime updatedAt;
  final List<WidgetCountdownItem> countdowns;
  final List<WidgetTodoItem> todos;
  final List<WidgetCourseItem> courses;
  final WidgetFocusState focus;
  final List<WidgetRecurrenceSeriesItem> recurrenceSeries;

  const WidgetSnapshot({
    required this.updatedAt,
    this.countdowns = const [],
    this.todos = const [],
    this.courses = const [],
    this.focus = const WidgetFocusState(),
    this.recurrenceSeries = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'countdowns': countdowns.map((e) => e.toJson()).toList(),
      'todos': todos.map((e) => e.toJson()).toList(),
      'courses': courses.map((e) => e.toJson()).toList(),
      'focus': focus.toJson(),
      'recurrenceSeries': recurrenceSeries.map((e) => e.toJson()).toList(),
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
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static WidgetSnapshot empty() {
    return WidgetSnapshot(updatedAt: DateTime.now());
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
