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

  static Stream<AiChatStreamChunk> streamChat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required bool deepThinking,
    double temperature = 0.7,
    int maxTokens = 2000,
    Duration timeout = const Duration(seconds: 60),
  }) async* {
    final client = http.Client();
    var chunkCount = 0;
    var emittedCount = 0;
    var lastError = '';

    try {
      final request = http.Request('POST', Uri.parse(_resolveApiUrl(apiUrl)));
      request.headers.addAll(_headers(apiKey));
      request.body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': true,
        'stream_options': {'include_usage': true},
        'thinking': {
          'type': deepThinking ? 'enabled' : 'disabled',
        },
      });

      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode}');
      }

      var buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
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
          if (data == '[DONE]') continue;

          chunkCount++;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final error = json['error'] as Map<String, dynamic>?;
            if (error != null) {
              throw Exception('API错误: ${error['message']}');
            }

            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;

            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            final streamChunk = AiChatStreamChunk(
              reasoningContent: delta['reasoning_content'] as String? ?? '',
              content: delta['content'] as String? ?? '',
            );
            if (streamChunk.content.isNotEmpty ||
                streamChunk.reasoningContent.isNotEmpty) {
              emittedCount++;
              yield streamChunk;
            }
          } catch (e) {
            lastError = '$e';
          }
        }
      }

      if (chunkCount == 0 || emittedCount == 0) {
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
    double temperature = 0.5,
    int maxTokens = 30,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final response = await http
        .post(
          Uri.parse(_resolveApiUrl(apiUrl)),
          headers: _headers(apiKey),
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    return (message?['content'] as String?) ?? '';
  }

  static Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  static String _resolveApiUrl(String apiUrl) =>
      apiUrl.isEmpty ? defaultApiUrl : apiUrl;
}
