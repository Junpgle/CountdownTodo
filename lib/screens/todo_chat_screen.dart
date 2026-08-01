import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../models/ai_todo_action.dart';
import '../services/suggestion_feedback_service.dart';
import '../models/chat_message.dart';
import '../services/ai_action_parser.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_todo_context_builder.dart';
import '../services/ai_todo_action_executor.dart';
import '../services/llm_service.dart';
import '../services/chat_storage_service.dart';
import '../services/pomodoro_control_service.dart';
import '../services/pomodoro_service.dart';
import '../screens/ai_assistant_tutorial_screen.dart';
import '../screens/settings/llm_config_page.dart';
import '../storage_service.dart';
import '../utils/page_transitions.dart';
import '../services/feature_tip_service.dart';
import '../services/reminder_schedule_service.dart';
import '../widgets/coach_mark_overlay.dart';

part 'todo_chat_screen_contract.dart';
part 'todo_chat_screen_lifecycle.dart';
part 'todo_chat_screen_send.dart';
part 'todo_chat_screen_layout.dart';
part 'todo_chat_screen_actions.dart';
part 'todo_chat_screen_messages.dart';
part 'todo_chat_screen_widgets.dart';

class TodoChatScreen extends StatefulWidget {
  final String username;
  final List<Map<String, dynamic>> todos;
  final List<TodoGroup> todoGroups;
  final List<CourseItem> courses;
  final List<TimeLogItem> timeLogs;
  final List<PomodoroRecord> pomodoroRecords;
  final List<ConflictInfo> conflicts;
  final List<Team> teams;
  final List<CountdownItem> countdowns;
  final List<PomodoroTag> pomodoroTags;
  final List<FixedScheduleItem> fixedSchedules;
  final List<AiTodoAction> initialCategorizationActions;
  final Function(TodoItem)? onTodoInserted;
  final Function(List<TodoItem>)? onTodosBatchInserted;
  final Function(List<TodoItem>)? onTodosUpdated;
  final Function(List<TodoItem> inserted, List<TodoItem> updated)?
      onTodosBatchAction;
  final Function(List<TodoGroup> groups)? onTodoGroupsChanged;
  final Function(List<FixedScheduleItem> schedules)? onFixedSchedulesChanged;

  const TodoChatScreen({
    super.key,
    required this.username,
    required this.todos,
    this.todoGroups = const [],
    this.courses = const [],
    this.timeLogs = const [],
    this.pomodoroRecords = const [],
    this.conflicts = const [],
    this.teams = const [],
    this.countdowns = const [],
    this.pomodoroTags = const [],
    this.fixedSchedules = const [],
    this.initialCategorizationActions = const [],
    this.onTodoInserted,
    this.onTodosBatchInserted,
    this.onTodosUpdated,
    this.onTodosBatchAction,
    this.onTodoGroupsChanged,
    this.onFixedSchedulesChanged,
  });

  @override
  State<TodoChatScreen> createState() => _TodoChatScreenState();
}

class _TodoChatScreenState extends _TodoChatScreenStateBase
    with
        _TodoChatLifecycle,
        _TodoChatSend,
        _TodoChatLayout,
        _TodoChatActions,
        _TodoChatMessages {}
