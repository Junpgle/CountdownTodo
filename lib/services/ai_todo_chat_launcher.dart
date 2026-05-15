import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../models/ai_todo_action.dart';
import '../screens/todo_chat_screen.dart';
import '../utils/page_transitions.dart';
import 'todo_classification_service.dart';
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
    Map<String, int> categoryReminderDefaults = const {},
    GlobalKey? sourceKey,
    void Function(List<TodoItem> inserted, List<TodoItem> updated)?
        onTodosBatchAction,
    void Function(List<TodoGroup> groups)? onTodoGroupsChanged,
  }) {
    final initialCategorizationActions =
        TodoClassificationService.buildCategorizeActions(
      todos: todos,
      groups: todoGroups,
      categoryReminderDefaults: categoryReminderDefaults,
    );
    final page = TodoChatScreen(
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
      initialCategorizationActions: initialCategorizationActions,
      onTodosBatchAction: onTodosBatchAction,
      onTodoGroupsChanged: onTodoGroupsChanged,
    );
    if (sourceKey != null) {
      return PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
      );
    }
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  static String buildCategorizationMessage(List<AiTodoAction> actions) {
    if (actions.isEmpty) return '';
    final lines = actions.map((action) {
      final groupName =
          action.metadata['groupName']?.toString() ?? action.groupId ?? '目标文件夹';
      final priority = action.metadata['priorityLabel']?.toString();
      final suffix = priority == null || priority.isEmpty ? '' : '，$priority';
      return '- ${action.title ?? '未命名待办'} -> $groupName$suffix';
    }).join('\n');
    return '我根据标题、备注和已有文件夹匹配到这些整理建议：\n\n$lines\n\n可以直接执行所选操作，也可以逐条忽略或编辑。';
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
