import 'dart:convert';

class WidgetSnapshot {
  final DateTime updatedAt;
  final List<WidgetCountdownItem> countdowns;
  final List<WidgetTodoItem> todos;
  final List<WidgetCourseItem> courses;
  final WidgetFocusState focus;

  const WidgetSnapshot({
    required this.updatedAt,
    this.countdowns = const [],
    this.todos = const [],
    this.courses = const [],
    this.focus = const WidgetFocusState(),
  });

  Map<String, dynamic> toJson() {
    return {
      'updatedAt': updatedAt.toIso8601String(),
      'countdowns': countdowns.map((e) => e.toJson()).toList(),
      'todos': todos.map((e) => e.toJson()).toList(),
      'courses': courses.map((e) => e.toJson()).toList(),
      'focus': focus.toJson(),
    };
  }

  factory WidgetSnapshot.fromJson(Map<String, dynamic> json) {
    return WidgetSnapshot(
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      countdowns: (json['countdowns'] as List<dynamic>?)
              ?.map((e) => WidgetCountdownItem.fromJson(e as Map<String, dynamic>))
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
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static WidgetSnapshot empty() {
    return WidgetSnapshot(updatedAt: DateTime.now());
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

  const WidgetTodoItem({
    required this.title,
    this.timeText,
    this.priority = 0,
    this.isDone = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'timeText': timeText ?? '',
      'priority': priority,
      'isDone': isDone,
    };
  }

  factory WidgetTodoItem.fromJson(Map<String, dynamic> json) {
    return WidgetTodoItem(
      title: json['title'] as String? ?? '',
      timeText: json['timeText'] as String?,
      priority: json['priority'] as int? ?? 0,
      isDone: json['isDone'] as bool? ?? false,
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
