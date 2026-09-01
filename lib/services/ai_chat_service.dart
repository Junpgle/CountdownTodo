import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/finance/services/ai_usage_cost_service.dart';
import '../models/chat_message.dart';
import 'minor_mode_policy.dart';
import 'minor_mode_service.dart';

class AiTokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cachedPromptTokens;
  final int imageTokens;
  final int audioTokens;
  final int videoTokens;
  final int reasoningTokens;
  final int audioSeconds;

  const AiTokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.cachedPromptTokens = 0,
    this.imageTokens = 0,
    this.audioTokens = 0,
    this.videoTokens = 0,
    this.reasoningTokens = 0,
    this.audioSeconds = 0,
  });

  static AiTokenUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final promptTokens =
        _readInt(json['prompt_tokens'] ?? json['input_tokens']);
    final completionTokens =
        _readInt(json['completion_tokens'] ?? json['output_tokens']);
    final totalTokens = _readInt(json['total_tokens']);
    final promptDetails = _asMap(
      json['prompt_tokens_details'] ?? json['input_tokens_details'],
    );
    final completionDetails = _asMap(
      json['completion_tokens_details'] ?? json['output_tokens_details'],
    );
    final cachedPromptTokens = _readInt(
      promptDetails?['cached_tokens'] ?? json['prompt_cache_hit_tokens'],
    );
    final imageTokens = _readInt(promptDetails?['image_tokens']);
    final audioTokens = _readInt(promptDetails?['audio_tokens']);
    final videoTokens = _readInt(promptDetails?['video_tokens']);
    final reasoningTokens = _readInt(completionDetails?['reasoning_tokens']);
    final audioSeconds = _readInt(json['seconds'] ?? json['audio_seconds']);
    if (promptTokens == 0 &&
        completionTokens == 0 &&
        totalTokens == 0 &&
        cachedPromptTokens == 0 &&
        imageTokens == 0 &&
        audioTokens == 0 &&
        videoTokens == 0 &&
        reasoningTokens == 0 &&
        audioSeconds == 0) {
      return null;
    }
    return AiTokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens:
          totalTokens == 0 ? promptTokens + completionTokens : totalTokens,
      cachedPromptTokens:
          cachedPromptTokens > promptTokens ? promptTokens : cachedPromptTokens,
      imageTokens: imageTokens,
      audioTokens: audioTokens,
      videoTokens: videoTokens,
      reasoningTokens: reasoningTokens,
      audioSeconds: audioSeconds,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static int _readInt(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }
}

class AiChatStreamChunk {
  const AiChatStreamChunk({
    this.content = '',
    this.reasoningContent = '',
    this.usage,
    this.usageSummary,
  });

  final String content;
  final String reasoningContent;
  final AiTokenUsage? usage;
  final ChatUsageSummary? usageSummary;
}

class AiChatService {
  static const String defaultApiUrl =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';
  static const String mimoApiBaseUrl = 'https://api.xiaomimimo.com/v1';
  static const String mimoTokenPlanOpenAiBaseUrl =
      'https://token-plan-cn.xiaomimimo.com/v1';
  static const String mimoTokenPlanAnthropicBaseUrl =
      'https://token-plan-cn.xiaomimimo.com/anthropic';
  static const String mimoTokenPlanProvider = 'mimo_token_plan';

  static const Map<String, String> providerBaseUrls = {
    'zhipu': 'https://open.bigmodel.cn/api/paas/v4',
    'mimo': mimoApiBaseUrl,
    mimoTokenPlanProvider: mimoTokenPlanOpenAiBaseUrl,
    'deepseek': 'https://api.deepseek.com',
    'nvidia_nim': 'https://integrate.api.nvidia.com/v1',
  };

  static String trimSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String inferProviderFromApiUrl(String apiUrl) {
    final normalized = apiUrl.toLowerCase();
    if (normalized.contains('token-plan-cn.xiaomimimo.com')) {
      return mimoTokenPlanProvider;
    }
    if (normalized.contains('api.xiaomimimo.com')) return 'mimo';
    if (normalized.contains('integrate.api.nvidia.com')) return 'nvidia_nim';
    if (normalized.contains('api.deepseek.com')) return 'deepseek';
    if (normalized.contains('open.bigmodel.cn')) return 'zhipu';
    return '';
  }

