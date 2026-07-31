import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../models/ai_todo_action.dart';
import '../screens/todo_chat_screen.dart';
import '../storage_service.dart';
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
    List<FixedScheduleItem>? fixedSchedules,
    Map<String, int> categoryReminderDefaults = const {},
    GlobalKey? sourceKey,
    void Function(List<TodoItem> inserted, List<TodoItem> updated)?
        onTodosBatchAction,
    void Function(List<TodoGroup> groups)? onTodoGroupsChanged,
    void Function(List<FixedScheduleItem> schedules)? onFixedSchedulesChanged,
  }) async {
    final initialCategorizationActions =
        await TodoClassificationService.buildCategorizeActions(
      todos: todos,
      groups: todoGroups,
      categoryReminderDefaults: categoryReminderDefaults,
    );
    final resolvedFixedSchedules = fixedSchedules ??
        await StorageService.getFixedSchedules(
          username,
          includeDeleted: true,
        );
    if (!context.mounted) return;
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
      fixedSchedules: resolvedFixedSchedules,
      initialCategorizationActions: initialCategorizationActions,
      onTodosBatchAction: onTodosBatchAction,
      onTodoGroupsChanged: onTodoGroupsChanged,
      onFixedSchedulesChanged: onFixedSchedulesChanged,
    );
    if (sourceKey != null) {
      return PageTransitions.pushFromRect(
        context: context,
        page: page,
        sourceKey: sourceKey,
      );
    }
    await Navigator.push(
      context,
      PageTransitions.material(builder: (_) => page),
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
    final recurrenceRuleBySeries = <String, TodoItem>{};
    for (final todo in todos.where((todo) => !todo.isDeleted)) {
      final seriesId = todo.recurrenceSeriesId?.trim();
      if (seriesId == null || seriesId.isEmpty) continue;
      final existing = recurrenceRuleBySeries[seriesId];
      if (existing == null ||
          (todo.recurrence != RecurrenceType.none &&
              existing.recurrence == RecurrenceType.none) ||
          (todo.recurrence == existing.recurrence &&
              (todo.createdDate ?? todo.createdAt) >
                  (existing.createdDate ?? existing.createdAt))) {
        recurrenceRuleBySeries[seriesId] = todo;
      }
    }

    return todos.where((t) => !t.isDeleted).map((t) {
      final seriesId = t.recurrenceSeriesId?.trim();
      final rule = seriesId == null || seriesId.isEmpty
          ? t
          : recurrenceRuleBySeries[seriesId] ?? t;
      return <String, dynamic>{
        'id': t.id,
        'title': t.title,
        'remark': t.remark ?? '',
        'startTime': _formatEpochMillis(t.createdDate),
        'endTime': _formatDateTime(t.dueDate),
        'timeMode': t.timeMode.name,
        'isAllDay': t.isAllDayTask,
        'isDone': t.isDone,
        'isDeleted': t.isDeleted,
        'recurrence': t.recurrence.name,
        'recurrenceRule': rule.recurrence.name,
        'recurrenceSeriesId': seriesId ?? '',
        'recurrenceRole': seriesId == null || seriesId.isEmpty
            ? 'standalone'
            : t.id == rule.id
                ? 'activeRule'
                : 'occurrence',
        'customIntervalDays': rule.customIntervalDays,
        'recurrenceEndDate': _formatDateTime(rule.recurrenceEndDate),
        'groupId': t.groupId ?? '',
        'reminderMinutes': t.reminderMinutes,
        // 执行器需要这些字段来生成完整快照，避免 AI 修改后丢失
        // 新版待办的协作、系列及本地元数据。
        'version': t.version,
        'updatedAt': t.updatedAt,
        'createdAt': t.createdAt,
        'imagePath': t.imagePath,
        'originalText': t.originalText,
        'teamUuid': t.teamUuid,
        'creatorId': t.creatorId,
        'creatorName': t.creatorName,
        'teamName': t.teamName,
        'collabType': t.collabType,
        'hasConflict': t.hasConflict,
        'serverVersionData': t.serverVersionData,
        'categoryId': t.categoryId,
      };
    }).toList();
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
