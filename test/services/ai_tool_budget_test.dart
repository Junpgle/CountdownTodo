import 'dart:convert';

import 'package:countdown_todo/models/ai_tool_budget.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_query_tool_service.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/ai_tool_chat_runner.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/widgets/ai_tool_budget_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _queryTool(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'parameters': {'type': 'object', 'properties': {}},
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('AiToolBudget 默认值、预设匹配、边界归一化与序列化正确', () {
    expect(AiToolBudget.standard.maxQueryRounds, 4);
    expect(AiToolBudget.standard.maxCalls, 8);
    expect(AiToolBudget.standard.maxTurnChars, 24000);
    expect(AiToolBudget.standard.matchingPreset, AiToolBudgetPreset.standard);
    expect(AiToolBudget.extended.matchingPreset, AiToolBudgetPreset.extended);
    expect(AiToolBudget.generous.matchingPreset, AiToolBudgetPreset.generous);

    const outOfRange = AiToolBudget(
      maxQueryRounds: 0,
      maxCalls: 999,
      maxTurnChars: 100,
    );
    final normalized = outOfRange.normalized();
    expect(normalized.maxQueryRounds, AiToolBudget.minQueryRounds);
    expect(normalized.maxCalls, 999);
    expect(normalized.maxTurnChars, AiToolBudget.minTurnChars);

    expect(AiToolBudget.unlimited.matchingPreset, AiToolBudgetPreset.unlimited);
    expect(
      AiToolBudget.fromStorage(AiToolBudget.unlimited.toStorageString()),
      AiToolBudget.unlimited,
    );

    const custom = AiToolBudget(
      maxQueryRounds: 6,
      maxCalls: 14,
      maxTurnChars: 36000,
    );
    expect(custom.matchingPreset, isNull);
    expect(custom.summaryLabel, contains('自定义'));
    expect(AiToolBudget.fromStorage(custom.toStorageString()), custom);
    expect(AiToolBudget.fromStorage('not-json'), AiToolBudget.standard);
    expect(AiToolBudget.fromStorage(null), AiToolBudget.standard);
  });

  test('ChatStorageService 持久化、读取与重置工具调用预算', () async {
    expect(await ChatStorageService.getToolBudget(), AiToolBudget.standard);

    const custom = AiToolBudget(
      maxQueryRounds: 10,
      maxCalls: 22,
      maxTurnChars: 60000,
    );
    await ChatStorageService.setToolBudget(custom);
    expect(await ChatStorageService.getToolBudget(), custom);

    await ChatStorageService.resetToolBudget();
    expect(await ChatStorageService.getToolBudget(), AiToolBudget.standard);
  });

  test('AiToolChatRunner 使用自定义 maxTurnChars 控制单轮数据字符预算', () async {
    var turn = 0;
    final observedToolPayloads = <String>[];

    final chunks = await AiToolChatRunner.run(
      messages: [
        {'role': 'user', 'content': '查两次大结果'},
      ],
      tools: [_queryTool('query_app_data')],
      maxQueryRounds: 4,
      maxCalls: 8,
      maxTurnChars: 1200,
      streamRound: (messages, tools) async* {
        for (final message in messages) {
          if (message['role'] == 'tool') {
            observedToolPayloads.add(message['content'] as String);
          }
        }
        turn++;
        if (turn == 1) {
          yield AiChatStreamChunk(
            toolCalls: [
              const AiChatFunctionCall(
                id: 'q1',
                name: 'query_app_data',
                arguments: '{"domain":"todos","offset":0}',
              ),
              const AiChatFunctionCall(
                id: 'q2',
                name: 'query_app_data',
                arguments: '{"domain":"todos","offset":50}',
              ),
            ],
          );
          return;
        }
        yield const AiChatStreamChunk(content: '已根据预算内结果完成回答');
      },
      executeRead: (call) async => {'ok': true, 'summary': 'x' * 900},
    ).toList();

    expect(chunks.map((c) => c.content).join(), contains('已根据预算内结果完成回答'));
    expect(observedToolPayloads.length, 2);
    // Second tool call hits the 1200-char custom turn budget after the first call.
    final secondPayload =
        jsonDecode(observedToolPayloads[1]) as Map<String, dynamic>;
    expect(secondPayload['ok'], false);
    expect(secondPayload['error'], contains('预算达到上限'));
    expect(
      observedToolPayloads.fold<int>(0, (sum, item) => sum + item.length),
      lessThanOrEqualTo(1200),
    );
  });

  test('AiToolChatRunner 提高 maxTurnChars 后允许单轮回传超过默认 24k 的数据', () async {
    var turn = 0;
    final observedToolPayloads = <String>[];

    final chunks = await AiToolChatRunner.run(
      messages: [
        {'role': 'user', 'content': '查四次大结果'},
      ],
      tools: [_queryTool('query_app_data')],
      maxQueryRounds: 4,
      maxCalls: 8,
      maxTurnChars: 48000,
      streamRound: (messages, tools) async* {
        for (final message in messages) {
          if (message['role'] == 'tool') {
            observedToolPayloads.add(message['content'] as String);
          }
        }
        turn++;
        if (turn == 1) {
          yield AiChatStreamChunk(
            toolCalls: [
              for (var i = 1; i <= 4; i++)
                AiChatFunctionCall(
                  id: 'q$i',
                  name: 'query_app_data',
                  arguments: '{"domain":"todos","offset":${i * 50}}',
                ),
            ],
          );
          return;
        }
        yield const AiChatStreamChunk(content: '已汇总四页数据');
      },
      executeRead: (call) async => {
        'ok': true,
        'items': [
          for (var i = 0; i < 6; i++)
            {'id': '${call.id}-$i', 'title': 'x' * 1100},
        ],
      },
    ).toList();

    expect(chunks.map((c) => c.content).join(), contains('已汇总四页数据'));
    expect(observedToolPayloads.length, 4);
    final totalChars = observedToolPayloads.fold<int>(
      0,
      (sum, item) => sum + item.length,
    );
    expect(totalChars, greaterThan(24000));
    for (final raw in observedToolPayloads) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['ok'], true);
    }
  });

  testWidgets('showAiToolBudgetDialog 支持选择预设、恢复默认并保存', (tester) async {
    AiToolBudget? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  saved = await showAiToolBudgetDialog(
                    context,
                    initialBudget: AiToolBudget.standard,
                  );
                },
                child: const Text('打开预算设置'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开预算设置'));
    await tester.pumpAndSettle();

    expect(find.text('单轮工具调用预算'), findsOneWidget);
    expect(find.text('4 轮'), findsOneWidget);
    expect(find.text('8 次'), findsOneWidget);
    expect(find.text('24k 字符'), findsOneWidget);

    await tester.tap(find.text('充裕'));
    await tester.pumpAndSettle();
    expect(find.text('12 轮'), findsOneWidget);
    expect(find.text('30 次'), findsOneWidget);
    expect(find.text('80k 字符'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, AiToolBudget.generous);

    await tester.tap(find.text('打开预算设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '不限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, AiToolBudget.unlimited);
  });

  test('AiToolChatRunner 在不限预算模式下允许超过默认轮数、次数与字符上限', () async {
    var turn = 0;
    final observedToolPayloads = <String>[];

    final chunks = await AiToolChatRunner.run(
      messages: [
        {'role': 'user', 'content': '连续查6轮'},
      ],
      tools: [_queryTool('query_app_data')],
      maxQueryRounds: null,
      maxCalls: null,
      maxTurnChars: null,
      streamRound: (messages, tools) async* {
        if (turn == 6) {
          for (final message in messages) {
            if (message['role'] == 'tool') {
              observedToolPayloads.add(message['content'] as String);
            }
          }
          yield const AiChatStreamChunk(content: '全部6轮查询已完成');
          return;
        }
        turn++;
        yield AiChatStreamChunk(
          toolCalls: [
            AiChatFunctionCall(
              id: 'q-$turn-a',
              name: 'query_app_data',
              arguments: '{"domain":"todos","offset":${turn * 10}}',
            ),
            AiChatFunctionCall(
              id: 'q-$turn-b',
              name: 'query_app_data',
              arguments: '{"domain":"todos","offset":${turn * 10 + 5}}',
            ),
          ],
        );
      },
      executeRead: (call) async => {
        'ok': true,
        'items': [
          for (var i = 0; i < 4; i++)
            {'id': '${call.id}-$i', 'title': 'x' * 700},
        ],
      },
    ).toList();

    expect(chunks.map((c) => c.content).join(), contains('全部6轮查询已完成'));
    expect(observedToolPayloads.length, 12);
    final totalChars = observedToolPayloads.fold<int>(
      0,
      (sum, item) => sum + item.length,
    );
    expect(totalChars, greaterThan(24000));
  });

  test('AiQueryToolService.hasPriorBudgetLimit 准确识别历史轮次是否触发预算上限', () {
    expect(AiQueryToolService.hasPriorBudgetLimit(const []), isFalse);

    final normalTurn = [
      ChatMessage(
        role: ChatRole.assistant,
        content: '这是今天的待办汇总。',
        nativeToolCalls: const [
          ChatNativeToolCall(
            id: 'q1',
            name: 'query_app_data',
            arguments: '{"domain":"todos"}',
            result: {'ok': true, 'items': []},
          ),
        ],
      ),
    ];
    expect(
      AiQueryToolService.hasPriorBudgetLimit(normalTurn, maxCalls: 8),
      isFalse,
    );

    final errorLimitTurn = [
      ChatMessage(
        role: ChatRole.assistant,
        content: '部分数据未查全。',
        nativeToolCalls: const [
          ChatNativeToolCall(
            id: 'q2',
            name: 'query_app_data',
            arguments: '{"domain":"todos"}',
            result: {'ok': false, 'error': '本轮工具调用次数达到上限'},
          ),
        ],
      ),
    ];
    expect(
      AiQueryToolService.hasPriorBudgetLimit(errorLimitTurn, maxCalls: 8),
      isTrue,
    );

    final textLimitTurn = [
      ChatMessage(
        role: ChatRole.assistant,
        content: '由于本轮查询次数已达上限，先展示已有结果。',
        nativeToolCalls: const [
          ChatNativeToolCall(
            id: 'q3',
            name: 'query_app_data',
            arguments: '{"domain":"todos"}',
            result: {'ok': true, 'items': []},
          ),
        ],
      ),
    ];
    expect(
      AiQueryToolService.hasPriorBudgetLimit(textLimitTurn, maxCalls: 8),
      isTrue,
    );
  });

  test('buildLeanSystemPrompt 在自定义提示词缺少 {now} 时仍兜底注入当前基准时间', () {
    final prompt = AiTodoContextBuilder.buildLeanSystemPrompt(
      customPrompt: '请简短回答用户问题。',
      promptEnabled: true,
      nativeToolCalls: true,
      queryTools: true,
      now: DateTime(2026, 11, 15, 15, 7),
    );
    expect(prompt, contains('当前基准时间：2026-11-15 15:07'));
    expect(prompt, contains('未指定年份的月份或日期默认按当前基准时间所在年份理解'));
    expect(AiQueryToolService.systemPrompt, contains('默认按当前基准时间所在年份理解'));
  });
}
