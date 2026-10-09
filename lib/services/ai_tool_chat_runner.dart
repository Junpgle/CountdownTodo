import 'dart:async';
import 'dart:convert';

import 'ai_chat_service.dart';
import 'ai_query_tool_service.dart';
import 'ai_tool_result_context.dart';

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
    required AiReadToolExecutor executeRead,
    Completer<void>? cancelToken,
    bool includeReasoningContent = false,
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
    final usedIds = <String>{};
    final completedQueries = <String, (String, Map<String, dynamic>)>{};
    var resultChars = 0;
    bool cancelled() => cancelToken?.isCompleted == true;

    for (var round = 0; round <= maxQueryRounds; round++) {
      if (cancelled()) return;
      final finalRound =
          round == maxQueryRounds ||
          callCount >= maxCalls ||
          resultChars > AiToolResultContext.maxTurnChars - 400;
      final roundTools = finalRound
          ? <Map<String, dynamic>>[]
          : tools
                .where(
                  (tool) =>
                      !proposalsProduced ||
                      AiQueryToolService.toolNames.contains(
                        (tool['function'] as Map)['name'],
                      ),
                )
                .toList();
      if (finalRound) {
        history.add({
          'role': 'system',
          'content':
              '本轮查询次数或数据预算已达上限。请依据已有工具结果回答；说明未查询到或尚未展开的数据，不要继续调用工具或编造数据。',
        });
      }
      var content = '';
      var reasoning = '';
      final calls = <AiChatFunctionCall>[];
      var maxIndex = -1;
      await for (final chunk in streamRound(history, roundTools)) {
        if (cancelled()) return;
        content += chunk.content;
        reasoning += chunk.reasoningContent;
        calls.addAll(chunk.toolCalls);
        for (final delta in chunk.toolCallDeltas) {
          if (delta.index > maxIndex) maxIndex = delta.index;
        }
        yield AiChatStreamChunk(
          content: chunk.content,
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
      if (cancelled() || calls.isEmpty) return;
      if (finalRound) throw StateError('模型在查询次数达到上限后仍返回工具调用');
      // A proposals-only response can be presented immediately as confirmation
      // cards. Mixed read/proposal responses still complete the read cycle.
      if (calls.every(
        (call) =>
            allowed.contains(call.name) && call.name.startsWith('propose_'),
      )) {
        return;
      }
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
