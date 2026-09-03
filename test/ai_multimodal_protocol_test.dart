import 'dart:convert';
import 'dart:typed_data';

import 'package:countdown_todo/models/ai_todo_action.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/services/ai_action_parser.dart';
import 'package:countdown_todo/services/ai_multimodal_message_builder.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('chat attachment compatibility', () {
    test('legacy image metadata defaults to the image kind', () {
      final attachment = ChatImageAttachment.fromJson({
        'path': '/tmp/legacy.png',
        'name': 'legacy.png',
        'mimeType': 'image/png',
      });

      expect(attachment.kind, ChatAttachmentKind.image);
      expect(attachment.typeLabel, '图片');
    });

    test('usage and recognition suggestions survive history round-trip', () {
      final message = ChatMessage(
        role: ChatRole.assistant,
        kind: ChatMessageKind.recognition,
        content: '识别完成',
        usageSummary: const ChatUsageSummary(
          provider: 'mimo',
          model: 'mimo-v2.5',
          promptTokens: 120,
          completionTokens: 30,
          totalTokens: 150,
          costMicros: 1234,
        ),
        recognition: ChatRecognitionInfo(
          source: 'audio',
          status: ChatRecognitionStatus.success,
          suggestions: const ['检查时间', '继续分析'],
          startedAt: DateTime(2026, 9, 1, 10),
          completedAt: DateTime(2026, 9, 1, 10, 1),
        ),
      );

      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.usageSummary?.costMicros, 1234);
      expect(restored.usageSummary?.totalTokens, 150);
      expect(restored.recognition?.suggestions, ['检查时间', '继续分析']);
    });

    test('usage aggregation keeps known cost and marks unknown calls', () {
      final combined = ChatUsageSummary.combine(const [
        ChatUsageSummary(
          provider: 'mimo',
          model: 'mimo-v2.5',
          totalTokens: 100,
          costMicros: 900,
        ),
        ChatUsageSummary(
          provider: 'custom',
          model: 'private-model',
          totalTokens: 25,
          unpricedCalls: 1,
        ),
      ]);

      expect(combined, isNotNull);
      expect(combined!.calls, 2);
      expect(combined.totalTokens, 125);
      expect(combined.costMicros, 900);
      expect(combined.unpricedCalls, 1);
      expect(combined.isFullyPriced, isFalse);
    });
  });

  group('multimodal request builder', () {
    test('builds OpenAI-compatible image content parts', () {
      final content = AiMultimodalMessageBuilder.buildContent(
        text: '看看这张图',
        attachment: ChatImageAttachment(
          path: '/tmp/todo.png',
          name: 'todo.png',
          mimeType: 'image/png',
        ),
        bytes: Uint8List.fromList([1, 2, 3]),
        provider: 'zhipu',
      );

      expect(content.first, {'type': 'text', 'text': '看看这张图'});
      expect(content[1]['type'], 'image_url');
      expect(
        (content[1]['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
    });

    test('uses provider-specific audio payload shape', () {
      final attachment = ChatImageAttachment(
        path: '/tmp/note.wav',
        name: 'note.wav',
        mimeType: 'audio/wav',
      );
      final mimo = AiMultimodalMessageBuilder.buildContent(
        text: '',
        attachment: attachment,
        bytes: Uint8List.fromList([1, 2, 3]),
        provider: 'mimo',
      );
      final openAiCompatible = AiMultimodalMessageBuilder.buildContent(
        text: '',
        attachment: attachment,
        bytes: Uint8List.fromList([1, 2, 3]),
        provider: 'custom',
      );

      final mimoAudio = mimo[1]['input_audio'] as Map;
      final standardAudio = openAiCompatible[1]['input_audio'] as Map;
      expect(mimoAudio['data'], startsWith('data:audio/wav;base64,'));
      expect(mimoAudio.containsKey('format'), isFalse);
      expect(standardAudio['data'], isNot(startsWith('data:')));
      expect(standardAudio['format'], 'wav');
    });

    test('builds video, text document, and binary file parts', () {
      final video = AiMultimodalMessageBuilder.buildContent(
        text: '总结视频',
        attachment: ChatImageAttachment(
          path: '/tmp/demo.mp4',
          name: 'demo.mp4',
          mimeType: 'video/mp4',
        ),
        bytes: Uint8List.fromList([1]),
        provider: 'mimo',
      );
      final textDocument = AiMultimodalMessageBuilder.buildContent(
        text: '总结文件',
        attachment: ChatImageAttachment(
          path: '/tmp/notes.md',
          name: 'notes.md',
          mimeType: 'text/markdown',
        ),
        bytes: Uint8List.fromList(utf8.encode('明天交报告')),
        provider: 'custom',
      );
      final binaryDocument = AiMultimodalMessageBuilder.buildContent(
        text: '读取 PDF',
        attachment: ChatImageAttachment(
          path: '/tmp/report.pdf',
          name: 'report.pdf',
          mimeType: 'application/pdf',
        ),
        bytes: Uint8List.fromList([1, 2]),
        provider: 'custom',
      );

      expect(video[1]['type'], 'video_url');
      expect(video[1]['fps'], 2);
      expect(textDocument[1]['type'], 'text');
      expect(textDocument[1]['text'], contains('明天交报告'));
      expect(binaryDocument[1]['type'], 'file');
      expect((binaryDocument[1]['file'] as Map)['filename'], 'report.pdf');
    });
  });

  group('versioned AI protocols and settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('parses Actions v2 envelopes and legacy arrays', () {
      const v2Content = '正文\n'
          '[ACTION_START]'
          '{"protocol":"cdt.actions","version":2,"actions":['
          '{"action":"create_todo","todos":[{"title":"交报告"}]}'
          ']}'
          '[ACTION_END]';
      const legacyContent = '[ACTION_START]'
          '[{"action":"create_todo","title":"买牛奶"}]'
          '[ACTION_END]';

      final v2 = AiActionParser.extractTodoActions(
        v2Content,
        originalText: '交报告',
      );
      final legacy = AiActionParser.extractTodoActions(
        legacyContent,
        originalText: '买牛奶',
      );

      expect(v2, hasLength(1));
      expect(v2.single.type, AiTodoActionType.createTodo);
      expect(v2.single.title, '交报告');
      expect(legacy, hasLength(1));
      expect(legacy.single.title, '买牛奶');
      expect(AiActionParser.cleanActionContent(v2Content), '正文');
    });

    test('persists custom model modalities with image-only legacy fallback',
        () {
      final model = CustomVisionModel(
        id: 'custom-id',
        name: '全模态模型',
        modelId: 'omni-model',
        apiUrl: 'https://example.com/v1/chat/completions',
        apiKey: 'secret',
        modalities: const {'image', 'audio', 'video', 'file'},
      );

      final restored = CustomVisionModel.fromJson(model.toJson());
      final legacy = CustomVisionModel.fromJson({
        'id': 'legacy',
        'name': '旧视觉模型',
        'model_id': 'legacy-model',
        'api_url': 'https://example.com/v1/chat/completions',
        'api_key': '',
      });
      final emptyCapabilities = CustomVisionModel.fromJson({
        'id': 'empty',
        'name': '空能力模型',
        'model_id': 'empty-model',
        'api_url': 'https://example.com/v1/chat/completions',
        'api_key': '',
        'modalities': <String>[],
      });

      expect(restored.modalities, {'image', 'audio', 'video', 'file'});
      expect(legacy.modalities, {'image'});
      expect(emptyCapabilities.modalities, {'image'});
    });

    test('persists assistant context behavior separately from model config',
        () async {
      expect(await ChatStorageService.isSmartContextEnabled(), isTrue);
      expect(await ChatStorageService.shouldShowContextPreview(), isFalse);
      expect(await ChatStorageService.shouldInjectMoreContext(), isFalse);

      await ChatStorageService.setSmartContextEnabled(false);
      await ChatStorageService.setShowContextPreview(true);
      await ChatStorageService.setInjectMoreContext(true);

      expect(await ChatStorageService.isSmartContextEnabled(), isFalse);
      expect(await ChatStorageService.shouldShowContextPreview(), isTrue);
      expect(await ChatStorageService.shouldInjectMoreContext(), isTrue);
    });

    test('reports built-in MiMo multimodal capabilities', () async {
      expect(
        await LLMService.getMultimodalCapabilities('mimo-v2.5'),
        {'image', 'audio', 'video'},
      );
      expect(
        await LLMService.getMultimodalCapabilities('mimo-v2-omni'),
        {'image', 'video'},
      );
      expect(
        await LLMService.getMultimodalCapabilities('legacy-vision'),
        {'image'},
      );
    });
  });
}
