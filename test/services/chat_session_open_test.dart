import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('first opening creates an active empty session', () async {
    final session = await ChatStorageService.openEmptySession();

    expect(await ChatStorageService.getActiveSessionId(), session.id);
    expect(await ChatStorageService.loadHistory(session.id), isEmpty);
    expect(await ChatStorageService.loadSessions(), hasLength(1));
  });

  test('reopening without chatting reuses the same empty session', () async {
    final first = await ChatStorageService.openEmptySession();
    final second = await ChatStorageService.openEmptySession();
    final third = await ChatStorageService.openEmptySession();

    expect(second.id, first.id);
    expect(third.id, first.id);
    expect(await ChatStorageService.loadSessions(), hasLength(1));
  });

  test('concurrent openings share one empty session', () async {
    final opened = await Future.wait(
      List.generate(12, (_) => ChatStorageService.openEmptySession()),
    );

    expect(opened.map((session) => session.id).toSet(), hasLength(1));
    expect(await ChatStorageService.loadSessions(), hasLength(1));
    expect(await ChatStorageService.getActiveSessionId(), opened.first.id);
  });

  test(
    'reopening after chatting starts empty and preserves old history',
    () async {
      final previous = await ChatStorageService.createSession();
      final history = [
        ChatMessage(role: ChatRole.user, content: '帮我规划今天'),
        ChatMessage(role: ChatRole.assistant, content: '先完成报告'),
      ];
      await ChatStorageService.saveHistory(history, previous.id);

      final opened = await ChatStorageService.openEmptySession();

      expect(opened.id, isNot(previous.id));
      expect(await ChatStorageService.getActiveSessionId(), opened.id);
      expect(await ChatStorageService.loadHistory(opened.id), isEmpty);
      expect(
        (await ChatStorageService.loadHistory(previous.id)).map((m) => m.id),
        history.map((m) => m.id),
      );
      expect(await ChatStorageService.loadSessions(), hasLength(2));

      final reopened = await ChatStorageService.openEmptySession();
      expect(reopened.id, opened.id);
      expect(await ChatStorageService.loadSessions(), hasLength(2));
    },
  );

  test('a user message without a reply still requires a new session', () async {
    final previous = await ChatStorageService.createSession();
    await ChatStorageService.saveHistory([
      ChatMessage(role: ChatRole.user, content: '请求未完成'),
    ], previous.id);

    final opened = await ChatStorageService.openEmptySession();

    expect(opened.id, isNot(previous.id));
    expect(await ChatStorageService.loadHistory(opened.id), isEmpty);
    expect(await ChatStorageService.loadHistory(previous.id), hasLength(1));
  });

  test(
    'reuses the last selected empty session even if it is not first',
    () async {
      final empty = await ChatStorageService.createSession();
      final other = await ChatStorageService.createSession();
      await ChatStorageService.saveHistory([
        ChatMessage(role: ChatRole.assistant, content: '识别结果'),
      ], other.id);
      await ChatStorageService.setActiveSessionId(empty.id);

      final opened = await ChatStorageService.openEmptySession();

      expect(opened.id, empty.id);
      expect(await ChatStorageService.loadHistory(opened.id), isEmpty);
      expect(await ChatStorageService.loadSessions(), hasLength(2));
    },
  );

  test(
    'a stale active id cannot restore another session with history',
    () async {
      final previous = await ChatStorageService.createSession();
      await ChatStorageService.saveHistory([
        ChatMessage(role: ChatRole.user, content: '历史消息'),
      ], previous.id);
      await ChatStorageService.setActiveSessionId('missing-session');

      final opened = await ChatStorageService.openEmptySession();

      expect(opened.id, isNot(previous.id));
      expect(await ChatStorageService.getActiveSessionId(), opened.id);
      expect(await ChatStorageService.loadHistory(opened.id), isEmpty);
      expect(await ChatStorageService.loadHistory(previous.id), hasLength(1));
    },
  );
}
