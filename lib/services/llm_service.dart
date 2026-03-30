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

    final prompt = '''你是一个专业的日程规划助手，擅长将自然语言准确转换为结构化的待办事项JSON。

【当前基准时间】
$nowStr
（注意：所有“今天”、“下周一”等时间，必须基于此基准推算）

【字段提取规则（严格执行）】
1. title: 核心动作/事件。必须极度精简！必须去除口语化前缀（如“提醒我”、“帮我记一下”、“我要”）、去除时间、去除地点（地点必须剥离到remark中）。
2. remark: 提取地点、人物、携带物品等补充信息。极其重要：一旦提取了地点（如“在图书馆”），必须将地点词从title中彻底删除！若无补充信息设为null。
3. isAllDay: 若用户没说具体几点（如“明天去学习”），设为true。
4. startTime: 格式"YYYY-MM-DD HH:mm"。全天事件设为当天的"00:00"。
5. endTime: 格式"YYYY-MM-DD HH:mm"。默认startTime加1小时。
6. recurrence: 识别重复周期。
   - 极其重要：只有当文本包含“每天”、“每周”、“每个[周几]”、“每月”、“每年”、“每隔X天”、“工作日”等表示【持续循环】的词时才设定。
   - 特别注意：类似“下周一”、“这周五”、“下个月1号”是指【特定的某一天】，不是重复事件，recurrence 必须设为 "none"。
7. customIntervalDays: 仅限customDays时使用，否则为null。
8. recurrenceEndDate: 循环截止日期，若无则null。

【输出示例（对比学习）】
输入: "下周一提醒我要在图书馆学习"
输出: {"title":"学习","remark":"图书馆","isAllDay":true,"startTime":"2026-04-06 00:00","endTime":"2026-04-06 01:00","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

输入: "帮我记一下明天早上8点和王总在302会议室开会"
输出: {"title":"和王总开会","remark":"302会议室","isAllDay":false,"startTime":"[明天日期] 08:00","endTime":"[明天日期] 09:00","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

输入: "以后每个工作日早上9点打卡"
输出: {"title":"打卡","remark":null,"isAllDay":false,"startTime":"[最近下一个工作日] 09:00","endTime":"[最近下一个工作日] 10:00","recurrence":"weekdays","customIntervalDays":null,"recurrenceEndDate":null}

【重要约束】
必须且只能返回纯JSON格式对象，绝对不要包含任何Markdown标记（如```json），确保能够直接被程序反序列化。

待解析文本: "$input"''';

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
