import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LLMConfig {
  final String apiKey;
  final String model;
  final String visionModel;
  final String apiUrl;
  final String textPrompt;
  final String visionPrompt;

  LLMConfig({
    required this.apiKey,
    required this.model,
    String? visionModel,
    String? apiUrl,
    String? textPrompt,
    String? visionPrompt,
  })  : visionModel = visionModel ?? 'glm-4.6v-flash',
        apiUrl =
            apiUrl ?? 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
        textPrompt = textPrompt ?? defaultTextPrompt,
        visionPrompt = visionPrompt ?? defaultVisionPrompt;

  static const String defaultTextPrompt =
      '''你是一个专业的日程规划助手，擅长将自然语言准确转换为结构化的待办事项JSON。

【当前基准时间】
{now}
（注意：所有"今天"、"下周一"等时间，必须基于此基准推算）

【字段提取规则（严格执行）】

===== 特殊场景：取餐码/取件码 =====
极其重要！优先检测以下场景：

1. 品牌识别（尽量精确）：
   - 快餐类：KFC、肯德基、麦当劳、汉堡王、德克士、华莱士、塔斯汀
   - 奶茶类：古茗、茶百道、蜜雪冰城、沪上阿姨、书亦烧仙草、CoCo、一点点、喜茶、奈雪的茶、霸王茶姬、卡旺卡、甜啦啦
   - 咖啡类：瑞幸、星巴克、库迪、Manner
   - 外餐类：海底捞、太二酸菜鱼、外婆家、西贝、必胜客
   - 快递类：顺丰、京东快递、菜鸟、中通、圆通、韵达、申通、极兔、德邦

2. 识别规则：
   - 如果文本包含取餐码、取件码、餐号、订单号、取单号等关键词
   - 或者包含上述品牌名+数字/字母组合
   - 则按以下规则处理：

3. 处理方式：
   - title: 使用【品牌名+取餐/取件】格式
     * 识别到具体品牌：如"肯德基取餐"、"顺丰取件"
     * 未识别具体品牌：外卖用"外卖取餐"，快递用"快递取件"，奶茶用"奶茶取餐"
   - remark: 取餐码/取件码的值（纯数字或字母数字组合）
   - isAllDay: true（默认全天事件）
   - startTime: 当天"00:00"
   - endTime: 当天"23:59"

4. 示例：
   输入: "KFC取餐码1234"
   输出: {"title":"KFC取餐","remark":"取餐码: 1234","isAllDay":true,"startTime":"[今天] 00:00","endTime":"[今天] 23:59","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

   输入: "顺丰快递到了取件码8866"
   输出: {"title":"顺丰取件","remark":"取件码: 8866","isAllDay":true,"startTime":"[今天] 00:00","endTime":"[今天] 23:59","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

   输入: "茶百道做好了A056"
   输出: {"title":"茶百道取餐","remark":"取餐码: A056","isAllDay":true,"startTime":"[今天] 00:00","endTime":"[今天] 23:59","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

===== 通用待办规则 =====
如果不是取餐/取件场景，则按以下规则：

1. title: 核心动作/事件。必须极度精简！必须去除口语化前缀（如"提醒我"、"帮我记一下"、"我要"）、去除时间、去除地点（地点必须剥离到remark中）。
2. remark: 提取地点、人物、携带物品等补充信息。极其重要：一旦提取了地点（如"在图书馆"），必须将地点词从title中彻底删除！若无补充信息设为null。
3. isAllDay: 若用户没说具体几点（如"明天去学习"），设为true。
4. startTime: 格式"YYYY-MM-DD HH:mm"。全天事件设为当天的"00:00"。
5. endTime: 格式"YYYY-MM-DD HH:mm"。默认startTime加1小时。
6. recurrence: 识别重复周期。
   - 极其重要：只有当文本包含"每天"、"每周"、"每个[周几]"、"每月"、"每年"、"每隔X天"、"工作日"等表示【持续循环】的词时才设定。
   - 特别注意：类似"下周一"、"这周五"、"下个月1号"是指【特定的某一天】，不是重复事件，recurrence 必须设为 "none"。
7. customIntervalDays: 仅限customDays时使用，否则为null。
8. recurrenceEndDate: 循环截止日期，若无则null。
9. reminderMinutes: 提前多少分钟提醒。
   - 识别用户提到的"提前5分钟"、"提前半小时"、"提前1小时"、"准时提醒"等。
   - 默认为 5。如果是"准时提醒"设为 0。

【输出格式】
如果输入包含多个待办，请返回JSON数组；如果是单个待办，也请返回JSON数组（只有一个元素）。
例如：[{"title":"xxx","remark":"xxx","isAllDay":false,"startTime":"YYYY-MM-DD HH:mm","endTime":"YYYY-MM-DD HH:mm","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}]

【重要约束】
必须且只能返回纯JSON格式数组，绝对不要包含任何Markdown标记（如```json），确保能够直接被程序反序列化。

待解析文本: "{input}"''';

  static const String defaultVisionPrompt = '''你是一个专业的日程规划助手，请从图片中提取待办事项信息。

【当前基准时间】
{now}

【任务】
仔细观察图片，识别其中的日程、待办、会议、提醒等信息，并转换为结构化JSON。

===== 特殊场景：取餐码/取件码 =====
极其重要！优先检测截图中的取餐码/取件码：

1. 品牌识别（尽量精确）：
   - 快餐类：KFC、肯德基、麦当劳、汉堡王、德克士、华莱士、塔斯汀
   - 奶茶类：古茗、茶百道、蜜雪冰城、沪上阿姨、书亦烧仙草、CoCo、一点点、喜茶、奈雪的茶、霸王茶姬、卡旺卡、甜啦啦
   - 咖啡类：瑞幸、星巴克、库迪、Manner
   - 外餐类：海底捞、太二酸菜鱼、外婆家、西贝、必胜客
   - 快递类：顺丰、京东快递、菜鸟、中通、圆通、韵达、申通、极兔、德邦

2. 识别规则：
   - 图片中有取餐码、取件码、餐号、订单号等
   - 或者包含上述品牌 logo/名称+数字组合
   - 则按以下规则处理：

3. 处理方式：
   - title: 使用【品牌名+取餐/取件】格式
     * 识别到具体品牌：如"肯德基取餐"、"顺丰取件"
     * 未识别具体品牌：外卖用"外卖取餐"，快递用"快递取件"，奶茶用"奶茶取餐"
   - remark: 取餐码/取件码的值
   - isAllDay: true（默认全天事件）
   - startTime: 当天"00:00"
   - endTime: 当天"23:59"

===== 通用待办规则 =====
1. title: 核心事件名称（如"开会"、"交作业"、"体检"）
2. remark: 地点、备注等补充信息，没有则null
3. isAllDay: 没有具体时间则为true
4. startTime: 格式"YYYY-MM-DD HH:mm"，全天事件设为"00:00"
5. endTime: 格式"YYYY-MM-DD HH:mm"，默认加1小时
6. recurrence: 重复规则（none/daily/weekly/monthly/yearly/weekdays/customDays）
7. customIntervalDays: 仅customDays时使用
8. recurrenceEndDate: 循环截止日期
9. reminderMinutes: 提前多少分钟提醒（默认 5）

【输出格式】
如果图片中有多个待办，请返回JSON数组；如果是单个待办，也请返回JSON数组（只有一个元素）。
例如：[{"title":"xxx","remark":"xxx","isAllDay":false,"startTime":"YYYY-MM-DD HH:mm","endTime":"YYYY-MM-DD HH:mm","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}]

必须且只能返回纯JSON数组格式，不要包含Markdown标记。''';

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        'model': model,
        'vision_model': visionModel,
        'api_url': apiUrl,
        'text_prompt': textPrompt,
        'vision_prompt': visionPrompt,
      };

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      apiKey: json['api_key'] ?? '',
      model: json['model'] ?? 'glm-4.7-flash',
      visionModel: json['vision_model'],
      apiUrl: json['api_url'],
      textPrompt: json['text_prompt'],
      visionPrompt: json['vision_prompt'],
    );
  }

  bool get isConfigured => apiKey.isNotEmpty && model.isNotEmpty;
}

