import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../screens/todo_chat_screen.dart';
import 'pomodoro_service.dart';

class AiTodoChatLauncher {
  static final DateFormat _localDateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');

  static Future<void> open(
    BuildContext context, {
    required String username,
    required List<TodoItem> todos,
    List<TodoGroup> todoGroups = const [],
    List<CourseItem> courses = const [],
    List<TimeLogItem> timeLogs = const [],
    List<PomodoroRecord> pomodoroRecords = const [],
    List<ConflictInfo> conflicts = const [],
    List<Team> teams = const [],
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    void Function(List<TodoItem> inserted, List<TodoItem> updated)?
        onTodosBatchAction,
    void Function(List<TodoGroup> groups)? onTodoGroupsChanged,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoChatScreen(
          username: username,
          todos: toChatTodoMaps(todos),
          todoGroups: todoGroups,
          courses: courses,
          timeLogs: timeLogs,
          pomodoroRecords: pomodoroRecords,
          conflicts: conflicts,
          teams: teams,
          countdowns: countdowns,
          pomodoroTags: pomodoroTags,
          onTodosBatchAction: onTodosBatchAction,
          onTodoGroupsChanged: onTodoGroupsChanged,
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> toChatTodoMaps(List<TodoItem> todos) {
    return todos
        .where((t) => !t.isDeleted)
        .map(
          (t) => <String, dynamic>{
            'id': t.id,
            'title': t.title,
            'remark': t.remark ?? '',
            'startTime': _formatEpochMillis(t.createdDate),
            'endTime': _formatDateTime(t.dueDate),
            'isAllDay': t.isAllDayTask,
            'isDone': t.isDone,
            'isDeleted': t.isDeleted,
            'recurrence': t.recurrence.name,
            'groupId': t.groupId ?? '',
            'reminderMinutes': t.reminderMinutes,
          },
        )
        .toList();
  }

  static String _formatEpochMillis(int? value) {
    if (value == null) return '';
    return _localDateTimeFormat
        .format(DateTime.fromMillisecondsSinceEpoch(value).toLocal());
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) return '';
    return _localDateTimeFormat.format(value.toLocal());
  }
}
