import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/ai_todo_action.dart';
import '../models.dart';
import 'ai_memory_service.dart';
import 'ai_team_binding_resolver.dart';
import 'chat_storage_service.dart';
import 'pomodoro_service.dart';
import 'ai_settings_navigation_service.dart';

part 'ai_context/ai_todo_context_prompts.dart';
part 'ai_context/ai_todo_context_injection.dart';
part 'ai_context/ai_todo_context_intent_actions.dart';
part 'ai_context/ai_todo_context_intent_routing.dart';
part 'ai_context/ai_todo_context_keywords.dart';
part 'ai_context/ai_todo_context_formatters.dart';
part 'ai_context/ai_todo_context_time.dart';

class AiTodoContextBuilder {
  static const pendingWriteProposalContextMarker =
      _pendingWriteProposalContextMarker;
  static const pendingCountdownDraftsContextMarker =
      _pendingCountdownDraftsContextMarker;
  static const int actionProtocolVersion = _actionProtocolVersion;
  static const int smartContextProtocolVersion = _smartContextProtocolVersion;
  static const todoSkipMutationKeywords = _todoSkipMutationKeywords;
  static const todoCompletionMutationKeywords = _todoCompletionMutationKeywords;
  static const todoListMutationKeywords = _todoListMutationKeywords;
  static const focusMutationKeywords = _focusMutationKeywords;

  static AiContextDateRange? resolveCustomInjectionDateRange({
    DateTime? customStart,
    DateTime? customEnd,
    bool injectMoreContext = false,
    DateTime? now,
  }) => _resolveCustomInjectionDateRange(
    customStart: customStart,
    customEnd: customEnd,
    injectMoreContext: injectMoreContext,
    now: now,
  );

  static String buildContextQueryText({
    required String userMessage,
    DateTime? customStart,
    DateTime? customEnd,
    bool injectMoreContext = false,
    DateTime? now,
  }) => _buildContextQueryText(
    userMessage: userMessage,
    customStart: customStart,
    customEnd: customEnd,
    injectMoreContext: injectMoreContext,
    now: now,
  );

  static String buildLeanSystemPrompt({
    required String customPrompt,
    required bool promptEnabled,
    bool nativeToolCalls = false,
    bool queryTools = false,
    bool settingsNavigation = true,
    bool memoryEnabled = false,
    String memoryPromptBlock = '',
    DateTime? now,
  }) => _buildLeanSystemPrompt(
    customPrompt: customPrompt,
    promptEnabled: promptEnabled,
    nativeToolCalls: nativeToolCalls,
    queryTools: queryTools,
    settingsNavigation: settingsNavigation,
    memoryEnabled: memoryEnabled,
    memoryPromptBlock: memoryPromptBlock,
    now: now,
  );

  static String buildActionProtocolPrompt(
    String userMessage, {
    String previousUserMessage = '',
    String previousAssistantMessage = '',
    List<Team> availableTeams = const [],
  }) => _buildActionProtocolPrompt(
    userMessage,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
    availableTeams: availableTeams,
  );

  static String buildSystemPrompt({
    required String customPrompt,
    required bool promptEnabled,
    required List<Map<String, dynamic>> todos,
    required List<TodoGroup> todoGroups,
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<FixedScheduleItem> fixedSchedules = const [],
    DateTime? now,
  }) => _buildSystemPrompt(
    customPrompt: customPrompt,
    promptEnabled: promptEnabled,
    todos: todos,
    todoGroups: todoGroups,
    countdowns: countdowns,
    pomodoroTags: pomodoroTags,
    planBlocks: planBlocks,
    fixedSchedules: fixedSchedules,
    now: now,
  );

