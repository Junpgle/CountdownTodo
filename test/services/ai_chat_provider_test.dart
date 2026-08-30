import 'package:countdown_todo/services/ai_chat_service.dart';
import 'package:countdown_todo/services/llm_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
