import 'dart:async';
import 'dart:convert';

import 'package:countdown_todo/features/finance/models/finance_ai_action.dart';
import 'package:countdown_todo/features/finance/services/finance_text_parser.dart';
import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_native_tool_call_parser.dart';
import 'package:countdown_todo/services/ai_native_tool_definition_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _SseFixtureClient extends http.BaseClient {
  _SseFixtureClient(this.body);

  final String body;
  http.Request? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    this.request = request as http.Request;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {}
}

Map<String, dynamic> _toolNamed(
  List<Map<String, dynamic>> tools,
  String name,
) => tools.firstWhere((tool) => (tool['function'] as Map)['name'] == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('兼容模型路由和请求协议', () {
    test('MiMo 2.6 与应用列出的 Token Plan 模型启用原生工具', () {
      for (final model in [
        'mimo-v2.6-flash',
        'mimo-v2.6-pro',
        'mimo-v2.6-pro-ultraspeed',
      ]) {
        expect(
          AiChatService.supportsFunctionTools(
            provider: 'mimo',
            apiUrl: '${AiChatService.mimoApiBaseUrl}/chat/completions',
            model: model,
          ),
          isTrue,
          reason: model,
        );
      }

      for (final model in ['mimo-v2.5', 'mimo-v2.5-pro']) {
        expect(
          AiChatService.supportsFunctionTools(
            provider: AiChatService.mimoTokenPlanProvider,
            apiUrl:
                '${AiChatService.mimoTokenPlanOpenAiBaseUrl}/chat/completions',
            model: model,
          ),
          isTrue,
          reason: model,
        );
      }

      expect(
        AiChatService.supportsFunctionTools(
          provider: 'custom',
          apiUrl: 'https://aggregator.example/v1/chat/completions',
          model: 'mimo-v2.6-flash',
        ),
        isFalse,
      );
    });

    test('MiMo tools 请求使用 tool_choice=auto 并关闭思考模式', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '提醒我明天买牛奶',
      );
      final body = AiChatService.buildStreamingRequestBody(
        apiUrl: '${AiChatService.mimoApiBaseUrl}/chat/completions',
        model: 'mimo-v2.6-flash',
        messages: const [
          {'role': 'user', 'content': '提醒我明天买牛奶'},
        ],
        deepThinking: true,
        provider: 'mimo',
        tools: tools,
      );

      expect(body['tools'], isNotEmpty);
      expect(body['tool_choice'], 'auto');
      expect(body['max_completion_tokens'], isNotNull);
      expect(body['thinking'], {'type': 'disabled'});

      final tokenPlanBody = AiChatService.buildStreamingRequestBody(
        apiUrl: '${AiChatService.mimoTokenPlanOpenAiBaseUrl}/chat/completions',
        model: 'mimo-v2.5-pro',
        messages: const [
          {'role': 'user', 'content': '记一笔午餐28元'},
        ],
        deepThinking: true,
        provider: AiChatService.mimoTokenPlanProvider,
        tools: tools,
      );
      expect(tokenPlanBody['tools'], tools);
      expect(tokenPlanBody['tool_choice'], 'auto');
      expect(tokenPlanBody['max_completion_tokens'], isNotNull);
      expect(tokenPlanBody['thinking'], {'type': 'disabled'});
    });
  });

  group('CDT 和记账工具定义及解析', () {
    test('明确待办、规划块、习惯与记账请求会提供对应工具', () {
      const userMessage = '创建明天买牛奶待办，规划已有待办今天执行，再创建每天喝水习惯并记一笔午餐28元';
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        userMessage,
      );
      final names = AiNativeToolDefinitionBuilder.allowedToolNames(tools);

      expect(names, contains('propose_cdt_actions'));
      expect(names, contains('propose_finance_drafts'));
      final cdtActions = AiNativeToolDefinitionBuilder.allowedCdtActionNames(
        tools,
      );
      expect(
        cdtActions,
        containsAll(['create_todo', 'create_plan_block', 'create_habit']),
      );
      expect(
        (_toolNamed(tools, 'propose_finance_drafts')['function']
            as Map)['parameters'],
        isA<Map>(),
      );
      final financeDescription =
          (_toolNamed(tools, 'propose_finance_drafts')['function']
                  as Map)['description']
              .toString();
      expect(financeDescription, contains('点击“编辑并保存”'));
      expect(financeDescription, contains('聊天中的“确认/确定”不会保存'));
    });

    test('模型 tool_calls 可解析为待办、规划块、习惯和记账确认草案', () {
      const userMessage = '创建明天买牛奶待办，规划已有待办今天执行，再创建每天喝水习惯并记一笔午餐28元';
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        userMessage,
      );
      final allowedTools = AiNativeToolDefinitionBuilder.allowedToolNames(
        tools,
      );
      final calls = [
        AiChatFunctionCall(
          id: 'call-cdt',
          name: 'propose_cdt_actions',
          arguments: jsonEncode({
            'actions': [
              {
                'action': 'create_todo',
                'todos': [
                  {
                    'title': '买牛奶',
                    'timeMode': 'dateOnly',
                    'dueDate': '2026-10-03',
                  },
                ],
              },
              {
                'action': 'create_plan_block',
                'blocks': [
                  {
                    'todoId': 'todo-real-1',
                    'title': '复习英语',
                    'startTime': '2026-10-02 19:00',
                    'dueDate': '2026-10-02 19:30',
                    'durationMinutes': 30,
                  },
                ],
              },
              {
                'action': 'create_habit',
                'habits': [
                  {
                    'name': '喝水',
                    'sourceType': 'quantityCheckIn',
                    'periodType': 'daily',
                    'targetValue': 2000,
                    'unit': 'ml',
                  },
                ],
              },
            ],
          }),
        ),
        AiChatFunctionCall(
          id: 'call-finance',
          name: 'propose_finance_drafts',
          arguments: jsonEncode({
            'drafts': [
              {
                'type': 'expense',
                'amount': 28.0,
                'category': '餐饮',
                'merchant': '午餐',
                'date': '2026-10-02',
              },
            ],
          }),
        ),
      ];
      final protocolText = AiNativeToolCallParser.appendToAssistantText(
        '',
        calls,
        allowedToolNames: allowedTools,
        allowedCdtActionNames:
            AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
        allowedFinanceActionNames:
            AiNativeToolDefinitionBuilder.allowedFinanceActionNames(tools),
      );

      final todoActions = AiActionParser.extractTodoActions(
        protocolText,
        originalText: userMessage,
        existingTodoTitles: const {'todo-real-1': '复习英语'},
      );
      final drafts = FinanceTextParser.extractAssistantDrafts(
        protocolText,
        now: DateTime(2026, 10, 2),
      );

      expect(
        todoActions.map((action) => action.type),
        contains(AiTodoActionType.createTodo),
      );
      expect(
        todoActions.map((action) => action.type),
        contains(AiTodoActionType.createPlanBlock),
      );
      expect(
        todoActions.map((action) => action.type),
        contains(AiTodoActionType.createHabit),
      );
      expect(
        todoActions
            .firstWhere(
              (action) => action.type == AiTodoActionType.createPlanBlock,
            )
            .todoId,
        'todo-real-1',
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.amountMinor, 2800);
      expect(drafts.single.merchant, '午餐');
    });

    test('已有账单修改必须保留真实 transactionId', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '把这笔午餐账单改成35元',
        previousUserMessage: '查看本月账单明细',
      );
      final allowed = AiNativeToolDefinitionBuilder.allowedFinanceActionNames(
        tools,
      );
      expect(allowed, contains('update_finance'));

      final actionContent = AiNativeToolCallParser.appendToAssistantText(
        '',
        [
          AiChatFunctionCall(
            id: 'call-update',
            name: 'propose_finance_actions',
            arguments: jsonEncode({
              'actions': [
                {
                  'action': 'update_finance',
                  'transactionId': 'transaction-real-1',
                  'amount': 35.0,
                },
              ],
            }),
          ),
        ],
        allowedToolNames: AiNativeToolDefinitionBuilder.allowedToolNames(tools),
        allowedCdtActionNames:
            AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
        allowedFinanceActionNames: allowed,
      );
      final actions = FinanceTextParser.extractAssistantActions(actionContent);

      expect(actions, hasLength(1));
      expect(actions.single.type, FinanceAiActionType.update);
      expect(actions.single.transactionId, 'transaction-real-1');
      expect(actions.single.amountMinor, 3500);
    });

    test('已有账单删除同样需要 transactionId 并转成待确认操作', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '删除这笔午餐账单',
        previousUserMessage: '查看本月午餐账单明细',
      );
      final allowed = AiNativeToolDefinitionBuilder.allowedFinanceActionNames(
        tools,
      );
      expect(allowed, contains('delete_finance'));

      final actionContent = AiNativeToolCallParser.appendToAssistantText(
        '',
        [
          AiChatFunctionCall(
            id: 'call-delete',
            name: 'propose_finance_actions',
            arguments: jsonEncode({
              'actions': [
                {
                  'action': 'delete_finance',
                  'transactionId': 'transaction-real-2',
                  'reason': '用户明确要求删除',
                },
              ],
            }),
          ),
        ],
        allowedToolNames: AiNativeToolDefinitionBuilder.allowedToolNames(tools),
        allowedCdtActionNames:
            AiNativeToolDefinitionBuilder.allowedCdtActionNames(tools),
        allowedFinanceActionNames: allowed,
      );
      final actions = FinanceTextParser.extractAssistantActions(actionContent);

      expect(actions, hasLength(1));
      expect(actions.single.type, FinanceAiActionType.delete);
      expect(actions.single.transactionId, 'transaction-real-2');
    });

    test('普通创建待办不会向模型暴露完成或删除动作', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '提醒我明天买牛奶',
      );
      final actions = AiNativeToolDefinitionBuilder.allowedCdtActionNames(
        tools,
      );

      expect(actions, contains('create_todo'));
      expect(actions, isNot(contains('complete_todo')));
      expect(actions, isNot(contains('delete_todo')));
    });

    test('否定删除要求不会开放删除工具，明确删除要求仍可用', () {
      final negatedActions =
          AiNativeToolDefinitionBuilder.allowedCdtActionNames(
            AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
              '不要删除这个待办',
            ),
          );
      final explicitActions =
          AiNativeToolDefinitionBuilder.allowedCdtActionNames(
            AiNativeToolDefinitionBuilder.buildNativeToolDefinitions('删除这个待办'),
          );

      expect(negatedActions, isNot(contains('delete_todo')));
      expect(explicitActions, contains('delete_todo'));
    });

    test('周期类型不明确时不向模型提供创建工具', () {
      final tools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
        '每天跑步',
      );

      expect(tools, isEmpty);
    });
  });

  test('MiMo SSE 分片合并 tool_calls，并处理 finish_reason 和无换行 DONE', () async {
    final cdtTools = AiNativeToolDefinitionBuilder.buildNativeToolDefinitions(
      '提醒我明天买牛奶',
    );
    final firstArguments = '{"actions":[{"action":"create_todo",';
    final secondArguments =
        '"todos":[{"title":"买牛奶","timeMode":"dateOnly","dueDate":"2026-10-03"}]}]}';
    final frames = [
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call-1',
                  'type': 'function',
                  'function': {'name': 'propose_cdt_actions', 'arguments': firstArguments},
                },
              ],
            },
            'finish_reason': null,
          },
        ],
      })}\n\n',
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': secondArguments},
                },
              ],
            },
            'finish_reason': null,
          },
        ],
      })}\n\n',
      'data: ${jsonEncode({
        'choices': [
          {'delta': {}, 'finish_reason': 'tool_calls'},
        ],
      })}\n\n',
      'data: ${jsonEncode({
        'choices': <Object>[],
        'usage': {'prompt_tokens': 40, 'completion_tokens': 12, 'total_tokens': 52},
      })}\n\n',
      'data: [DONE]',
    ].join();
    final client = _SseFixtureClient(frames);
    final chunks = await AiChatService.streamChat(
      apiUrl: '${AiChatService.mimoApiBaseUrl}/chat/completions',
      apiKey: 'fixture-key',
      model: 'mimo-v2.6-flash',
      messages: const [
        {'role': 'user', 'content': '提醒我明天买牛奶'},
      ],
      deepThinking: true,
      provider: 'mimo',
      tools: cdtTools,
      clientFactory: () => client,
    ).toList();

    final request = client.request!;
    final requestBody = jsonDecode(request.body) as Map<String, dynamic>;
    expect(
      request.url.toString(),
      '${AiChatService.mimoApiBaseUrl}/chat/completions',
    );
    expect(requestBody['tools'], cdtTools);
    expect(requestBody['tool_choice'], 'auto');
    expect(requestBody['thinking'], {'type': 'disabled'});
    expect(chunks.expand((chunk) => chunk.toolCallDeltas), hasLength(2));
    expect(chunks.map((chunk) => chunk.finishReason), contains('tool_calls'));
    final completedCalls = chunks.expand((chunk) => chunk.toolCalls).toList();
    expect(completedCalls, hasLength(1));
    expect(completedCalls.single.id, 'call-1');
    expect(completedCalls.single.name, 'propose_cdt_actions');
    expect(jsonDecode(completedCalls.single.arguments), {
      'actions': [
        {
          'action': 'create_todo',
          'todos': [
            {'title': '买牛奶', 'timeMode': 'dateOnly', 'dueDate': '2026-10-03'},
          ],
        },
      ],
    });
  });

  test('工具调用和注入上下文可写入聊天历史并往返读取', () {
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: '已生成待确认草案',
      rawContent: '[NATIVE_TOOL_CALLS] ...',
      smartContext: '待办：买牛奶（ID: todo-1）',
      nativeToolCalls: const [
        ChatNativeToolCall(
          id: 'call-1',
          name: 'propose_cdt_actions',
          arguments: '{"actions":[]}',
          resultSummary: '应用解析出 1 条待确认操作草案。',
        ),
      ],
    );
    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.rawContent, message.rawContent);
    expect(restored.smartContext, message.smartContext);
    expect(restored.nativeToolCalls, hasLength(1));
    expect(restored.nativeToolCalls!.single.name, 'propose_cdt_actions');
    expect(restored.nativeToolCalls!.single.arguments, '{"actions":[]}');
    expect(restored.nativeToolCalls!.single.resultSummary, '应用解析出 1 条待确认操作草案。');
  });
}
