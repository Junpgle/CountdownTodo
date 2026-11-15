import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'first opening creates an active empty session without persisting it',
    () async {
      final session = await ChatStorageService.openEmptySession();

      expect(await ChatStorageService.getActiveSessionId(), session.id);
      expect(await ChatStorageService.loadHistory(session.id), isEmpty);
      expect(await ChatStorageService.loadSessions(), isEmpty);
    },
  );

  test(
    'reopening without chatting reuses the same unsaved empty session',
    () async {
      final first = await ChatStorageService.openEmptySession();
      final second = await ChatStorageService.openEmptySession();
      final third = await ChatStorageService.openEmptySession();

      expect(second.id, first.id);
      expect(third.id, first.id);
      expect(await ChatStorageService.loadSessions(), isEmpty);
    },
  );

  test('concurrent openings share one unsaved empty session', () async {
    final opened = await Future.wait(
      List.generate(12, (_) => ChatStorageService.openEmptySession()),
    );

    expect(opened.map((session) => session.id).toSet(), hasLength(1));
    expect(await ChatStorageService.loadSessions(), isEmpty);
    expect(await ChatStorageService.getActiveSessionId(), opened.first.id);
  });

  test(
    'reopening after chatting starts empty and preserves old history',
    () async {
      final previous = await ChatStorageService.openEmptySession();
      final history = [
        ChatMessage(role: ChatRole.user, content: '帮我规划今天'),
        ChatMessage(role: ChatRole.assistant, content: '先完成报告'),
      ];
      await ChatStorageService.saveHistory(history, previous.id);
      expect(await ChatStorageService.loadSessions(), hasLength(1));

      final opened = await ChatStorageService.openEmptySession();

      expect(opened.id, isNot(previous.id));
      expect(await ChatStorageService.getActiveSessionId(), opened.id);
      expect(await ChatStorageService.loadHistory(opened.id), isEmpty);
      expect(
        (await ChatStorageService.loadHistory(previous.id)).map((m) => m.id),
        history.map((m) => m.id),
      );
      expect(await ChatStorageService.loadSessions(), hasLength(1));

      final reopened = await ChatStorageService.openEmptySession();
      expect(reopened.id, opened.id);
      expect(await ChatStorageService.loadSessions(), hasLength(1));
    },
  );

  test(
    'a user message without a reply is persisted and starts a new draft',
    () async {
      final previous = await ChatStorageService.openEmptySession();
      await ChatStorageService.addMessage(
        ChatMessage(role: ChatRole.user, content: '请求未完成'),
        sessionId: previous.id,
      );

      final opened = await ChatStorageService.openEmptySession();

      expect(opened.id, isNot(previous.id));
      expect(await ChatStorageService.loadHistory(opened.id), isEmpty);
      expect(await ChatStorageService.loadHistory(previous.id), hasLength(1));
      expect((await ChatStorageService.loadSessions()).single.id, previous.id);
    },
  );

  test('openEmptySession batch-cleans pre-existing empty sessions', () async {
    final empty1 = await ChatStorageService.createSession(title: '空对话1');
    final nonEmpty = await ChatStorageService.createSession(title: '有效对话');
    await ChatStorageService.saveHistory([
      ChatMessage(role: ChatRole.user, content: '你好'),
    ], nonEmpty.id);
    final empty2 = await ChatStorageService.createSession(title: '空对话2');
    await ChatStorageService.setActiveSessionId(empty2.id);

    final opened = await ChatStorageService.openEmptySession();

    final saved = await ChatStorageService.loadSessions();
    expect(saved.map((s) => s.id).toList(), [nonEmpty.id]);
    expect(opened.id, isNot(empty1.id));
    expect(opened.id, isNot(empty2.id));
    expect(await ChatStorageService.getActiveSessionId(), opened.id);
  });

  test(
    'deleteEmptySessions removes only empty sessions and updates active id',
    () async {
      final empty1 = await ChatStorageService.createSession(title: '空1');
      final keep = await ChatStorageService.createSession(title: '保留');
      await ChatStorageService.saveHistory([
        ChatMessage(role: ChatRole.user, content: '内容'),
      ], keep.id);
      final empty2 = await ChatStorageService.createSession(title: '空2');
      await ChatStorageService.setActiveSessionId(empty2.id);

      final removed = await ChatStorageService.deleteEmptySessions();

      expect(removed, 2);
      final remaining = await ChatStorageService.loadSessions();
      expect(remaining.map((s) => s.id).toList(), [keep.id]);
      expect(await ChatStorageService.getActiveSessionId(), keep.id);
      expect(await ChatStorageService.loadHistory(empty1.id), isEmpty);
    },
  );

  test(
    'saving empty history or clearing history removes the empty session',
    () async {
      final session = await ChatStorageService.openEmptySession();
      await ChatStorageService.addMessage(
        ChatMessage(role: ChatRole.user, content: '临时消息'),
        sessionId: session.id,
      );
      expect(await ChatStorageService.loadSessions(), hasLength(1));

      await ChatStorageService.clearHistory();
      expect(await ChatStorageService.loadSessions(), isEmpty);

      await ChatStorageService.saveHistory([], session.id);
      expect(await ChatStorageService.loadSessions(), isEmpty);
    },
  );
}
