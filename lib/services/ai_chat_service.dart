import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AiChatStreamChunk {
  const AiChatStreamChunk({
    this.content = '',
    this.reasoningContent = '',
  });

  final String content;
  final String reasoningContent;
}

class AiChatService {
  static const String defaultApiUrl =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  static const Map<String, String> providerBaseUrls = {
    'nvidia_nim': 'https://integrate.api.nvidia.com/v1',
  };

  static String trimSlash(String value) {
    return value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
  }

  static String resolveChatUrl(String provider, String apiUrl) {
    if (provider == 'nvidia_nim') {
      final base = trimSlash(
          apiUrl.isNotEmpty ? apiUrl : providerBaseUrls['nvidia_nim']!);
      return '$base/chat/completions';
    }
    return apiUrl.isEmpty ? defaultApiUrl : apiUrl;
  }

  static String maskKey(String key) {
    if (key.length <= 12) return '***';
    return '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
  }

  static List<Map<String, String>> normalizeMessagesForNim(
    List<Map<String, String>> messages,
  ) {
    final systemParts = <String>[];
    final others = <Map<String, String>>[];

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        final content = msg['content'];
        if (content != null && content.trim().isNotEmpty) {
          systemParts.add(content.trim());
        }
      } else {
        others.add(msg);
      }
    }

    if (systemParts.isEmpty) return messages;

    return [
      {
        'role': 'system',
        'content': systemParts.join('\n\n---\n\n'),
      },
      ...others,
    ];
  }

  static Stream<AiChatStreamChunk> streamChat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required bool deepThinking,
    String provider = 'zhipu',
    double temperature = 0.7,
    int maxTokens = 2000,
    Duration timeout = const Duration(seconds: 60),
    Completer<void>? cancelToken,
  }) async* {
    final client = http.Client();
    var chunkCount = 0;
    var emittedCount = 0;
    var lastError = '';
    var cancelled = false;

    try {
      final resolvedUrl = resolveChatUrl(provider, apiUrl);
      final request = http.Request('POST', Uri.parse(resolvedUrl));
      request.headers.addAll(_headers(apiKey));

      final bool isNvidiaNim = provider == 'nvidia_nim';

      final body = <String, dynamic>{
        'model': model,
        'messages': isNvidiaNim
            ? normalizeMessagesForNim(messages)
            : messages,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': true,
      };

      if (isNvidiaNim) {
        if (model.startsWith('deepseek-ai/deepseek-v4')) {
          body['reasoning_effort'] = deepThinking ? 'high' : 'none';
        }
      } else {
        body['stream_options'] = {'include_usage': true};
        body['thinking'] = {
          'type': deepThinking ? 'enabled' : 'disabled',
        };
      }

      request.body = jsonEncode(body);

      final response = await client.send(request).timeout(timeout);
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

            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;

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
    } finally {
      client.close();
    }
  }

  static Future<String> completeChat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    String provider = 'zhipu',
    double temperature = 0.5,
    int maxTokens = 30,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final resolvedUrl = resolveChatUrl(provider, apiUrl);

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };

    if (provider == 'nvidia_nim') {
      body['messages'] = normalizeMessagesForNim(messages);
    }

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
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    return (message?['content'] as String?) ?? '';
  }

  static Future<List<String>> fetchNvidiaNimModels(String apiKey) async {
    final response = await http
        .get(
          Uri.parse('${providerBaseUrls['nvidia_nim']!}/models'),
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
}
