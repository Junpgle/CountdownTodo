import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../features/finance/services/ai_usage_cost_service.dart';
import '../models/chat_message.dart';
import 'ai_chat_service.dart';
import 'llm_service.dart';
import 'minor_mode_policy.dart';
import 'minor_mode_service.dart';

class MimoAsrResult {
  const MimoAsrResult({required this.text, this.usageSummary});

  final String text;
  final ChatUsageSummary? usageSummary;
}

/// MiMo ASR uses chat/completions with a single WAV input, not audio/transcriptions.
class MimoAsrService {
  MimoAsrService({
    http.Client? client,
    Future<bool> Function()? authorize,
    Future<ChatUsageSummary?> Function(AiTokenUsage?)? recordUsage,
  }) : _client = client ?? http.Client(),
       _authorize =
           authorize ?? MinorModeService.instance.authorizeAiInteraction,
       _recordUsage = recordUsage ?? _saveUsage;

  static const model = 'mimo-v2.5-asr';
  static const maxAudioBytes = 7 * 1024 * 1024;
  final http.Client _client;
  final Future<bool> Function() _authorize;
  final Future<ChatUsageSummary?> Function(AiTokenUsage?) _recordUsage;

  /// Token Plan credentials are separate and must not be sent to the metered API.
  static String selectApiKey({
    required String savedMimoKey,
    required String provider,
    required String apiUrl,
    required String apiKey,
  }) {
    if (savedMimoKey.trim().isNotEmpty) return savedMimoKey.trim();
    final host = Uri.tryParse(apiUrl)?.host.toLowerCase() ?? '';
    return AiChatService.effectiveProvider(provider, apiUrl) == 'mimo' &&
            (apiUrl.isEmpty || host == 'api.xiaomimimo.com')
        ? apiKey.trim()
        : '';
  }

  static Future<String> resolveApiKey({Map<String, String>? chatConfig}) async {
    final saved = await LLMService.getProviderApiKey('mimo');
    final chatKey = selectApiKey(
      savedMimoKey: saved,
      provider: chatConfig?['provider'] ?? '',
      apiUrl: chatConfig?['apiUrl'] ?? '',
      apiKey: chatConfig?['apiKey'] ?? '',
    );
    if (chatKey.isNotEmpty) return chatKey;
    final config = await LLMService.getConfig();
    return selectApiKey(
      savedMimoKey: saved,
      provider: config?.provider ?? '',
      apiUrl: config?.apiUrl ?? '',
      apiKey: config?.apiKey ?? '',
    );
  }

  Future<String> transcribe({
    required Uint8List wavBytes,
    required String apiKey,
  }) async =>
      (await transcribeWithUsage(wavBytes: wavBytes, apiKey: apiKey)).text;

  Future<MimoAsrResult> transcribeWithUsage({
    required Uint8List wavBytes,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const FormatException('请先配置小米 MiMo API Key');
    }
    if (wavBytes.length <= 44) throw const FormatException('没有录到声音，请重新录音');
    if (wavBytes.length > maxAudioBytes) {
      throw const FormatException('录音过长，请缩短后重试');
    }
    if (!await _authorize()) {
      throw const MinorModeAccessException('当前未成年人模式年龄段暂不允许使用高级 AI 功能');
    }
    final response = await _client
        .post(
          Uri.parse('${AiChatService.mimoApiBaseUrl}/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'api-key': apiKey.trim(),
          },
          body: jsonEncode({
            'model': model,
            'stream': false,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'input_audio',
                    'input_audio': {
                      'data': 'data:audio/wav;base64,${base64Encode(wavBytes)}',
                      'format': 'wav',
                    },
                  },
                ],
              },
            ],
            'asr_options': {'language': 'auto'},
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final reason = switch (response.statusCode) {
        401 || 403 => 'MiMo API Key 无效或没有语音识别权限',
        402 => 'MiMo 余额不足',
        429 => 'MiMo 请求过于频繁或额度不足，请稍后重试',
        _ => 'MiMo 语音识别失败（HTTP ${response.statusCode}），请稍后重试',
      };
      throw Exception(reason);
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('MiMo 返回了无效的识别结果');
    }
    ChatUsageSummary? usageSummary;
    try {
      usageSummary = await _recordUsage(AiTokenUsage.fromJson(data['usage']));
    } catch (_) {
      // Accounting failure must not lose a successful transcription.
    }
    final choices = data['choices'];
    final message =
        choices is List && choices.isNotEmpty && choices.first is Map
        ? choices.first['message']
        : null;
    final content = message is Map ? message['content'] : null;
    if (content is! String) throw const FormatException('MiMo 返回了无效的识别结果');
    final text = content.trim();
    if (text.isEmpty) throw const FormatException('没有识别到说话内容，请重新录音');
    return MimoAsrResult(text: text, usageSummary: usageSummary);
  }

  void dispose() => _client.close();

  static Future<ChatUsageSummary?> _saveUsage(AiTokenUsage? usage) async {
    final record = await AiUsageCostService.recordUsage(
      provider: 'mimo',
      model: model,
      operation: 'voice_asr',
      promptTokens: usage?.promptTokens ?? 0,
      completionTokens: usage?.completionTokens ?? 0,
      totalTokens: usage?.totalTokens ?? 0,
      cachedPromptTokens: usage?.cachedPromptTokens ?? 0,
      audioTokens: usage?.audioTokens ?? 0,
      audioSeconds: usage?.audioSeconds ?? 0,
      usageAvailable: usage != null,
    );
    return record == null ? null : AiChatService.usageSummaryFromRecord(record);
  }
}
