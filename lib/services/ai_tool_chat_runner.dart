import 'dart:async';
import 'dart:convert';

import 'ai_chat_service.dart';
import 'ai_query_tool_service.dart';
import 'ai_tool_result_context.dart';
import 'ai_settings_navigation_service.dart';

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
    int maxQueryRounds = 4,
    int maxCalls = 8,
  }) async* {
    final history = [
      for (final message in messages) Map<String, dynamic>.from(message),
    ];
    final allowed = {
      for (final tool in tools) (tool['function'] as Map)['name'] as String,
    };
    var callCount = 0;
    var indexOffset = 0;
    var proposalsProduced = false;
    var planningRepairAttempted = false;
    final hasPlanningTool = tools.any((tool) {
      final function = tool['function'] as Map;
      return function['name'] == 'propose_cdt_actions' &&
          jsonEncode(function['parameters']).contains('create_plan_block');
    });
    final usedIds = <String>{};
    final completedQueries = <String, (String, Map<String, dynamic>)>{};
    var resultChars = 0;
    bool cancelled() => cancelToken?.isCompleted == true;

    for (var round = 0; round <= maxQueryRounds + 1; round++) {
      if (cancelled()) return;
      final finalRound =
          round >= maxQueryRounds ||
          callCount >= maxCalls ||
          resultChars > AiToolResultContext.maxTurnChars - 400;
      final roundTools = tools.where((tool) {
        final isQuery = AiQueryToolService.toolNames.contains(
          (tool['function'] as Map)['name'],
        );
        return (!finalRound || !isQuery) &&
            (!proposalsProduced || isQuery) &&
            (!planningRepairAttempted ||
                (tool['function'] as Map)['name'] == 'propose_cdt_actions');
      }).toList();
      if (finalRound && !planningRepairAttempted) {
        history.add({
          'role': 'system',
          'content':
              '本轮查询次数或数据预算已达上限。不要继续查询或编造数据。'
              '依据已有结果回答；若用户要求生成操作且信息齐全，仍可调用本轮保留的propose_*工具生成待确认草案。'
              '信息不足时说明缺少什么；未调用提案工具时不要声称已生成草案。',
        });
      }
      var content = '';
      var reasoning = '';
      final calls = <AiChatFunctionCall>[];
      var maxIndex = -1;
      final runRound = planningRepairAttempted
          ? streamProposalRound ?? streamRound
          : streamRound;
      await for (final chunk in runRound(history, roundTools)) {
        if (cancelled()) return;
        content += chunk.content;
        reasoning += chunk.reasoningContent;
        calls.addAll(chunk.toolCalls);
        for (final delta in chunk.toolCallDeltas) {
          if (delta.index > maxIndex) maxIndex = delta.index;
        }
        yield AiChatStreamChunk(
          // Planning prose is buffered until we know whether actual draft
          // calls arrived. Never flash a false "created/saved" claim.
          content: hasPlanningTool ? '' : chunk.content,
          reasoningContent: chunk.reasoningContent,
          toolCallDeltas: [
            for (final delta in chunk.toolCallDeltas)
              AiChatFunctionCallDelta(
                index: delta.index + indexOffset,
                id: delta.id,
                name: delta.name,
                arguments: delta.arguments,
              ),
          ],
          toolCalls: chunk.toolCalls,
          finishReason: chunk.finishReason,
          usage: chunk.usage,
          usageSummary: chunk.usageSummary,
        );
      }
      indexOffset += maxIndex + 1;
      if (cancelled()) return;
      if (calls.isEmpty && hasPlanningTool && !proposalsProduced) {
        final claimsDraft = RegExp(
          r'草案.{0,12}已生成|已(?:生成|创建|新建|保存)|我已为|回复.{0,12}确认.{0,20}保存',
        ).hasMatch(content);
        if ((requirePlanningProposal || claimsDraft) &&
            !planningRepairAttempted) {
          planningRepairAttempted = true;
          history.add({
            'role': 'assistant',
            'content': content,
            if (includeReasoningContent) 'reasoning_content': reasoning,
          });
          history.add({
            'role': 'system',
            'content':
                '上一条只有文字，没有返回规划工具调用，App没有创建任何待办或规划卡。'
                '用户已要求生成方案，请现在调用propose_cdt_actions提交create_plan_block。'
                '已有待办用真实todoId；不存在的事项用newTodoTitle，不编造ID。'
                '只生成待确认卡，不保存，不再要求回复确认。确实缺少日期或时段时明确说明缺少什么。',
          });
          continue;
        }
        yield AiChatStreamChunk(
          content: claimsDraft
              ? '模型没有返回可执行的规划草案，本次未创建或保存待办、规划块。请重试生成。'
              : content,
        );
        return;
      }
      if (hasPlanningTool && content.isNotEmpty) {
        yield AiChatStreamChunk(content: content);
      }
      if (calls.isEmpty) return;
      // A proposals-only response can be presented immediately as confirmation
      // cards. Mixed read/proposal responses still complete the read cycle.
      if (calls.every(
        (call) =>
            allowed.contains(call.name) && call.name.startsWith('propose_'),
      )) {
        return;
      }
      if (finalRound) throw StateError('模型在查询次数达到上限后仍返回查询调用');
      history.add({
        'role': 'assistant',
        'content': content,
        if (includeReasoningContent) 'reasoning_content': reasoning,
        'tool_calls': [
          for (final call in calls)
            {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.arguments},
            },
        ],
      });
      for (final call in calls) {
        if (cancelled()) return;
        callCount++;
        Map<String, dynamic> result;
        if (!allowed.contains(call.name)) {
          result = {'ok': false, 'error': '本轮未开放此工具'};
        } else if (!usedIds.add(call.id)) {
          result = {'ok': false, 'error': '重复的工具调用ID，未再次执行'};
        } else if (callCount > maxCalls) {
          result = {'ok': false, 'error': '本轮工具调用次数达到上限'};
        } else if (resultChars > AiToolResultContext.maxTurnChars - 400) {
          result = {'ok': false, 'error': '本轮数据预算达到上限，请根据已有结果回答'};
        } else if (AiQueryToolService.toolNames.contains(call.name)) {
          final key = AiToolResultContext.queryKey(call.name, call.arguments);
          final cached = completedQueries[key];
          if (cached != null) {
            result = {...cached.$2, 'reused_tool_call_id': cached.$1};
          } else {
            try {
              result = await executeRead(call)
                  .timeout(const Duration(seconds: 20));
              if (result['ok'] == true) {
                completedQueries[key] = (call.id, result);
              }
            } catch (_) {
              result = {'ok': false, 'error': '本地查询失败或超时，请稍后重试'};
            }
          }
        } else if (call.name == AiSettingsNavigationService.toolName) {
          proposalsProduced = true;
          final targets = AiSettingsNavigationService.targetsFromArguments(
            call.arguments,
          );
          result = {
            'ok': targets.isNotEmpty,
            'status': targets.isNotEmpty
                ? 'awaiting_navigation'
                : 'invalid_target',
            'targets': targets,
            'settings_changed': false,
            'message': targets.isNotEmpty
                ? '已生成设置入口卡片，用户点击后进入设置自行调整。'
                : '未找到有效设置入口，不要编造路径。',
          };
        } else {
          proposalsProduced = true;
          result = {
            'status': 'awaiting_confirmation',
            'saved': false,
            'message': '操作草案交给App解析并展示确认卡，尚未执行。请用户核对确认。',
          };
        }
        if (cancelled()) return;
        final modelSource = result.containsKey('reused_tool_call_id')
            ? <String, dynamic>{
                'ok': true,
                'reused_tool_call_id': result['reused_tool_call_id'],
                'message': '相同条件已查询，直接使用该调用的结果；未重复读取或回传明细。',
              }
            : result;
        final remaining = AiToolResultContext.maxTurnChars - resultChars;
        final modelResult = AiToolResultContext.forModel(
          modelSource,
          maxChars: remaining.clamp(400, AiToolResultContext.maxResultChars),
        );
        final encoded = jsonEncode(modelResult);
        resultChars += encoded.length;
        history.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': encoded,
        });
        yield AiChatStreamChunk(toolResults: {call.id: result});
      }
    }
  }
}
