import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_native_tool_call_parser.dart';
import 'package:countdown_todo/services/ai_native_tool_definition_builder.dart';
import 'package:countdown_todo/services/ai_query_tool_service.dart';
import 'package:countdown_todo/services/ai_tool_chat_runner.dart';
import 'package:countdown_todo/services/ai_tool_result_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _FixtureClient extends http.BaseClient {
  _FixtureClient(this.respond);
  final String Function(Map<String, dynamic> body) respond;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    return http.StreamedResponse(Stream.value(utf8.encode(respond(body))), 200);
  }

  @override
  void close() {}
}

String _sse(Map<String, dynamic> delta, String finish) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
    })}\n\n'
    'data: [DONE]\n\n';

const _queryCall = AiChatFunctionCall(
  id: 'q-1',
  name: 'query_finance',
  arguments: '{"view":"summary","start_date":"2026-09-01","end_date_exclusive":"2026-10-01"}',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final tools = AiQueryToolService.buildDefinitions();
  const messages = <Map<String, dynamic>>[
    {'role': 'user', 'content': '查询上个月的账单'},
  ];

  test('仅文字声称规划已生成时自动补一次工具调用，错误文字不显示', () async {
    final planningTools =
        AiNativeToolDefinitionBuilder.buildNativeToolDefinitions('生成规划块');
    var rounds = 0;
    final chunks = await AiToolChatRunner.run(
      messages: const [
        {'role': 'user', 'content': '可以，生成规划块'},
      ],
      tools: planningTools,
      maxQueryRounds: 0,
      requirePlanningProposal: true,
      streamRound: (history, roundTools) async* {
        if (++rounds == 1) {
          yield const AiChatStreamChunk(content: '规划块草案已生成，我已为它们创建待办，回复确认以保存。');
        } else {
          expect(history.last['content'], contains('没有返回规划工具调用'));
          expect(AiNativeToolDefinitionBuilder.allowedToolNames(roundTools), {
            'propose_cdt_actions',
          });
          yield const AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'new-plans',
                name: 'propose_cdt_actions',
                arguments: '{"actions":[{"action":"create_plan_block","blocks":[{"newTodoTitle":"行测","startTime":"2026-10-10 16:20","dueDate":"2026-10-10 17:45"}]}]}',
              ),
            ],
          );
        }
      },
      executeRead: (_) async => throw StateError('不得执行写入'),
    ).toList();
    expect(rounds, 2);
    expect(chunks.map((chunk) => chunk.content).join(), isEmpty);
    expect(chunks.expand((chunk) => chunk.toolCalls), hasLength(1));
  });

  test('模型两次都只声称生成时明确报告失败，不无限重试也不伪造卡片', () async {
    var rounds = 0;
    final chunks = await AiToolChatRunner.run(
      messages: const [
        {'role': 'user', 'content': '要的'},
      ],
      tools: AiNativeToolDefinitionBuilder.buildNativeToolDefinitions('生成规划块'),
      requirePlanningProposal: true,
      streamRound: (_, _) async* {
        rounds++;
        yield const AiChatStreamChunk(content: '规划块草案已生成，请回复确认以保存。');
      },
      executeRead: (_) async => throw StateError('不能写入'),
    ).toList();
    expect(rounds, 2);
    expect(
      chunks.map((chunk) => chunk.content).join(),
      contains('没有返回可执行的规划草案'),
    );
    expect(chunks.expand((chunk) => chunk.toolCalls), isEmpty);
  });

  test('续聊中的完整新规划请求隔离旧草案历史并正常生成新操作卡', () async {
    const request =
        '请从现在开始安排我今天剩下的时间，截止晚上21:30，避开晚餐。'
        '我要完成：公考行测复习、公考申论复习、习概小论文选题和提交、预备党员在线党课学习。'
        '请生成规划块操作卡供我核对，不要自动保存。';
    final planningTools = [
      ...tools,
      ...AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(request),
    ];
    var rounds = 0;
    final chunks = await AiToolChatRunner.run(
      messages: const [
        {'role': 'system', 'content': '基础系统提示'},
        {'role': 'system', 'content': '只读查询工具说明'},
        {'role': 'user', 'content': '帮我规划今天的待办'},
        {
          'role': 'assistant',
          'content': '已生成1条待确认操作草案，请核对。'
              '\n[READ_ONLY_TOOL_HISTORY]旧对话中的待办查询结果[/READ_ONLY_TOOL_HISTORY]',
        },
        {'role': 'user', 'content': request},
      ],
      planningRequestText: request,
      tools: planningTools,
      requirePlanningProposal: true,
      streamRound: (history, _) async* {
        rounds++;
        expect(
          history.where((message) => message['role'] == 'user').map(
            (message) => message['content'],
          ),
          [request],
        );
        expect(
          history.any(
            (message) =>
                '${message['content']}'.contains('旧对话中的待办查询结果') ||
                '${message['content']}'.contains('已生成1条待确认操作草案'),
          ),
          isFalse,
        );
        if (rounds == 1) {
          expect(history.last['role'], 'user');
          yield const AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'current-todos',
                name: 'query_app_data',
                arguments: '{"domain":"todos","view":"list"}',
              ),
            ],
          );
        } else {
          expect(history.last['role'], 'tool');
          yield const AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'new-planning-draft',
                name: 'propose_cdt_actions',
                arguments:
                    '{"actions":[{"action":"create_plan_block","blocks":[{"newTodoTitle":"行测","startTime":"2026-10-10 18:00","dueDate":"2026-10-10 18:30"}]}]}',
              ),
            ],
          );
        }
      },
      executeRead: (_) async => {
        'ok': true,
        'items': [
          {'id': 'todo-xingce', 'title': '行测'},
        ],
      },
    ).toList();

    expect(rounds, 2);
    expect(
      chunks.expand((chunk) => chunk.toolCalls).last.name,
      'propose_cdt_actions',
    );
  });

  test('不完整的规划追问仍保留之前对话上下文', () async {
    const request = '那按之前的安排继续到晚上九点半';
    var historyRetained = false;
    await AiToolChatRunner.run(
      messages: const [
        {'role': 'system', 'content': '基础系统提示'},
        {'role': 'user', 'content': '行测和申论排到晚上九点半'},
        {'role': 'assistant', 'content': '晚餐后安排行测，再安排申论。'},
        {'role': 'user', 'content': request},
      ],
      planningRequestText: request,
      tools: [
        ...tools,
        ...AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(request),
      ],
      requirePlanningProposal: true,
      streamRound: (history, _) async* {
        historyRetained = history.any(
          (message) => message['content'] == '晚餐后安排行测，再安排申论。',
        );
        yield const AiChatStreamChunk(content: '请确认之前设置的具体时间。');
      },
      executeRead: (_) async => throw StateError('不能执行写入'),
    ).toList();
    expect(historyRetained, isTrue);
  });

  test('真正缺少时段时允许澄清，不把普通规划咨询强制变成操作', () async {
    var rounds = 0;
    final chunks = await AiToolChatRunner.run(
      messages: const [
        {'role': 'user', 'content': '帮我规划行测'},
      ],
      tools: AiNativeToolDefinitionBuilder.buildNativeToolDefinitions('帮我规划行测'),
      streamRound: (_, _) async* {
        rounds++;
        yield const AiChatStreamChunk(content: '请告诉我哪一天、从几点到几点。');
      },
      executeRead: (_) async => throw StateError('不能写入'),
    ).toList();
    expect(rounds, 1);
    expect(chunks.map((chunk) => chunk.content).join(), contains('哪一天'));
  });

  test('可以接续公考规划，查询上限后仍通过真实SSE生成可解析规划草案', () async {
    final proposalTools =
        AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
          '可以',
          previousUserMessage: '从现在开始安排公考行测、申论和习概选题，帮我规划到晚上九点半',
        );
    final allTools = [...tools, ...proposalTools];
    var requests = 0;
    var reads = 0;
    final chunks = await AiToolChatRunner.run(
      messages: const [
        {'role': 'user', 'content': '可以'},
      ],
      tools: allTools,
      maxQueryRounds: 1,
      streamRound: (history, roundTools) => AiChatService.streamChat(
        apiUrl: '${AiChatService.mimoApiBaseUrl}/chat/completions',
        apiKey: 'fixture-key',
        model: 'mimo-v2.6-flash',
        provider: 'mimo',
        deepThinking: false,
        messages: history,
        tools: roundTools,
        clientFactory: () => _FixtureClient((body) {
          requests++;
          if (requests == 1) {
            return _sse({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'todos',
                  'type': 'function',
                  'function': {
                    'name': 'query_app_data',
                    'arguments': '{"domain":"todos","keyword":"习概"}',
                  },
                },
              ],
            }, 'tool_calls');
          }
          expect(AiNativeToolDefinitionBuilder.allowedToolNames(roundTools), {
            'propose_cdt_actions',
          });
          expect(history.last['role'], 'system');
          return _sse({
            'tool_calls': [
              {
                'index': 0,
                'id': 'plans',
                'type': 'function',
                'function': {
                  'name': 'propose_cdt_actions',
                  'arguments': jsonEncode({
                    'actions': [
                      {
                        'action': 'create_plan_block',
                        'blocks': [
                          {
                            'todoId': 'xigai-1',
                            'startTime': '2026-10-10 20:30',
                            'dueDate': '2026-10-10 21:30',
                          },
                        ],
                      },
                    ],
                  }),
                },
              },
            ],
          }, 'tool_calls');
        }),
      ),
      executeRead: (call) async {
        reads++;
        expect(call.name, 'query_app_data');
        return {
          'ok': true,
          'items': [
            {'id': 'xigai-1', 'title': '习概选题'},
          ],
        };
      },
    ).toList();
    expect(requests, 2);
    expect(reads, 1);
    final actionText = AiNativeToolCallParser.appendToAssistantText(
      '[READ_ONLY_TOOL_HISTORY]{"queries":[]}[/READ_ONLY_TOOL_HISTORY]',
      chunks.expand((chunk) => chunk.toolCalls).toList(),
      allowedToolNames: AiNativeToolDefinitionBuilder.allowedToolNames(
        allTools,
      ),
      allowedCdtActionNames:
          AiNativeToolDefinitionBuilder.allowedCdtActionNames(allTools),
      allowedFinanceActionNames: const {},
    );
    expect(actionText, isNot(contains('READ_ONLY_TOOL_HISTORY')));
    final actions = AiActionParser.extractTodoActions(
      actionText,
      originalText: '可以',
      existingTodoTitles: const {'xigai-1': '习概选题'},
    );
    expect(actions, hasLength(1));
    expect(actions.single.todoId, 'xigai-1');
    expect(actions.single.isAdded, false);
  });

  test('查询调用数量上限保留提案工具，不再执行额外读取', () async {
    var rounds = 0;
    var reads = 0;
    await AiToolChatRunner.run(
      messages: messages,
      tools: [
        ...tools,
        {
          'type': 'function',
          'function': {'name': 'propose_cdt_actions'},
        },
      ],
      maxCalls: 1,
      streamRound: (_, roundTools) async* {
        if (++rounds == 1) {
          yield const AiChatStreamChunk(toolCalls: [_queryCall]);
        } else {
          expect(AiNativeToolDefinitionBuilder.allowedToolNames(roundTools), {
            'propose_cdt_actions',
          });
          yield const AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'proposal',
                name: 'propose_cdt_actions',
                arguments: '{}',
              ),
            ],
          );
        }
      },
      executeRead: (_) async {
        reads++;
        return {'ok': true};
      },
    ).toList();
    expect(rounds, 2);
    expect(reads, 1);
  });

  test('真实SSE工具调用回传匹配ID和JSON，第二次请求生成最终答复', () async {
    var requests = 0;
    var executions = 0;
    final chunks = await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      streamRound: (history, roundTools) => AiChatService.streamChat(
        apiUrl: '${AiChatService.mimoApiBaseUrl}/chat/completions',
        apiKey: 'fixture-key',
        model: 'mimo-v2.6-flash',
        provider: 'mimo',
        deepThinking: false,
        messages: history,
        tools: roundTools,
        clientFactory: () => _FixtureClient((body) {
          requests++;
          if (requests == 1) {
            expect(body['tools'], hasLength(3));
            expect(body['messages'], messages);
            return _sse({
              'tool_calls': [
                {
                  'index': 0,
                  'id': _queryCall.id,
                  'type': 'function',
                  'function': {
                    'name': _queryCall.name,
                    'arguments': _queryCall.arguments,
                  },
                },
              ],
            }, 'tool_calls');
          }
          final sent = body['messages'] as List;
          expect((sent[sent.length - 2] as Map)['tool_calls'], hasLength(1));
          expect(sent.last['role'], 'tool');
          expect(sent.last['tool_call_id'], 'q-1');
          expect(jsonDecode(sent.last['content'] as String), {
            'ok': true,
            'net_expense_minor': 12345,
          });
          return _sse({'content': '上个月净支出123.45元。'}, 'stop');
        }),
      ),
      executeRead: (call) async {
        executions++;
        expect(
          jsonDecode(call.arguments),
          containsPair('start_date', '2026-09-01'),
        );
        return {'ok': true, 'net_expense_minor': 12345};
      },
    ).toList();
    expect(requests, 2);
    expect(executions, 1);
    expect(chunks.map((chunk) => chunk.content).join(), '上个月净支出123.45元。');
    expect(chunks.expand((chunk) => chunk.toolResults.keys), ['q-1']);
  });

  test('多次查询和分页调用均保留独立结果及连续流式索引', () async {
    var round = 0;
    final chunks = await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      streamRound: (history, _) async* {
        round++;
        if (round <= 2) {
          if (round == 2) expect(history.last['tool_call_id'], 'page-1');
          final call = AiChatFunctionCall(
            id: 'page-$round',
            name: 'query_finance',
            arguments: '{"offset":${(round - 1) * 30}}',
          );
          yield AiChatStreamChunk(
            toolCallDeltas: [
              AiChatFunctionCallDelta(
                index: 0,
                id: call.id,
                name: call.name,
                arguments: call.arguments,
              ),
            ],
          );
          yield AiChatStreamChunk(toolCalls: [call]);
        } else {
          expect(
            history.where((message) => message['role'] == 'tool'),
            hasLength(2),
          );
          yield const AiChatStreamChunk(content: '已读取两页明细。');
        }
        yield const AiChatStreamChunk(
          usageSummary: ChatUsageSummary(
            provider: 'mimo',
            model: 'fixture',
            promptTokens: 10,
            completionTokens: 5,
          ),
        );
      },
      executeRead: (call) async => {
        'ok': true,
        'offset': jsonDecode(call.arguments)['offset'],
      },
    ).toList();
    expect(
      chunks
          .expand((chunk) => chunk.toolCallDeltas)
          .map((delta) => delta.index),
      [0, 1],
    );
    expect(chunks.expand((chunk) => chunk.toolResults.keys), [
      'page-1',
      'page-2',
    ]);
    final usage = ChatUsageSummary.combine(
      chunks.map((chunk) => chunk.usageSummary).whereType<ChatUsageSummary>(),
    )!;
    expect(usage.calls, 3);
    expect(usage.promptTokens, 30);
  });

  test('失败返回交给模型修正，未开放工具不执行', () async {
    var round = 0;
    var executions = 0;
    await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      streamRound: (history, _) async* {
        round++;
        if (round == 1) {
          yield const AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(id: 'bad', name: 'run_sql', arguments: '{}'),
            ],
          );
        } else if (round == 2) {
          expect(jsonDecode(history.last['content'] as String)['ok'], false);
          yield const AiChatStreamChunk(toolCalls: [_queryCall]);
        } else {
          yield const AiChatStreamChunk(content: '查询完成');
        }
      },
      executeRead: (_) async {
        executions++;
        return {'ok': true};
      },
    ).toList();
    expect(executions, 1);
  });

  test('取消发生在查询中时，不再向模型发送结果', () async {
    final cancel = Completer<void>();
    var rounds = 0;
    final chunks = await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      cancelToken: cancel,
      streamRound: (_, _) async* {
        rounds++;
        yield const AiChatStreamChunk(toolCalls: [_queryCall]);
      },
      executeRead: (_) async {
        cancel.complete();
        return {'ok': true};
      },
    ).toList();
    expect(rounds, 1);
    expect(chunks.expand((chunk) => chunk.toolResults.keys), isEmpty);
  });

  test('查询上限后移除工具并要求基于已有结果完成答复', () async {
    var rounds = 0;
    await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      maxQueryRounds: 1,
      streamRound: (history, roundTools) async* {
        rounds++;
        if (rounds == 1) {
          yield const AiChatStreamChunk(toolCalls: [_queryCall]);
        } else {
          expect(roundTools, isEmpty);
          expect(history.last['role'], 'system');
          yield const AiChatStreamChunk(content: '根据已查询的账单回复');
        }
      },
      executeRead: (_) async => {'ok': true},
    ).toList();
    expect(rounds, 2);
  });

  test('纯操作提案继续交给确认卡，不执行写入或额外调用模型', () async {
    var rounds = 0;
    final proposalTools = [
      {
        'type': 'function',
        'function': {'name': 'propose_cdt_actions'},
      },
    ];
    await AiToolChatRunner.run(
      messages: messages,
      tools: proposalTools,
      streamRound: (_, _) async* {
        rounds++;
        yield const AiChatStreamChunk(
          toolCalls: [
            AiChatFunctionCall(
              id: 'proposal',
              name: 'propose_cdt_actions',
              arguments: '{}',
            ),
          ],
        );
      },
      executeRead: (_) async => throw StateError('不能执行写入提案'),
    ).toList();
    expect(rounds, 1);
  });

  test('查询和提案混合时回传待确认状态，后续不重复提供提案工具', () async {
    var rounds = 0;
    await AiToolChatRunner.run(
      messages: messages,
      tools: [
        ...tools,
        {
          'type': 'function',
          'function': {'name': 'propose_cdt_actions'},
        },
      ],
      includeReasoningContent: true,
      streamRound: (history, roundTools) async* {
        rounds++;
        if (rounds == 1) {
          yield const AiChatStreamChunk(
            reasoningContent: '需要先查询',
            toolCalls: [
              _queryCall,
              AiChatFunctionCall(
                id: 'proposal',
                name: 'propose_cdt_actions',
                arguments: '{}',
              ),
            ],
          );
        } else {
          expect(roundTools, hasLength(3));
          expect(
            jsonDecode(history.last['content'] as String)['status'],
            'awaiting_confirmation',
          );
          expect(
            history
                .where((message) => message['role'] == 'assistant')
                .single['reasoning_content'],
            '需要先查询',
          );
          yield const AiChatStreamChunk(content: '请核对操作草案');
        }
      },
      executeRead: (_) async => {'ok': true},
    ).toList();
    expect(rounds, 2);
  });

  test('相同查询只执行一次，重复调用仅引用之前结果，UI仍有完整记录', () async {
    var round = 0;
    var executions = 0;
    final result = {
      'ok': true,
      'total_count': 3,
      'items': [
        {'id': 'todo-1', 'title': '任务'},
      ],
    };
    final chunks = await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      streamRound: (history, _) async* {
        round++;
        if (round <= 2) {
          yield AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'same-$round',
                name: 'query_app_data',
                arguments: round == 1
                    ? '{"domain":"todos","status":"pending"}'
                    : '{"status":"pending","view":"list","domain":"todos","limit":10,"offset":0}',
              ),
            ],
          );
        } else {
          final repeated = jsonDecode(history.last['content'] as String) as Map;
          expect(repeated['reused_tool_call_id'], 'same-1');
          expect(repeated, isNot(contains('items')));
          yield const AiChatStreamChunk(content: '查询完成');
        }
      },
      executeRead: (_) async {
        executions++;
        return result;
      },
    ).toList();
    expect(executions, 1);
    final ui = {for (final chunk in chunks) ...chunk.toolResults};
    expect(ui['same-1'], result);
    expect(ui['same-2']!['items'], result['items']);
  });

  test('失败不会缓存，允许相同参数重试', () async {
    var rounds = 0;
    var executions = 0;
    await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      streamRound: (_, _) async* {
        if (++rounds <= 2) {
          yield AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'retry-$rounds',
                name: _queryCall.name,
                arguments: _queryCall.arguments,
              ),
            ],
          );
        } else {
          yield const AiChatStreamChunk(content: '已重试');
        }
      },
      executeRead: (_) async => {'ok': ++executions > 1},
    ).toList();
    expect(executions, 2);
  });

  test('大结果受单次与本轮预算限制，完整原始返回仍送往对话卡片', () async {
    var rounds = 0;
    final chunks = await AiToolChatRunner.run(
      messages: messages,
      tools: tools,
      streamRound: (history, roundTools) async* {
        rounds++;
        if (rounds <= 3) {
          yield AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'large-$rounds',
                name: 'query_app_data',
                arguments: '{"domain":"todos","offset":${rounds * 50}}',
              ),
            ],
          );
        } else {
          final results = history.where((m) => m['role'] == 'tool').toList();
          expect(
            results.fold<int>(
              0,
              (sum, m) => sum + (m['content'] as String).length,
            ),
            lessThanOrEqualTo(AiToolResultContext.maxTurnChars),
          );
          for (final m in results) {
            expect(
              (m['content'] as String).length,
              lessThanOrEqualTo(AiToolResultContext.maxResultChars),
            );
            final decoded = jsonDecode(m['content'] as String) as Map;
            expect(decoded['total_count'], 1000);
            expect(decoded['context_truncated'], true);
            expect(decoded['next_offset'], greaterThan(0));
          }
          yield const AiChatStreamChunk(content: '已查看部分任务，共1000项。');
        }
      },
      executeRead: (call) async => {
        'ok': true,
        'total_count': 1000,
        'summary': {'count': 1000},
        'offset': jsonDecode(call.arguments)['offset'],
        'has_more': true,
        'items': [
          for (var i = 0; i < 50; i++)
            {'id': 'todo-$i', 'title': '任务$i', 'remark': '大段备注' * 5000},
        ],
      },
    ).toList();
    final ui = {for (final c in chunks) ...c.toolResults};
    expect(ui, hasLength(3));
    expect(ui['large-1']!['items'], hasLength(50));
  });
}
