import 'package:flutter/material.dart';

import '../models.dart';
import '../screens/todo_chat_screen.dart';

class AiTodoChatLauncher {
  static Future<void> open(
    BuildContext context, {
    required String username,
    required List<TodoItem> todos,
    List<TodoGroup> todoGroups = const [],
    List<CourseItem> courses = const [],
    List<TimeLogItem> timeLogs = const [],
    List<ConflictInfo> conflicts = const [],
    List<Team> teams = const [],
    void Function(List<TodoItem> inserted, List<TodoItem> updated)?
        onTodosBatchAction,
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
          conflicts: conflicts,
          teams: teams,
          onTodosBatchAction: onTodosBatchAction,
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
            'startTime': t.createdDate != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    t.createdDate!,
                    isUtc: true,
                  ).toLocal().toIso8601String()
                : '',
            'endTime': t.dueDate?.toIso8601String() ?? '',
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
}
