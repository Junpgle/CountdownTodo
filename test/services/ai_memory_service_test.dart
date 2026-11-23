import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/services/ai_memory_service.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/daily_ai_suggestion_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('add, deduplicate, update, delete, and clear memories', () async {
    final added = await AiMemoryService.addMemory(
      'alice',
      '  晚上22点后不安排高强度学习  ',
    );
    expect(added, isNotNull);
    expect(added!.content, '晚上22点后不安排高强度学习');
    expect(added.source, 'manual');

    await AiMemoryService.addMemory('alice', '晚上22点后不安排高强度学习', source: 'ai');
    var items = await AiMemoryService.loadMemories('alice');
    expect(items.length, 1);
    expect(items.first.source, 'ai');

    // Separate user scope remains empty.
    expect(await AiMemoryService.loadMemories('bob'), isEmpty);

    final updated = await AiMemoryService.updateMemory(
      'alice',
      items.first.id,
      '晚上22:30后只安排轻松阅读',
    );
    expect(updated, isTrue);
    items = await AiMemoryService.loadMemories('alice');
    expect(items.first.content, '晚上22:30后只安排轻松阅读');

    final deleted = await AiMemoryService.deleteMemory('alice', items.first.id);
    expect(deleted, isTrue);
    expect(await AiMemoryService.loadMemories('alice'), isEmpty);

    await AiMemoryService.addMemory('alice', '回复尽量简短');
    await AiMemoryService.clearMemories('alice');
    expect(await AiMemoryService.loadMemories('alice'), isEmpty);
  });

  test('enforces maxItems and maxItemLength', () async {
    final longText = '偏' * 150;
    final savedLong = await AiMemoryService.addMemory('alice', longText);
    expect(savedLong!.content.length, AiMemoryService.maxItemLength);

    for (var i = 0; i < 25; i++) {
      await AiMemoryService.addMemory('alice', '偏好_$i');
    }
    final items = await AiMemoryService.loadMemories('alice');
    expect(items.length, AiMemoryService.maxItems);
  });

  test('executeToolCall and text memory commands respect enabled switch', () async {
    final saveResult = await AiMemoryService.executeToolCall('alice', {
      'action': 'save',
      'content': '早上9点前优先处理核心任务',
    });
    expect(saveResult['ok'], isTrue);
    expect(
      await AiMemoryService.loadPromptBlock('alice'),
      contains('早上9点前优先处理核心任务'),
    );

    await AiMemoryService.setEnabled('alice', false);
    expect(await AiMemoryService.loadPromptBlock('alice'), isEmpty);
    final blockedResult = await AiMemoryService.executeToolCall('alice', {
      'action': 'save',
      'content': '不应该被保存',
    });
    expect(blockedResult['ok'], isFalse);
    expect(blockedResult['status'], 'memory_disabled');

    await AiMemoryService.setEnabled('alice', true);
    const rawReply =
        '好的，我记住了。[MEMORY_START]{"action":"save","content":"周末不安排工作"}[MEMORY_END]';
    final notices = await AiMemoryService.applyTextMemoryCommands(
      'alice',
      rawReply,
    );
    expect(notices.length, 1);
    expect(AiMemoryService.cleanContent(rawReply), '好的，我记住了。');
    expect(await AiMemoryService.loadPromptBlock('alice'), contains('周末不安排工作'));

    final deleteResult = await AiMemoryService.executeToolCall('alice', {
      'action': 'delete',
      'content': '周末不安排工作',
    });
    expect(deleteResult['ok'], isTrue);
    expect(
      await AiMemoryService.loadPromptBlock('alice'),
      isNot(contains('周末不安排工作')),
    );
  });

  test('injects memory block into chat and daily suggestion prompts', () {
    const memoryBlock = '【用户长期偏好记忆】\n- 晚上10点后休息';
    final chatPrompt = AiTodoContextBuilder.buildLeanSystemPrompt(
      customPrompt: '',
      promptEnabled: false,
      nativeToolCalls: true,
      memoryEnabled: true,
      memoryPromptBlock: memoryBlock,
    );
    expect(chatPrompt, contains(AiMemoryService.toolName));
    expect(chatPrompt, contains('晚上10点后休息'));

    final suggestionMessages = DailyAiSuggestionService.buildPromptMessages(
      now: DateTime(2026, 11, 15, 9, 0),
      todos: const [],
      countdowns: const [],
      planBlocks: const [],
      fixedSchedules: const [],
      courses: const [],
      memoryPromptBlock: memoryBlock,
    );
    expect(suggestionMessages.last['content'], contains('晚上10点后休息'));
  });
}
