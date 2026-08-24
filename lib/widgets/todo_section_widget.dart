// ignore_for_file: unused_element

import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/app_dialogs.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../services/api_service.dart';
import '../storage_service.dart';
import '../screens/historical_todos_screen.dart';
import '../services/todo_parser_service.dart';
import '../services/llm_service.dart';
import '../services/course_service.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/ai_todo_chat_launcher.dart';
import '../services/pomodoro_service.dart';
import '../screens/course_screens.dart';
import '../screens/home_settings_screen.dart';
import '../screens/add_todo_screen.dart';
import 'home_sections.dart';
import 'todo_group_widget.dart';
import 'todo_recurrence_progress.dart';
import 'todo_recurrence_occurrence_picker.dart';
import 'todo_recurrence_completion_overview.dart';
import '../utils/local_image_provider.dart';
import '../utils/page_transitions.dart';
import '../screens/folder_manage_screen.dart';
import '../services/pomodoro_sync_service.dart';
import '../services/feature_tip_service.dart';
import '../services/item_semantics_service.dart';
import '../services/fixed_schedule_recurrence_service.dart';
import '../services/reminder_schedule_service.dart';
import '../widgets/coach_mark_overlay.dart';
import 'version_history_sheet.dart';
import 'ai_water_border.dart';
import '../screens/todo_plan_screen.dart';
import '../features/habits/models/habit_goal.dart';
import '../features/habits/repositories/habit_repository.dart';

part 'todo_section_widget_contract.dart';
part 'todo_section_widget_lifecycle.dart';
part 'todo_section_widget_capture.dart';
part 'todo_section_widget_recurrence.dart';
part 'todo_section_widget_view.dart';
part 'todo_section_widget_independent_status.dart';
part 'todo_edit_screen.dart';

enum _TodoFolderDisplayMode {
  inline,
  separate,
  urgentFirst,
  hidden,
}

enum _RecurrenceOccurrenceAction {
  toggleCompletion,
  edit,
}

enum _OccurrenceSwitchAction {
  cancel,
  discard,
  save,
}

enum _QuickCaptureTarget { todo, fixedSchedule, cancel }

class TodoSectionWidget extends StatefulWidget {
  final List<TodoItem> todos;
  final String username;
  final bool isLight;
  final Function(List<TodoItem>) onTodosChanged;
  final VoidCallback onRefreshRequested;
  final Set<String> highlightedTodoIds;
  final int remoteUpdateHighlightSignal;
  final List<TodoGroup> todoGroups;
  final List<ConflictInfo> conflicts;
  final Function(List<TodoGroup>) onGroupsChanged;

  /// 大模型识别成功后的回调，用于导航到确认页面
  final Function(
          List<Map<String, dynamic>>, String?, String?, String?, String?)?
      onLLMResultsParsed; // 🚀 参数：Results, imagePath, originalText, teamUuid, teamName

  final Function(String?, String?)? onTeamChanged; // 🚀 传参：ID, Name

  final Key? folderKey;
  final Key? historyKey;

  const TodoSectionWidget({
    super.key,
    required this.todos,
    required this.username,
    required this.isLight,
    required this.onTodosChanged,
    required this.onRefreshRequested,
    this.highlightedTodoIds = const <String>{},
    this.remoteUpdateHighlightSignal = 0,
    this.todoGroups = const [],
    this.conflicts = const [],
    this.onGroupsChanged = _defaultOnGroupsChanged,
    this.onLLMResultsParsed,
    this.onTeamChanged,
    this.initialSelectedTeamUuid,
    this.folderKey,
    this.historyKey,
  });

  final String? initialSelectedTeamUuid;

  static void _defaultOnGroupsChanged(List<TodoGroup> _) {}

  @override
  State<TodoSectionWidget> createState() => TodoSectionWidgetState();
}

Map<String, String> _buildRecurrenceSeriesRepresentativeIds(
  Map<String, List<TodoItem>> seriesOccurrences,
) {
  final representativeIds = <String, String>{};
  for (final entry in seriesOccurrences.entries) {
    TodoItem? latest;
    TodoItem? latestActive;
    for (final occurrence in entry.value) {
      if (occurrence.isDeleted) continue;
      final start = occurrence.createdDate ?? occurrence.createdAt;
      if (latest == null || start > (latest.createdDate ?? latest.createdAt)) {
        latest = occurrence;
      }
      if (occurrence.recurrence != RecurrenceType.none &&
          (latestActive == null ||
              start > (latestActive.createdDate ?? latestActive.createdAt))) {
        latestActive = occurrence;
      }
    }
    final representative = latestActive ?? latest;
    if (representative != null) {
      representativeIds[entry.key] = representative.id;
    }
  }
  return representativeIds;
}

bool _shouldDisplayRecurrenceTodo(
  TodoItem todo,
  Map<String, String> seriesRepresentativeIds,
) {
  final seriesId = todo.recurrenceSeriesId;
  if (seriesId == null || seriesId.isEmpty) return true;
  final representativeId = seriesRepresentativeIds[seriesId];
  return representativeId == null || representativeId == todo.id;
}

List<TodoItem> _filterHabitOnlyRecurringTodos(
  List<TodoItem> todos,
  Set<String> habitOnlySeriesIds,
) {
  if (habitOnlySeriesIds.isEmpty) return todos;
  return todos.where((todo) {
    final seriesId = todo.recurrenceSeriesId;
    return seriesId == null ||
        seriesId.isEmpty ||
        !habitOnlySeriesIds.contains(seriesId);
  }).toList();
}