class CustomTextModel {
  final String id;
  final String name;
  final String modelId;
  final String apiUrl;
  final String apiKey;

  CustomTextModel({
    required this.id,
    required this.name,
    required this.modelId,
    required this.apiUrl,
    required this.apiKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'model_id': modelId,
        'api_url': apiUrl,
        'api_key': apiKey,
      };

  factory CustomTextModel.fromJson(Map<String, dynamic> json) {
    return CustomTextModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      modelId: json['model_id'] ?? '',
      apiUrl: json['api_url'] ?? '',
      apiKey: json['api_key'] ?? '',
    );
  }
}

class CustomVisionModel {
  final String id;
  final String name;
  final String modelId;
  final String apiUrl;
  final String apiKey;

  CustomVisionModel({
    required this.id,
    required this.name,
    required this.modelId,
    required this.apiUrl,
    required this.apiKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'model_id': modelId,
        'api_url': apiUrl,
        'api_key': apiKey,
      };

  factory CustomVisionModel.fromJson(Map<String, dynamic> json) {
    return CustomVisionModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      modelId: json['model_id'] ?? '',
      apiUrl: json['api_url'] ?? '',
      apiKey: json['api_key'] ?? '',
    );
  }
}

class LLMService {
  static const String _configKey = 'llm_config';
  static const String _zhipuApiKeyKey = 'zhipu_api_key';
  static const String _customTextModelsKey = 'custom_text_models';
  static const String _customVisionModelsKey = 'custom_vision_models';

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

