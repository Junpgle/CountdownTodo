import 'dart:convert';

class WidgetSnapshot {
  final int todayTodoCount;
  final String? nextTodoTitle;
  final String? nextTodoDueText;
  final String? nearestCountdownTitle;
  final String? nearestCountdownDaysText;
  final String? pomodoroStateText;
  final String? pomodoroLeftText;
  final String? widgetMode;
  final DateTime updatedAt;

  const WidgetSnapshot({
    required this.todayTodoCount,
    this.nextTodoTitle,
    this.nextTodoDueText,
    this.nearestCountdownTitle,
    this.nearestCountdownDaysText,
    this.pomodoroStateText,
    this.pomodoroLeftText,
    this.widgetMode,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'todayTodoCount': todayTodoCount,
      'nextTodoTitle': nextTodoTitle ?? '',
      'nextTodoDueText': nextTodoDueText ?? '',
      'nearestCountdownTitle': nearestCountdownTitle ?? '',
      'nearestCountdownDaysText': nearestCountdownDaysText ?? '',
      'pomodoroStateText': pomodoroStateText ?? '',
      'pomodoroLeftText': pomodoroLeftText ?? '',
      'widgetMode': widgetMode ?? 'todo',
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory WidgetSnapshot.fromJson(Map<String, dynamic> json) {
    return WidgetSnapshot(
      todayTodoCount: json['todayTodoCount'] as int? ?? 0,
      nextTodoTitle: json['nextTodoTitle'] as String?,
      nextTodoDueText: json['nextTodoDueText'] as String?,
      nearestCountdownTitle: json['nearestCountdownTitle'] as String?,
      nearestCountdownDaysText: json['nearestCountdownDaysText'] as String?,
      pomodoroStateText: json['pomodoroStateText'] as String?,
      pomodoroLeftText: json['pomodoroLeftText'] as String?,
      widgetMode: json['widgetMode'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static WidgetSnapshot empty() {
    return WidgetSnapshot(
      todayTodoCount: 0,
      updatedAt: DateTime.now(),
    );
  }

  static WidgetSnapshot fromWidgetData(Map<String, dynamic> widgetData, DateTime now) {
    int todoCount = 0;
    String? nextTitle;
    String? nextDue;
    for (int i = 1; i <= 8; i++) {
      final title = widgetData['todo_$i'] as String? ?? '';
      if (title.isNotEmpty) {
        todoCount++;
        if (nextTitle == null) {
          nextTitle = _stripHtml(title);
          nextDue = widgetData['todo_${i}_due'] as String?;
        }
      }
    }

    String? cdTitle;
    String? cdDays;
    final rawTitle = widgetData['cd_title_1'] as String? ?? '';
    if (rawTitle.isNotEmpty) {
      cdTitle = _stripHtml(rawTitle);
      cdDays = widgetData['cd_days_1'] as String?;
    }

    String? pomState;
    final tlTotal = widgetData['tl_total'] as String? ?? '';
    if (tlTotal.isNotEmpty) {
      pomState = tlTotal;
    }

    final mode = widgetData['widget_mode'] as String? ?? 'todo';

    return WidgetSnapshot(
      todayTodoCount: todoCount,
      nextTodoTitle: nextTitle,
      nextTodoDueText: nextDue,
      nearestCountdownTitle: cdTitle,
      nearestCountdownDaysText: cdDays,
      pomodoroStateText: pomState,
      widgetMode: mode,
      updatedAt: now,
    );
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }
}