  /// 根据用户消息关键词，返回需要注入的上下文片段。无匹配返回 null。
  static String? buildContextInjection({
    required String userMessage,
    String previousUserMessage = '',
    required List<CourseItem> courses,
    required List<TimeLogItem> timeLogs,
    List<TodoGroup> todoGroups = const [],
    List<PomodoroRecord> pomodoroRecords = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<Map<String, dynamic>> todos = const [],
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<FixedScheduleItem> fixedSchedules = const [],
    required List<ConflictInfo> conflicts,
    required List<Team> teams,
    bool expandFocusContext = false,
    AiContextDateRange? focusRecordPriorityRange,
    DateTime? now,
  }) => _buildContextInjection(
    userMessage: userMessage,
    previousUserMessage: previousUserMessage,
    courses: courses,
    timeLogs: timeLogs,
    todoGroups: todoGroups,
    pomodoroRecords: pomodoroRecords,
    planBlocks: planBlocks,
    todos: todos,
    countdowns: countdowns,
    pomodoroTags: pomodoroTags,
    fixedSchedules: fixedSchedules,
    conflicts: conflicts,
    teams: teams,
    expandFocusContext: expandFocusContext,
    focusRecordPriorityRange: focusRecordPriorityRange,
    now: now,
  );

  /// 返回用于输入区提示的注入摘要，不包含完整上下文正文。
  static String? buildContextInjectionSummary({
    required String userMessage,
    String previousUserMessage = '',
    required List<CourseItem> courses,
    required List<TimeLogItem> timeLogs,
    List<TodoGroup> todoGroups = const [],
    List<PomodoroRecord> pomodoroRecords = const [],
    List<TodoPlanBlock> planBlocks = const [],
    List<Map<String, dynamic>> todos = const [],
    List<CountdownItem> countdowns = const [],
    List<PomodoroTag> pomodoroTags = const [],
    List<FixedScheduleItem> fixedSchedules = const [],
    required List<ConflictInfo> conflicts,
    required List<Team> teams,
    bool expandFocusContext = false,
    DateTime? now,
  }) => _buildContextInjectionSummary(
    userMessage: userMessage,
    previousUserMessage: previousUserMessage,
    courses: courses,
    timeLogs: timeLogs,
    todoGroups: todoGroups,
    pomodoroRecords: pomodoroRecords,
    planBlocks: planBlocks,
    todos: todos,
    countdowns: countdowns,
    pomodoroTags: pomodoroTags,
    fixedSchedules: fixedSchedules,
    conflicts: conflicts,
    teams: teams,
    expandFocusContext: expandFocusContext,
    now: now,
  );

  /// Prevents short cancellations and declines from inheriting an earlier
  /// write request or exposing unrelated proposal tools.
  static bool isExplicitOperationDecline(String text) =>
      _isExplicitOperationDecline(text);

  static bool isExplicitScheduleMutationRequest(String text) =>
      _isExplicitScheduleMutationRequest(text);

  static Set<String> explicitScheduleActionNames(String text) =>
      _explicitScheduleActionNames(text);

  static Set<String> explicitPlanningActionNames(String text) =>
      _explicitPlanningActionNames(text);

  /// Carries only an explicit creation request across an assistant's parameter
  /// clarification. Short answers such as a title, date, or duration otherwise
  /// lose the action type and can be routed to an unrelated tool.
  static String inheritExplicitCreationClarification(
    String userMessage, {
    required String previousUserMessage,
    required String previousAssistantMessage,
  }) => _inheritExplicitCreationClarification(
    userMessage,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
  );

  static bool isExplicitTodoGroupManagementRequest(String text) =>
      _isExplicitTodoGroupManagementRequest(text);

  /// Recognizes common spoken commands such as "帮我记两个待办" and
  /// "我要写两条任务" without treating how-to questions as write requests.
  static bool isExplicitTodoCreationRequest(String text) =>
      _isExplicitTodoCreationRequest(text);

  static int? explicitTodoCreationCount(String text) =>
      _explicitTodoCreationCount(text);

