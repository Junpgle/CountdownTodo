import 'dart:convert';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_native_tool_call_parser.dart';
import 'package:countdown_todo/services/ai_settings_navigation_service.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/ai_tool_chat_runner.dart';
import 'package:countdown_todo/services/ai_query_tool_service.dart';
import 'package:countdown_todo/utils/ai_settings_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tool = AiSettingsNavigationService.toolName;
  String parseNative(
    String arguments, {
    Set<String> allowed = const {tool},
  }) => AiNativeToolCallParser.appendToAssistantText(
    '可以在这里调整。',
    [AiChatFunctionCall(id: 'settings-1', name: tool, arguments: arguments)],
    allowedToolNames: allowed,
    allowedCdtActionNames: {},
    allowedFinanceActionNames: {},
  );

  test(
    'native settings calls produce a specific validated card, not mutations',
    () {
      final content = parseNative(
        jsonEncode({
          'targets': ['liquid_glass_transparency'],
        }),
      );
      expect(AiSettingsNavigationService.extractTargets(content), [
        'liquid_glass_transparency',
      ]);
      expect(AiActionParser.cleanActionContent(content), '可以在这里调整。');
      expect(
        AiActionParser.extractTodoActions(content, originalText: '我想调整液态玻璃透明度'),
        isEmpty,
      );
      expect(content, isNot(contains('[ACTION_START]')));
    },
  );

  test(
    'rejects invented routes, malformed arguments and unavailable tools',
    () {
      for (final arguments in [
        '{',
        '[]',
        '{"targets":"theme"}',
        '{"targets":["https://example.com","delete_all",42]}',
      ]) {
        expect(
          AiSettingsNavigationService.extractTargets(parseNative(arguments)),
          isEmpty,
        );
      }
      expect(
        AiSettingsNavigationService.extractTargets(
          parseNative('{"targets":["theme"]}', allowed: {}),
        ),
        isEmpty,
      );
    },
  );

  test('text protocol deduplicates and bounds cards, hiding incomplete blocks', () {
    const content =
        '找到这些设置。\n[SETTINGS_START]{"targets":["theme","theme","llm_config","animation","wallpaper","unknown"]}[SETTINGS_END]';
    expect(AiSettingsNavigationService.extractTargets(content), [
      'theme',
      'llm_config',
      'animation',
    ]);
    expect(AiActionParser.cleanActionContent(content), '找到这些设置。');
    expect(
      AiActionParser.cleanActionContent('正在查找[SETTINGS_START]{"targets":['),
      '正在查找',
    );
    expect(
      AiSettingsNavigationService.extractTargets(
        '[SETTINGS_START]{bad}[SETTINGS_END]',
      ),
      isEmpty,
    );
  });

  test('history persists cards and supplies honest context for follow-ups', () {
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: '找到了',
      settingsTargets: ['liquid_glass_transparency'],
    );
    final restored = ChatMessage.fromJson(
      jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
    );
    expect(restored.settingsTargets, ['liquid_glass_transparency']);
    expect(
      restored.copyWith(content: '请点击').settingsTargets,
      restored.settingsTargets,
    );
    expect(restored.toLLMMessage(), contains('未自动修改'));
    expect(restored.toLLMMessage(), contains('liquid_glass_transparency'));
    expect(
      ChatMessage.fromJson({'role': 'assistant', 'content': '旧消息'})
          .settingsTargets,
      isEmpty,
    );
    expect(
      ChatMessage.fromJson({
        'role': 'assistant',
        'content': '',
        'settingsTargets': ['unknown', 'theme'],
      }).settingsTargets,
      ['theme'],
    );
  });

  test(
    'both prompt modes describe settings navigation and every ID has a route',
    () {
      for (final native in [false, true]) {
        final prompt = AiTodoContextBuilder.buildLeanSystemPrompt(
          customPrompt: '',
          promptEnabled: false,
          nativeToolCalls: native,
        );
        expect(prompt, contains('liquid_glass_transparency'));
        expect(prompt, contains(native ? tool : '[SETTINGS_START]'));
      }
      final definition =
          AiSettingsNavigationService.buildDefinition()['function'] as Map;
      expect(definition['name'], tool);
      final properties = (definition['parameters'] as Map)['properties'] as Map;
      final ids =
          ((properties['targets'] as Map)['items'] as Map)['enum'] as List;
      expect(ids, contains('liquid_glass_transparency'));
      expect(ids.toSet().length, ids.length);
      for (final id in ids.cast<String>()) {
        expect(
          AiSettingsNavigation.pageFor(id, username: 'test'),
          isNotNull,
          reason: id,
        );
      }
      expect(
        AiSettingsNavigation.pageFor('arbitrary-route', username: 'test'),
        isNull,
      );
    },
  );
  test('mixed read and navigation calls report a card without claiming settings changed', () async {
    var round = 0;
    var reads = 0;
    Map<String, dynamic>? navigationResult;
    await for (final chunk in AiToolChatRunner.run(
      messages: [
        {'role': 'user', 'content': '查看今天待办，再帮我找到玻璃透明度设置'},
      ],
      tools: [
        AiSettingsNavigationService.buildDefinition(),
        ...AiQueryToolService.buildDefinitions(),
      ],
      streamRound: (messages, tools) async* {
        if (round++ == 0) {
          yield const AiChatStreamChunk(
            toolCalls: [
              AiChatFunctionCall(
                id: 'read-1',
                name: 'query_app_data',
                arguments: '{"domain":"todos"}',
              ),
              AiChatFunctionCall(
                id: 'nav-1',
                name: 'propose_settings_navigation',
                arguments: '{"targets":["liquid_glass_transparency"]}',
              ),
            ],
          );
        } else {
          final result = messages.singleWhere(
            (item) => item['tool_call_id'] == 'nav-1',
          );
          expect(
            jsonDecode(result['content'] as String)['status'],
            'awaiting_navigation',
          );
          yield const AiChatStreamChunk(content: '可以点击卡片调整。');
        }
      },
      executeRead: (call) async {
        reads++;
        return {'ok': true, 'items': []};
      },
    )) {
      navigationResult ??= chunk.toolResults['nav-1'];
    }
    expect(reads, 1);
    expect(round, 2);
    expect(navigationResult?['targets'], ['liquid_glass_transparency']);
    expect(navigationResult?['settings_changed'], false);
  });
}
