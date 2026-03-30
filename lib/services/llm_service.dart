import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LLMConfig {
  final String apiKey;
  final String model;
  final String apiUrl;

  LLMConfig({
    required this.apiKey,
    required this.model,
    String? apiUrl,
  }) : apiUrl =
            apiUrl ?? 'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        'model': model,
        'api_url': apiUrl,
      };

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      apiKey: json['api_key'] ?? '',
      model: json['model'] ?? '',
      apiUrl: json['api_url'],
    );
  }

  bool get isConfigured => apiKey.isNotEmpty && model.isNotEmpty;
}

class LLMService {
  static const String _configKey = 'llm_config';

  static Future<LLMConfig?> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString(_configKey);
    if (configStr == null || configStr.isEmpty) return null;
    try {
      final json = jsonDecode(configStr) as Map<String, dynamic>;
      return LLMConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(LLMConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  static Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
  }

  static Future<Map<String, dynamic>> parseTodoWithLLM(String input) async {
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置，请先在设置中配置API');
    }

    final now = DateTime.now();
    final nowStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final prompt = '''请解析以下待办事项文本，提取结构化信息并以JSON格式返回。

待办文本: "$input"

当前时间: $nowStr

请返回以下格式的JSON（所有字段都必须包含，没有的字段设为null）:
{
  "title": "待办事项标题（去除时间、地点等信息后的核心内容）",
  "remark": "备注或地点信息",
  "isAllDay": false,
  "startTime": "YYYY-MM-DD HH:mm格式的开始时间，如果没有具体时间则为null",
  "endTime": "YYYY-MM-DD HH:mm格式的结束时间，如果没有则为null",
  "recurrence": "none/daily/weekly/monthly/yearly/weekdays/customDays之一",
  "customIntervalDays": null,
  "recurrenceEndDate": null
}

注意：
1. 时间解析请基于当前时间进行计算
2. 如果文本中有"每天"则recurrence设为"daily"，"每周"设为"weekly"，以此类推
3. 只返回JSON，不要有其他内容''';

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    final body = jsonEncode({
      'model': config.model,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.1,
    });

    print('========== LLM 请求 ==========');
    print('API: ${config.apiUrl}');
    print('Model: ${config.model}');
    print('Prompt:\n$prompt');
    print('Body: $body');
    print('==============================');

    final response = await http
        .post(
          Uri.parse(config.apiUrl),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      print('LLM 请求失败: ${response.statusCode} - ${response.body}');
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }

    final content = choices[0]['message']['content'] as String;

    print('========== LLM 响应 ==========');
    print('原始返回:\n$content');
    print('==============================');

    final jsonStr = _extractJson(content);
    final result = jsonDecode(jsonStr) as Map<String, dynamic>;

    print('解析结果: $result');
    print('==============================');

    return result;
  }

  static String _extractJson(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(trimmed);
    if (match != null) {
      return match.group(0)!;
    }
    throw Exception('无法从返回内容中提取JSON: $content');
  }
}