  static String effectiveProvider(String provider, String apiUrl) {
    if (provider.isNotEmpty && provider != 'custom') return provider;
    final inferred = inferProviderFromApiUrl(apiUrl);
    return inferred.isNotEmpty ? inferred : provider;
  }

  static bool usesMimoChatProtocol(String provider, String apiUrl) {
    final effective = effectiveProvider(provider, apiUrl);
    return effective == 'mimo' || effective == mimoTokenPlanProvider;
  }

  static String resolveChatUrl(String provider, String apiUrl) {
    final effective = effectiveProvider(provider, apiUrl);
    if (effective == 'nvidia_nim' || effective == mimoTokenPlanProvider) {
      final base =
          trimSlash(apiUrl.isNotEmpty ? apiUrl : providerBaseUrls[effective]!);
      if (base.endsWith('/chat/completions')) return base;
      return '$base/chat/completions';
    }
    return apiUrl.isEmpty ? defaultApiUrl : apiUrl;
  }

  static String maskKey(String key) {
    if (key.length <= 12) return '***';
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }

  static ChatUsageSummary usageSummaryFromRecord(AiUsageRecord record) {
    return ChatUsageSummary(
      provider: record.provider,
      model: record.model,
      promptTokens: record.promptTokens,
      completionTokens: record.completionTokens,
      totalTokens: record.totalTokens,
      cachedPromptTokens: record.cachedPromptTokens,
      imageTokens: record.imageTokens,
      audioTokens: record.audioTokens,
      videoTokens: record.videoTokens,
      reasoningTokens: record.reasoningTokens,
      audioSeconds: record.audioSeconds,
      imageCount: record.imageCount,
      costMicros: record.costMicros,
      unpricedCalls: record.isPriced ? 0 : 1,
    );
  }