  static Future<String> getZhipuApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_zhipuApiKeyKey) ?? '';
  }

  static Future<void> saveZhipuApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_zhipuApiKeyKey, apiKey);
  }

  static Future<List<CustomTextModel>> getCustomTextModels() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customTextModelsKey) ?? [];
    return list
        .map((e) =>
            CustomTextModel.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveCustomTextModel(CustomTextModel model) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getCustomTextModels();
    final idx = models.indexWhere((m) => m.id == model.id);
    if (idx >= 0) {
      models[idx] = model;
    } else {
      models.add(model);
    }
    await prefs.setStringList(_customTextModelsKey,
        models.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> deleteCustomTextModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getCustomTextModels();
    models.removeWhere((m) => m.id == id);
    await prefs.setStringList(_customTextModelsKey,
        models.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<List<CustomVisionModel>> getCustomVisionModels() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customVisionModelsKey) ?? [];
    return list
        .map((e) =>
            CustomVisionModel.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveCustomVisionModel(CustomVisionModel model) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getCustomVisionModels();
    final idx = models.indexWhere((m) => m.id == model.id);
    if (idx >= 0) {
      models[idx] = model;
    } else {
      models.add(model);
    }
    await prefs.setStringList(_customVisionModelsKey,
        models.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> deleteCustomVisionModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getCustomVisionModels();
    models.removeWhere((m) => m.id == id);
    await prefs.setStringList(_customVisionModelsKey,
        models.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<String> testConnection() async {
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    final body = jsonEncode({
      'model': config.model,
      'messages': [
        {'role': 'user', 'content': '请回复"连接成功"'}
      ],
      'temperature': 0.1,
      'max_tokens': 50,
    });

    print('========== 测试连接 ==========');
    print('API: ${config.apiUrl}');
    print('Model: ${config.model}');
    print('==============================');

    final response = await http
        .post(
          Uri.parse(config.apiUrl),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      print('完整响应: ${response.body}');
      throw Exception(
          '返回数据格式异常: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) {
      print('完整响应: ${response.body}');
      throw Exception(
          '返回数据格式异常: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
    }
    final content = (message['content'] as String?) ?? '';
    final reasoning = (message['reasoning_content'] as String?) ?? '';
    final fullContent =
        reasoning.isNotEmpty ? '$reasoning\n\n$content' : content;
    print('测试响应: $fullContent');
    return fullContent;
  }

  static Future<List<Map<String, dynamic>>> parseTodoWithLLM(
      String input) async {
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置，请先在设置中配置API');
    }

    final now = DateTime.now();
    final nowStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final prompt = config.textPrompt
        .replaceAll('{now}', nowStr)
        .replaceAll('{input}', input);

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

    print('========== LLM 文本请求 ==========');
    print('API: ${config.apiUrl}');
    print('Model: ${config.model}');
    print('Prompt:\n$prompt');
    print('==================================');

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

    final message = choices[0]['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';
    final reasoning = (message['reasoning_content'] as String?) ?? '';
    final fullContent =
        reasoning.isNotEmpty ? '$reasoning\n\n$content' : content;

    print('========== LLM 文本响应 ==========');
    print('原始返回:\n$fullContent');
    print('==================================');

    final results = _extractJsonList(fullContent);

    print('解析结果: $results');
    print('==================================');

    return results;
  }

  static Future<List<Map<String, dynamic>>> parseTodoFromImage(
      String imagePath) async {
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置，请先在设置中配置API');
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('图片文件不存在: $imagePath');
    }

    // 检查文件大小
    final fileSize = await file.length();
    print('图片大小: ${(fileSize / 1024).toStringAsFixed(1)}KB');

    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('图片太大，请使用小于10MB的图片');
    }

    // 读取并编码图片
    final bytes = await file.readAsBytes();

    // 使用 Future.microtask 避免阻塞主线程
    final base64Image = await Future.microtask(() => base64Encode(bytes));

    String mimeType = 'image/jpeg';
    final ext = imagePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        mimeType = 'image/png';
        break;
      case 'gif':
        mimeType = 'image/gif';
        break;
      case 'webp':
        mimeType = 'image/webp';
        break;
    }

    final now = DateTime.now();
    final nowStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final prompt = config.visionPrompt.replaceAll('{now}', nowStr);

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    final imageUrl = 'data:$mimeType;base64,$base64Image';
    print('Base64 长度: ${imageUrl.length}');

    final body = jsonEncode({
      'model': config.visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': imageUrl}
            }
          ]
        }
      ],
      'temperature': 0.1,
    });

    // 清理不再需要的变量
    bytes.length; // 保持引用但不使用
    base64Image.length;

    print('========== LLM 图片识别请求 ==========');
    print('API: ${config.apiUrl}');
    print('Model: ${config.visionModel}');
    print('Image: $imagePath (${(fileSize / 1024).toStringAsFixed(1)}KB)');
    print('Body 大小: ${(body.length / 1024).toStringAsFixed(1)}KB');
    print('====================================');

    final response = await http
        .post(
          Uri.parse(config.apiUrl),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      print('LLM 请求失败: ${response.statusCode} - ${response.body}');
      throw Exception('API调用失败: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }

    final message = choices[0]['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';
    final reasoning = (message['reasoning_content'] as String?) ?? '';
    final fullContent =
        reasoning.isNotEmpty ? '$reasoning\n\n$content' : content;

    print('========== LLM 图片识别响应 ==========');
    print('原始返回:\n$fullContent');
    print('=====================================');

    final results = _extractJsonList(fullContent);

    print('解析结果: $results');
    print('====================================');

    return results;
  }

  static List<Map<String, dynamic>> _extractJsonList(String content) {
    final trimmed = content.trim();

    // 尝试直接解析整个内容为 JSON 数组
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final list = jsonDecode(trimmed) as List;
        return list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    // 尝试解析为单个 JSON 对象，然后包装成数组
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final obj = jsonDecode(trimmed) as Map<String, dynamic>;
        return [obj];
      } catch (_) {}
    }

    // 尝试提取多个 JSON 对象（每行一个 JSON）
    final lines = trimmed.split('\n');
    final results = <Map<String, dynamic>>[];
    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) continue;
      if (l.startsWith('{') && l.endsWith('}')) {
        try {
          final obj = jsonDecode(l) as Map<String, dynamic>;
          results.add(obj);
        } catch (_) {}
      }
    }
    if (results.isNotEmpty) return results;

    // 尝试使用正则提取所有 JSON 对象
    final matches = RegExp(r'\{[^{}]*\}').allMatches(trimmed);
    for (final match in matches) {
      try {
        final obj = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        if (obj.containsKey('title')) {
          results.add(obj);
        }
      } catch (_) {}
    }
    if (results.isNotEmpty) return results;

    throw Exception('无法从返回内容中提取JSON: $content');
  }
}