List<TodoItem> _collapseRecurrenceInstancesForDisplayForTest(
  List<TodoItem> todos,
) {
  final seriesOccurrences = <String, List<TodoItem>>{};
  for (final todo in todos) {
    final seriesId = todo.recurrenceSeriesId;
    if (todo.isDeleted || seriesId == null || seriesId.isEmpty) continue;
    seriesOccurrences.putIfAbsent(seriesId, () => []).add(todo);
  }
  final representativeIds =
      _buildRecurrenceSeriesRepresentativeIds(seriesOccurrences);
  return todos
      .where((todo) =>
          !todo.isDeleted &&
          _shouldDisplayRecurrenceTodo(todo, representativeIds))
      .toList();
}

({int completedCount, int totalCount, int overdueCount})
    _calculateRecurrenceSummary({
  required List<TodoRecurrenceProgressNode> allNodes,
  required List<TodoRecurrenceProgressNode> historyNodes,
  required bool hasFixedEnd,
}) {
  final summaryNodes = hasFixedEnd ? allNodes : historyNodes;
  return (
    completedCount: summaryNodes
        .where((node) => node.state == TodoRecurrenceNodeState.completed)
        .length,
    totalCount: summaryNodes.length,
    overdueCount: summaryNodes
        .where((node) => node.state == TodoRecurrenceNodeState.overdue)
        .length,
  );
}

abstract class _TodoSectionStateBase extends State<TodoSectionWidget>
    with TickerProviderStateMixin, _TodoSectionContract {
  static const _kIdleAnimation = AlwaysStoppedAnimation(0.0);
  bool _isWholeListExpanded = true;
  bool _isTodayExpanded = true;
  bool _isTodayManuallyExpanded = false;
  bool _isPastTodosExpanded = false;
  bool _isFutureExpanded = true;
  bool _hasInitializedExpansion = false;

  final Map<String, GlobalKey> _todoCardKeys = {};
  final Map<String, Key> _todoDismissKeys = {};
  final Map<String, AnimationController> _completingAnimations = {};
  final Map<String, bool> _isCompleting = {};
  bool _inlineFolders = true;
  _TodoFolderDisplayMode _folderDisplayMode = _TodoFolderDisplayMode.inline;
  _TodoSectionViewModel? _cachedVm;
  int? _cachedVmSignature;
  Map<String, List<TodoItem>> _recurrenceSeriesOccurrences = const {};

  String? _selectedSubTeamUuid; // 🚀 内部视口：当前选择的团队 UUID
  final Map<String, String> _teamRoles = {}; // 🚀 缓存团队 ID -> 角色 (admin/member)
  List<Team> _teams = [];
  Set<String> _habitOnlyRecurringSeriesIds = <String>{};

  bool _isAiGeneratedTodo(TodoItem todo) => isAiGeneratedTodo(todo);
}

class TodoSectionWidgetState extends _TodoSectionStateBase
    with
        _TodoSectionLifecycleMixin,
        _TodoSectionCaptureMixin,
        _TodoSectionRecurrenceMixin,
        _TodoSectionViewMixin {
  @visibleForTesting
  static List<TodoItem> collapseRecurrenceInstancesForDisplayForTest(
    List<TodoItem> todos,
  ) =>
      _collapseRecurrenceInstancesForDisplayForTest(todos);

  @visibleForTesting
  static List<TodoItem> filterHabitOnlyRecurringTodosForTest(
    List<TodoItem> todos,
    Set<String> habitOnlySeriesIds,
  ) =>
      _filterHabitOnlyRecurringTodos(todos, habitOnlySeriesIds);

  @visibleForTesting
  static ({int completedCount, int totalCount, int overdueCount})
      recurrenceSummaryForTest({
    required List<TodoRecurrenceProgressNode> allNodes,
    required List<TodoRecurrenceProgressNode> historyNodes,
    required bool hasFixedEnd,
  }) =>
          _calculateRecurrenceSummary(
            allNodes: allNodes,
            historyNodes: historyNodes,
            hasFixedEnd: hasFixedEnd,
          );
}

class _AiAssistantContext {
  const _AiAssistantContext({
    this.courses = const [],
    this.timeLogs = const [],
    this.pomodoroRecords = const [],
    this.teams = const [],
  });

  final List<CourseItem> courses;
  final List<TimeLogItem> timeLogs;
  final List<PomodoroRecord> pomodoroRecords;
  final List<Team> teams;
}

class _TodoSectionViewModel {
  final DateTime today;
  final List<TodoItem> activeTodos;
  final Iterable<TodoGroup> activeGroups;
  final int undoneCount;
  final List<_SortedDisplayItem> pastItems;
  final List<_SortedDisplayItem> todayItems;
  final List<_SortedDisplayItem> futureItems;
  final List<_GroupDisplayData> separateGroupData;

  _TodoSectionViewModel({
    required this.today,
    required this.activeTodos,
    required this.activeGroups,
    required this.undoneCount,
    required this.pastItems,
    required this.todayItems,
    required this.futureItems,
    required this.separateGroupData,
  });
}

class _GroupDisplayData {
  final TodoGroup group;
  final List<TodoItem> todos;
  final bool isAllDone;
  final DateTime? minDate;
  final double progress;

  _GroupDisplayData({
    required this.group,
    required this.todos,
    required this.isAllDone,
    this.minDate,
    required this.progress,
  });
}

class _SortedDisplayItem {
  final TodoItem? todo;
  final TodoGroup? group;
  final DateTime? date;
  final bool isDone;
  final int startMs;
  final double progress;
  final List<TodoItem>? groupTodos;

  _SortedDisplayItem({
    this.todo,
    this.group,
    this.date,
    required this.isDone,
    this.startMs = 0,
    this.progress = 0.0,
    this.groupTodos,
  });
}