  static List<Map<String, dynamic>> normalizeMessagesForNim(
    List<Map<String, dynamic>> messages,
  ) {
    final systemParts = <String>[];
    final others = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        final content = _contentAsText(msg['content']);
        if (content.trim().isNotEmpty) {
          systemParts.add(content.trim());
        }
      } else {
        others.add(msg);
      }
    }

    // 确保角色严格交替 user/assistant/user/assistant
    final alternated = <Map<String, dynamic>>[];
    String? lastRole;
    for (final msg in others) {
      final role = msg['role'] ?? 'user';
      if (role == lastRole) {
        final last = alternated.removeLast();
        alternated.add({
          'role': role,
          'content': _mergeContent(last['content'], msg['content']),
        });
      } else {
        alternated.add({...msg});
        lastRole = role;
      }
    }

    if (systemParts.isEmpty) return alternated;

    return [
      {
        'role': 'system',
        'content': systemParts.join('\n\n---\n\n'),
      },
      ...alternated,
    ];
  }

  static String _contentAsText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .join('\n');
    }
    return content?.toString() ?? '';
  }

  static Object _mergeContent(Object? first, Object? second) {
    if (first is String && second is String) {
      return '$first\n\n$second';
    }
    final firstParts = first is List
        ? List<dynamic>.from(first)
        : [
            {'type': 'text', 'text': _contentAsText(first)},
          ];
    final secondParts = second is List
        ? List<dynamic>.from(second)
        : [
            {'type': 'text', 'text': _contentAsText(second)},
          ];
    return [
      ...firstParts,
      {'type': 'text', 'text': '\n\n'},
      ...secondParts,
    ];
  }

  static Stream<AiChatStreamChunk> streamChat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required bool deepThinking,
    String provider = 'zhipu',
    double temperature = 0.7,
    int maxTokens = 2000,
    Duration timeout = const Duration(seconds: 60),
    Completer<void>? cancelToken,
    String usageOperation = 'chat',
    int imageCount = 0,
  }) async* {
    await _ensureAiInteractionAllowed();
    final client = http.Client();
    var chunkCount = 0;
    var emittedCount = 0;
    var lastError = '';
    var cancelled = false;
    var usageRecorded = false;

    try {
      if (cancelToken?.isCompleted == true) return;
      if (cancelToken != null) {
        unawaited(cancelToken.future.then((_) {
          cancelled = true;
          // Closing the client also aborts a request that is still waiting for
          // response headers, which a stream-level cancellation check cannot
          // reach.
          client.close();
        }));
      }
      final resolvedUrl = resolveChatUrl(provider, apiUrl);
      final request = http.Request('POST', Uri.parse(resolvedUrl));
      request.headers.addAll(_headers(apiKey));

      final effective = effectiveProvider(provider, apiUrl);
      final bool isNvidiaNim = effective == 'nvidia_nim';
      final bool isMimo = usesMimoChatProtocol(provider, apiUrl);

      final body = <String, dynamic>{
        'model': model,
        'messages': isNvidiaNim ? normalizeMessagesForNim(messages) : messages,
        'temperature': temperature,
        'stream': true,
      };

      if (isNvidiaNim) {
        body['max_tokens'] = maxTokens;
        if (model.startsWith('deepseek-ai/deepseek-v4')) {
          body['reasoning_effort'] = deepThinking ? 'high' : 'none';
        }
      } else {
        body[isMimo ? 'max_completion_tokens' : 'max_tokens'] = maxTokens;
        body['stream_options'] = {'include_usage': true};
        body['thinking'] = {
          'type': deepThinking ? 'enabled' : 'disabled',
        };
      }

      request.body = jsonEncode(body);

      http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(timeout);
      } catch (_) {
        if (cancelled || cancelToken?.isCompleted == true) return;
        rethrow;
      }
      if (cancelled || cancelToken?.isCompleted == true) return;
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception(
          '请求失败: ${response.statusCode}\n'
          'URL: $resolvedUrl\n'
          'Model: $model\n'
          'Body: $errorBody',
        );
      }

      var buffer = '';
      var streamDone = false;
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (cancelToken?.isCompleted == true) {
          cancelled = true;
          break;
        }
        if (streamDone) break;
        buffer += chunk;
        while (true) {
          final newlineIdx = buffer.indexOf('\n');
          if (newlineIdx == -1) break;

          final line = buffer.substring(0, newlineIdx).replaceAll('\r', '');
          buffer = buffer.substring(newlineIdx + 1);
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (!trimmed.startsWith('data:')) {
            lastError = '非SSE行: $trimmed';
            continue;
          }

          final data = trimmed.substring(5).trim();
          if (data == '[DONE]') {
            streamDone = true;
            break;
          }

          chunkCount++;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final error = json['error'] as Map<String, dynamic>?;
            if (error != null) {
              throw Exception('API错误: ${error['message']}');
            }

            final usage = AiTokenUsage.fromJson(json['usage']);
            ChatUsageSummary? usageSummary;
            if (usage != null && !usageRecorded) {
              usageSummary = await _recordUsage(
                provider: effective,
                model: model,
                operation: usageOperation,
                usage: usage,
                imageCount: imageCount,
              );
              usageRecorded = true;
            }

            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) {
              if (usage != null) {
                yield AiChatStreamChunk(
                  usage: usage,
                  usageSummary: usageSummary,
                );
              }
              continue;
            }

            final choice = choices[0] as Map<String, dynamic>;
            final delta = choice['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            final finishReason = choice['finish_reason']?.toString();
            if (finishReason != null &&
                finishReason.isNotEmpty &&
                finishReason != 'null') {
              streamDone = true;
            }

            final content = delta['content'] as String? ?? '';
            final reasoningContent =
                delta['reasoning_content'] as String? ?? '';
            final hasReasoningContent = reasoningContent.isNotEmpty;
            final hasContent = content.isNotEmpty;

            if (hasContent || hasReasoningContent) {
              emittedCount++;
              yield AiChatStreamChunk(
                reasoningContent: reasoningContent,
                content: content,
                usage: usage,
                usageSummary: usageSummary,
              );
            }

            if (streamDone) break;
          } catch (e) {
            lastError = '$e';
          }
        }
      }

      if (!cancelled && (chunkCount == 0 || emittedCount == 0)) {
        throw Exception(
          '未收到有效回复${lastError.isNotEmpty ? ': $lastError' : ''}',
        );
      }
      if (!cancelled && !usageRecorded) {
        await _recordUsage(
          provider: effective,
          model: model,
          operation: usageOperation,
          imageCount: imageCount,
        );
      }
    } finally {
      client.close();
    }
  }

  static Future<String> completeChat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    String provider = 'zhipu',
    double temperature = 0.5,
    int maxTokens = 30,
    Duration timeout = const Duration(seconds: 10),
    String usageOperation = 'title',
  }) async {
    await _ensureAiInteractionAllowed();
    final resolvedUrl = resolveChatUrl(provider, apiUrl);

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
    };

    if (effectiveProvider(provider, apiUrl) == 'nvidia_nim') {
      body['messages'] = normalizeMessagesForNim(messages);
    }
    body[usesMimoChatProtocol(provider, apiUrl)
        ? 'max_completion_tokens'
        : 'max_tokens'] = maxTokens;

    final response = await http
        .post(
          Uri.parse(resolvedUrl),
          headers: _headers(apiKey),
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception(
        '请求失败: ${response.statusCode}\n'
        'URL: $resolvedUrl\n'
        'Model: $model\n'
        'Body: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _recordUsage(
      provider: effectiveProvider(provider, apiUrl),
      model: model,
      operation: usageOperation,
      usage: AiTokenUsage.fromJson(data['usage']),
    );
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    return (message?['content'] as String?) ?? '';
  }

  static Future<ChatUsageSummary?> _recordUsage({
    required String provider,
    required String model,
    required String operation,
    AiTokenUsage? usage,
    int imageCount = 0,
  }) async {
    try {
      final record = await AiUsageCostService.recordUsage(
        provider: provider.isEmpty ? 'custom' : provider,
        model: model,
        operation: operation,
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
        totalTokens: usage?.totalTokens ?? 0,
        cachedPromptTokens: usage?.cachedPromptTokens ?? 0,
        imageTokens: usage?.imageTokens ?? 0,
        audioTokens: usage?.audioTokens ?? 0,
        videoTokens: usage?.videoTokens ?? 0,
        reasoningTokens: usage?.reasoningTokens ?? 0,
        audioSeconds: usage?.audioSeconds ?? 0,
        imageCount: imageCount,
        usageAvailable: usage != null,
      );
      if (record == null) return null;
      return usageSummaryFromRecord(record);
    } catch (_) {
      // Observability must never turn a successful AI reply into an error.
      return null;
    }
  }

  static Future<List<String>> fetchNvidiaNimModels(String apiKey) async {
    return fetchProviderModels(provider: 'nvidia_nim', apiKey: apiKey);
  }

  static Future<List<String>> fetchProviderModels({
    required String provider,
    required String apiKey,
  }) async {
    final authorized = await MinorModeService.instance.authorizeAction(
      MinorModeAction.llmConfiguration,
    );
    if (!authorized) {
      throw const MinorModeAccessException('未成年人模式下，模型列表获取需要家长身份认证');
    }

    final baseUrl = providerBaseUrls[provider];
    if (baseUrl == null) {
      throw Exception('该服务商暂不支持拉取模型列表');
    }

    final response = await http
        .get(
          Uri.parse('${trimSlash(baseUrl)}/models'),
          headers: _headers(apiKey),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        '拉取模型失败: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['data'] as List;

    return list
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  static Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  static Future<void> _ensureAiInteractionAllowed() async {
    final allowed = await MinorModeService.instance.authorizeAiInteraction();
    if (!allowed) {
      throw const MinorModeAccessException('当前未成年人模式年龄段暂不允许使用高级 AI 功能');
    }
  }
}