  /// Recognizes a requested number of new ledger entries, such as "记两笔
  /// 支出" or "新增3笔账单". Count validation only runs for explicit write
  /// requests so a read-only statement about existing entries is unaffected.
  static int? explicitFinanceDraftCount(String text) =>
      _explicitFinanceDraftCount(text);

  static bool isExplicitHabitCreationRequest(String text) =>
      _isExplicitHabitCreationRequest(text);

  static bool isExplicitHabitMutationRequest(String text) =>
      _isExplicitHabitMutationRequest(text);

  static Set<String> explicitHabitActionNames(
    String text, {
    String previousAssistantMessage = '',
  }) => _explicitHabitActionNames(
    text,
    previousAssistantMessage: previousAssistantMessage,
  );

  /// Identifies concrete CDT action types explicitly requested in the current
  /// turn so a mixed request cannot be marked complete after only one action.
  static Set<String> requiredExplicitCdtActionNames(
    String text, {
    String previousUserMessage = '',
    String previousAssistantMessage = '',
  }) => _requiredExplicitCdtActionNames(
    text,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
  );

  /// Keeps explicit focus writes out of the generic read-only route for
  /// "记录", while leaving questions on the query path.
  static bool isExplicitFocusMutationRequest(String text) =>
      _isExplicitFocusMutationRequest(text);

  static Set<String> explicitFocusActionNames(String text) =>
      _explicitFocusActionNames(text);

  static Set<String> explicitCountdownActionNames(String text) =>
      _explicitCountdownActionNames(text);

  /// Returns the exact suffix requested for every title in a pending
  /// countdown draft set. Follow-up corrections may refer to the immediately
  /// preceding request, but only when the app has supplied pending draft data.
  static String? pendingCountdownTitleSuffixForRequest(
    String text, {
    String previousUserMessage = '',
    String previousAssistantMessage = '',
  }) => _pendingCountdownTitleSuffixForRequest(
    text,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
  );

  /// Serializes pending countdowns as model context, not as an executable
  /// command. The model must return a new proposal through the normal tool.
  static String pendingCountdownDraftContext(List<AiTodoAction> actions) =>
      _pendingCountdownDraftContext(actions);

  static String extractPendingCountdownDraftContext(String text) =>
      _extractPendingCountdownDraftContext(text);

  static bool isExplicitCountdownMutationRequest(String text) =>
      _isExplicitCountdownMutationRequest(text);

  static bool isExplicitlyTargetingTodo(String text) =>
      _isExplicitlyTargetingTodo(text);

  /// Disambiguates an amount-bearing transaction record from finance queries
  /// that also contain broad words such as "记录" or "支出".
  static bool isExplicitFinanceDraftRequest(String text) =>
      _isExplicitFinanceDraftRequest(text);

  /// Only expose the ledger-write proposal for an explicit transaction request
  /// or a concise amount-bearing entry. Financial planning amounts such as a
  /// budget, loan, balance, or investment are not transactions by themselves.
  static bool shouldOfferFinanceDraftProposal(String text) =>
      _shouldOfferFinanceDraftProposal(text);

  static bool hasExplicitFinanceDeleteIntent(String text) =>
      _hasExplicitFinanceDeleteIntent(text);

  static bool hasExplicitFinanceUpdateIntent(String text) =>
      _hasExplicitFinanceUpdateIntent(text);

  static bool isExplicitlyRequested(String text, String trigger) =>
      _isExplicitlyRequested(text, trigger);

  static String buildPromptPreview({
    required String customPrompt,
    required bool promptEnabled,
    required List<Map<String, dynamic>> todos,
    required List<TodoGroup> todoGroups,
    DateTime? now,
  }) => _buildPromptPreview(
    customPrompt: customPrompt,
    promptEnabled: promptEnabled,
    todos: todos,
    todoGroups: todoGroups,
    now: now,
  );

  static String buildManualCopyPrompt(List<Map<String, dynamic>> messages) =>
      _buildManualCopyPrompt(messages);
}
