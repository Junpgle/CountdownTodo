import 'dart:async';
import 'dart:convert';

import '../features/finance/models/finance_models.dart';
import 'ai_action_parser.dart';
import 'ai_chat_service.dart';
import 'ai_memory_service.dart';
import 'ai_native_tool_call_parser.dart';
import 'ai_native_tool_definition_builder.dart';
import 'ai_query_tool_service.dart';
import 'ai_planning_draft_validator.dart';
import 'ai_tool_result_context.dart';
import 'ai_settings_navigation_service.dart';
import 'ai_todo_context_builder.dart';
import 'ai_tool_chat/ai_cdt_action_labels.dart';

part 'ai_tool_chat/ai_tool_chat_runner_loop.dart';
part 'ai_tool_chat/ai_tool_chat_runner_legacy.dart';
part 'ai_tool_chat/ai_tool_chat_runner_proposal_validation.dart';
part 'ai_tool_chat/ai_tool_chat_runner_cdt_validation.dart';

typedef AiToolRoundStream = Stream<AiChatStreamChunk> Function(
  List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>> tools,
);
typedef AiReadToolExecutor = Future<Map<String, dynamic>> Function(
  AiChatFunctionCall call,
);

/// Continues the same user turn after the app returns read-only tool results.
/// Mutation tools stay proposals handled by the existing confirmation UI.

abstract final class AiToolChatRunner {
  static Stream<AiChatStreamChunk> run({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required AiToolRoundStream streamRound,
    AiToolRoundStream? streamProposalRound,
    required AiReadToolExecutor executeRead,
    Completer<void>? cancelToken,
    bool includeReasoningContent = false,
    bool requirePlanningProposal = false,
    String planningRequestText = '',
    String previousUserMessage = '',
    String previousAssistantMessage = '',
    Set<String>? knownTodoIds,
    Set<String>? knownHabitIds,
    Set<String>? knownFinanceTransactionIds,
    Map<String, Set<String>>? knownFinanceCatalogIdsByKind,
    Map<String, Set<String>>? knownReferenceIdsByDomain,
    DateTime? planningNow,
    int? maxQueryRounds = 4,
    int? maxCalls = 8,
    int? maxTurnChars = AiToolResultContext.maxTurnChars,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> arguments)?
    onManageMemory,
  }) => _runAiToolChat(
    messages: messages,
    tools: tools,
    streamRound: streamRound,
    streamProposalRound: streamProposalRound,
    executeRead: executeRead,
    cancelToken: cancelToken,
    includeReasoningContent: includeReasoningContent,
    requirePlanningProposal: requirePlanningProposal,
    planningRequestText: planningRequestText,
    previousUserMessage: previousUserMessage,
    previousAssistantMessage: previousAssistantMessage,
    knownTodoIds: knownTodoIds,
    knownHabitIds: knownHabitIds,
    knownFinanceTransactionIds: knownFinanceTransactionIds,
    knownFinanceCatalogIdsByKind: knownFinanceCatalogIdsByKind,
    knownReferenceIdsByDomain: knownReferenceIdsByDomain,
    planningNow: planningNow,
    maxQueryRounds: maxQueryRounds,
    maxCalls: maxCalls,
    maxTurnChars: maxTurnChars,
    onManageMemory: onManageMemory,
  );

  /// Detects replies that are legitimately asking for missing write details.
  /// Shared by native and text-protocol write recovery so neither path turns a
  /// clarification into an inferred mutation.
  static bool isLikelyClarification(String content) =>
      _isLikelyClarification(content);
}
