import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/chat_storage_service.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:countdown_todo/models/chat_message.dart';
import 'package:countdown_todo/screens/settings/llm_config_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  // ignore: unnecessary_overrides
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  group('MiMo Token Plan provider', () {
    test('exposes the dedicated OpenAI and Anthropic base URLs', () {
      expect(
        AiChatService.providerBaseUrls[AiChatService.mimoTokenPlanProvider],
        'https://token-plan-cn.xiaomimimo.com/v1',
      );
      expect(
        AiChatService.mimoTokenPlanAnthropicBaseUrl,
        'https://token-plan-cn.xiaomimimo.com/anthropic',
      );
    });

    test('resolves a Token Plan base URL to Chat Completions', () {
      expect(
        AiChatService.resolveChatUrl(
          AiChatService.mimoTokenPlanProvider,
          AiChatService.mimoTokenPlanOpenAiBaseUrl,
        ),
        'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
      );
      expect(
        AiChatService.resolveChatUrl(
          AiChatService.mimoTokenPlanProvider,
          'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
        ),
        'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
      );
    });

    test('infers Token Plan for manually entered endpoints', () {
      expect(
        AiChatService.inferProviderFromApiUrl(
          'https://token-plan-cn.xiaomimimo.com/v1',
        ),
        AiChatService.mimoTokenPlanProvider,
      );
      expect(
        AiChatService.resolveChatUrl(
          '',
          'https://token-plan-cn.xiaomimimo.com/v1',
        ),
        'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
      );
    });
  });

  test('persists the selected vision provider for duplicate model IDs', () {
    final config = LLMConfig(
      provider: AiChatService.mimoTokenPlanProvider,
      visionProvider: AiChatService.mimoTokenPlanProvider,
      apiKey: 'token-plan-key',
      model: 'mimo-v2.5-pro',
      visionModel: 'mimo-v2.5',
      apiUrl: 'https://token-plan-cn.xiaomimimo.com/v1/chat/completions',
    );

    final restored = LLMConfig.fromJson(config.toJson());
    expect(restored.provider, AiChatService.mimoTokenPlanProvider);
    expect(restored.visionProvider, AiChatService.mimoTokenPlanProvider);
    expect(restored.apiUrl, config.apiUrl);
  });

  test('parses OpenAI-compatible token usage', () {
    final usage = AiTokenUsage.fromJson({
      'prompt_tokens': 120,
      'completion_tokens': 34,
      'total_tokens': 154,
    });

    expect(usage, isNotNull);
    expect(usage!.promptTokens, 120);
    expect(usage.completionTokens, 34);
    expect(usage.totalTokens, 154);
  });

  test('parses MiMo usage details and clamps cached input', () {
    final usage = AiTokenUsage.fromJson({
      'prompt_tokens': 1268,
      'completion_tokens': 356,
      'total_tokens': 1624,
      'completion_tokens_details': {'reasoning_tokens': 40},
      'prompt_tokens_details': {
        'cached_tokens': 2000,
        'image_tokens': 500,
        'audio_tokens': 12,
        'video_tokens': 3,
      },
    });

    expect(usage, isNotNull);
    expect(usage!.cachedPromptTokens, 1268);
    expect(usage.imageTokens, 500);
    expect(usage.audioTokens, 12);
    expect(usage.videoTokens, 3);
    expect(usage.reasoningTokens, 40);
  });

  test('parses MiMo ASR duration usage', () {
    final usage = AiTokenUsage.fromJson({
      'prompt_tokens': 46,
      'completion_tokens': 20,
      'total_tokens': 66,
      'prompt_tokens_details': {
        'cached_tokens': 45,
        'audio_tokens': 25,
      },
      'seconds': 4,
    });

    expect(usage, isNotNull);
    expect(usage!.cachedPromptTokens, 45);
    expect(usage.audioTokens, 25);
    expect(usage.audioSeconds, 4);
  });

  test('parses DeepSeek top-level cache usage fields', () {
    final usage = AiTokenUsage.fromJson({
      'prompt_tokens': 1000,
      'completion_tokens': 100,
      'total_tokens': 1100,
      'prompt_cache_hit_tokens': 600,
      'prompt_cache_miss_tokens': 400,
    });

    expect(usage, isNotNull);
    expect(usage!.cachedPromptTokens, 600);
  });

  test('keeps LLM API keys out of SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});

    await LLMService.saveConfig(
      LLMConfig(apiKey: 'global-secret', model: 'test-model'),
    );
    await LLMService.saveProviderApiKey('zhipu', 'provider-secret');
    await LLMService.saveCustomTextModel(
      CustomTextModel(
        id: 'text-model-id',
        name: 'Test model',
        modelId: 'test-model',
        apiUrl: 'https://example.com/v1/chat/completions',
        apiKey: 'custom-secret',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final config = prefs.getString('llm_config')!;
    expect(config, isNot(contains('global-secret')));
    expect(prefs.getString('provider_api_key_zhipu'), isNull);
    expect(prefs.getString('zhipu_api_key'), isNull);
    final storedCustom = prefs.getStringList('custom_text_models')!.single;
    expect(storedCustom, isNot(contains('custom-secret')));

    expect((await LLMService.getConfig())!.apiKey, 'global-secret');
    expect(await LLMService.getProviderApiKey('zhipu'), 'provider-secret');
    expect((await LLMService.getCustomTextModels()).single.apiKey,
        'custom-secret');
  });

  test('stores replies in the session that started the request', () async {
    SharedPreferences.setMockInitialValues({});
    final firstSession = await ChatStorageService.createSession();
    final secondSession = await ChatStorageService.createSession();

    await ChatStorageService.addMessage(
      ChatMessage(role: ChatRole.user, content: 'first request'),
      sessionId: firstSession.id,
    );
    await ChatStorageService.setActiveSessionId(secondSession.id);
    await ChatStorageService.addMessage(
      ChatMessage(role: ChatRole.assistant, content: 'first response'),
      sessionId: firstSession.id,
    );

    expect(await ChatStorageService.loadHistory(firstSession.id), hasLength(2));
    expect(await ChatStorageService.loadHistory(secondSession.id), isEmpty);
  });

  test('cancelling before response headers closes the pending request',
      () async {
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestReceived = Completer<void>();
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (!requestReceived.isCompleted) requestReceived.complete();
        await Future<void>.delayed(const Duration(seconds: 5));
        try {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write('data: [DONE]\\n\\n');
          await request.response.close();
        } catch (_) {
          // The cancellation test deliberately closes the client first.
        }
      });

      try {
        final cancelToken = Completer<void>();
        final response = AiChatService.streamChat(
          apiUrl: 'http://${server.address.address}:${server.port}/v1',
          apiKey: 'test-key',
          model: 'test-model',
          messages: const [
            {'role': 'user', 'content': 'hello'},
          ],
          deepThinking: false,
          cancelToken: cancelToken,
        ).toList();
        await requestReceived.future.timeout(const Duration(seconds: 2));
        cancelToken.complete();
        await expectLater(
          response,
          completes,
        ).timeout(const Duration(seconds: 2));
      } finally {
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient);
  });

  testWidgets('changing the vision model preserves the selected text model',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LLMService.saveConfig(
      LLMConfig(
        apiKey: 'test-key',
        model: 'glm-4.7-flash',
        visionModel: 'glm-4.6v-flash',
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: LLMConfigPage(isEmbedded: true)),
    );
    await tester.pumpAndSettle();

    final modelDropdowns = find.byType(DropdownButton<String>);
    expect(modelDropdowns, findsNWidgets(2));
    expect(find.text('GLM-4.7-Flash'), findsOneWidget);

    await tester.ensureVisible(modelDropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(modelDropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GLM-4.1V-Thinking-Flash').last);
    await tester.pumpAndSettle();

    expect(find.text('GLM-4.7-Flash'), findsOneWidget);
    expect(find.text('GLM-4.1V-Thinking-Flash'), findsOneWidget);
  });
}
