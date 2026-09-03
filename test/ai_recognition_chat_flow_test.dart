import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_recognition_chat_bridge.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('pending recognition keeps an exact link to its assistant message',
      () async {
    final handle = await AiRecognitionChatBridge.startText('明天交报告');
    final pendingHandle = AiRecognitionChatBridge.handleFromPending({
      'recognitionChatSessionId': handle.sessionId,
      'recognitionChatMessageId': handle.messageId,
    });

    expect(pendingHandle, isNotNull);
    expect(pendingHandle!.sessionId, handle.sessionId);
    expect(pendingHandle.messageId, handle.messageId);

    final history = await ChatStorageService.loadHistory(handle.sessionId);
    expect(history, hasLength(2));
    expect(history.last.id, handle.messageId);
    expect(
      history.last.recognition?.status,
      ChatRecognitionStatus.processing,
    );
  });

  test('completion updates the original session with suggestions and cost',
      () async {
    final handle = await AiRecognitionChatBridge.startImage('/tmp/todo.png');
    final otherSession = await ChatStorageService.createSession(
      title: '另一段对话',
    );

    await AiRecognitionChatBridge.complete(
      handle,
      todoResults: const [
        {'title': '交报告'},
      ],
      usageSummary: const ChatUsageSummary(
        provider: 'mimo',
        model: 'mimo-v2.5',
        totalTokens: 80,
        costMicros: 456,
      ),
    );

    final originalHistory =
        await ChatStorageService.loadHistory(handle.sessionId);
    final otherHistory = await ChatStorageService.loadHistory(otherSession.id);
    final reply = originalHistory.last;

    expect(originalHistory, hasLength(2));
    expect(otherHistory, isEmpty);
    expect(reply.id, handle.messageId);
    expect(reply.recognition?.status, ChatRecognitionStatus.success);
    expect(reply.recognition?.todoResults, hasLength(1));
    expect(reply.recognition?.suggestions, isNotEmpty);
    expect(reply.usageSummary?.costMicros, 456);

    await AiRecognitionChatBridge.markProcessing(handle);
    final retrying =
        (await ChatStorageService.loadHistory(handle.sessionId)).last;
    expect(retrying.recognition?.status, ChatRecognitionStatus.processing);
    expect(retrying.recognition?.todoResults, isEmpty);
    expect(retrying.recognition?.suggestions, isEmpty);
    expect(retrying.usageSummary, isNull);
  });

  test('failed recognition keeps actionable suggestions in the same message',
      () async {
    final handle = await AiRecognitionChatBridge.startText('模糊内容');
    await AiRecognitionChatBridge.fail(handle, Exception('无法识别'));

    final history = await ChatStorageService.loadHistory(handle.sessionId);
    final reply = history.last;

    expect(reply.id, handle.messageId);
    expect(reply.recognition?.status, ChatRecognitionStatus.failed);
    expect(reply.recognition?.error, '无法识别');
    expect(reply.recognition?.suggestions, contains('重试识别'));
  });
}
