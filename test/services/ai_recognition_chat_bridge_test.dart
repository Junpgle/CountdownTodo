import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/ai_recognition_chat_bridge.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'chat image and recognition metadata survive local history round-trip',
    () {
      final message = ChatMessage(
        role: ChatRole.user,
        kind: ChatMessageKind.conversation,
        content: '请识别这张图片',
        attachment: ChatImageAttachment(
          path: '/tmp/todo.png',
          name: 'todo.png',
          mimeType: 'image/png',
          sizeBytes: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.attachment?.path, '/tmp/todo.png');
      expect(restored.attachment?.mimeType, 'image/png');
      expect(restored.attachment?.bytes, isNull);

      final recognition = ChatMessage(
        role: ChatRole.assistant,
        kind: ChatMessageKind.recognition,
        content: 'AI识别中…',
        recognition: ChatRecognitionInfo(
          source: 'text',
          status: ChatRecognitionStatus.processing,
          inputText: '明天交报告',
          startedAt: DateTime(2026, 9, 1, 10),
        ),
      );
      final restoredRecognition = ChatMessage.fromJson(recognition.toJson());
      expect(restoredRecognition.recognition?.source, 'text');
      expect(
        restoredRecognition.recognition?.status,
        ChatRecognitionStatus.processing,
      );
    },
  );

  test('recognition bridge updates the same assistant event', () async {
    final handle = await AiRecognitionChatBridge.startText('明天交报告');
    var history = await ChatStorageService.loadHistory(handle.sessionId);
    expect(history, hasLength(2));
    expect(history.last.recognition?.status, ChatRecognitionStatus.processing);

    await AiRecognitionChatBridge.complete(
      handle,
      todoResults: [
        {'title': '交报告'},
      ],
    );
    history = await ChatStorageService.loadHistory(handle.sessionId);
    expect(history, hasLength(2));
    expect(history.last.id, handle.messageId);
    expect(history.last.recognition?.todoResults, hasLength(1));
    expect(history.last.recognition?.status, ChatRecognitionStatus.success);
  });

  test('NIM normalization keeps multimodal content when merging roles', () {
    final messages = AiChatService.normalizeMessagesForNim([
      {'role': 'system', 'content': 'system'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '识别图片'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,x'},
          },
        ],
      },
      {'role': 'user', 'content': '补充说明'},
    ]);

    expect(messages.first['role'], 'system');
    expect(messages[1]['content'], isA<List<dynamic>>());
    expect(
      (messages[1]['content'] as List).any(
        (part) => part is Map && part['type'] == 'image_url',
      ),
      isTrue,
    );
  });

  test(
    'recognition bridge streams live model output and preserves rawContent',
    () async {
      final handle = await AiRecognitionChatBridge.startImage('/tmp/demo.png');
      var notifications = 0;
      void listener() => notifications++;
      AiRecognitionChatBridge.streamChanges.addListener(listener);
      addTearDown(
        () => AiRecognitionChatBridge.streamChanges.removeListener(listener),
      );

      final formatted = AiRecognitionChatBridge.formatModelStream(
        reasoningContent: '正在读取图片中的取餐码',
        content: '[{"title":"肯德基取餐"}]',
      );
      AiRecognitionChatBridge.updateStream(handle, formatted);

      expect(notifications, 1);
      expect(
        AiRecognitionChatBridge.liveContentFor(handle.messageId),
        contains('正在读取图片中的取餐码'),
      );
      expect(
        AiRecognitionChatBridge.liveContentFor(handle.messageId),
        contains('肯德基取餐'),
      );

      await AiRecognitionChatBridge.complete(
        handle,
        todoResults: const [
          {'title': '肯德基取餐'},
        ],
      );

      expect(AiRecognitionChatBridge.liveContentFor(handle.messageId), isNull);
      final history = await ChatStorageService.loadHistory(handle.sessionId);
      expect(history.last.rawContent, contains('肯德基取餐'));
    },
  );
}
