import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/image_input_reader.dart';
import 'ai_chat_service.dart';
import 'minor_mode_policy.dart';
import 'minor_mode_service.dart';
import 'secure_storage_service.dart';
import '../features/finance/services/ai_usage_cost_service.dart';

class LLMConfig {
  final String provider;
  final String? visionProvider;
  final String apiKey;
  final String model;
  final String visionModel;
  final String apiUrl;
  final String textPrompt;
  final String visionPrompt;

  LLMConfig({
    this.provider = 'zhipu',
    this.visionProvider,
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
      '''你是一个专业的事项识别助手，负责把自然语言准确区分为待办、固定日程或规划块，并输出结构化JSON。

【当前基准时间】
{now}
（注意：所有"今天"、"下周一"等时间，必须基于此基准推算）

【字段提取规则（严格执行）】

===== 事项类型边界（最高优先级） =====
每条结果都必须输出 itemKind：
- todo：用户需要完成的结果，例如交作业、写报告、缴费、复习、取件；可以未安排、只有完成日期或有截止时刻。
- fixedSchedule：时间主要由学校、组织、预约方、交通或票务决定的占用，例如课程、考试、会议、面试、预约、航班、车次、演出；它不是可勾选完成的待办。
- planBlock：用户自行安排且可以移动的执行时段，例如“今晚8点到9点复习英语”；它必须表达明确执行区间并关联一个要做的结果。
- needsConfirmation：只有时间段但无法判断是外部约束还是自主执行时段。
不要因为一句话带时间就一律输出待办；也不要把待办的截止点解释成一小时日程。

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
   - 这是需要用户完成领取动作的待办，不是固定日程
   - 普通文本没有可靠日期时：isAllDay=false，startTime=null，endTime=null，不得擅自设为今天
   - 文本明确领取日期但没有具体时刻时：isAllDay=true，startTime为当天"00:00"，endTime为当天"23:59"
   - 文本明确最晚领取时刻时：isAllDay=false，startTime为目标日期"00:00"，endTime为最晚领取时刻

4. 示例：
   输入: "KFC取餐码1234"
   输出: {"itemKind":"todo","title":"KFC取餐","remark":"取餐码: 1234","isAllDay":false,"startTime":null,"endTime":null,"timeMode":"unscheduled","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

   输入: "顺丰快递到了取件码8866"
   输出: {"itemKind":"todo","title":"顺丰取件","remark":"取件码: 8866","isAllDay":false,"startTime":null,"endTime":null,"timeMode":"unscheduled","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

   输入: "茶百道做好了A056"
   输出: {"itemKind":"todo","title":"茶百道取餐","remark":"取餐码: A056","isAllDay":false,"startTime":null,"endTime":null,"timeMode":"unscheduled","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null}

===== 通用事项规则 =====
如果不是取餐/取件场景，则按以下规则：

1. itemKind: 必须按上面的边界输出 todo/fixedSchedule/planBlock/needsConfirmation。
2. title: 核心动作/事件。必须极度精简！必须去除口语化前缀（如"提醒我"、"帮我记一下"、"我要"）、去除时间和地点。
3. location: fixedSchedule 的地点单独写入此字段；没有则为null。todo和planBlock的地点继续放在remark中并把location设为null。
4. remark: 提取人物、携带物品等补充信息；todo和planBlock也在这里保留地点。地点词必须从title中彻底删除，若无补充信息设为null。
5. 时间字段：todo 未安排时起止均为null；日期待办为当天00:00到23:59；截止待办为当天00:00到截止点。fixedSchedule 时间待定时用日期的00:00到23:59并设isAllDay=true；只有开始时刻时startTime为原时刻且endTime=null；明确区间才同时填写。planBlock必须有明确开始和结束。
6. timeMode: 未安排为"unscheduled"；仅日期为"dateOnly"；待办单一截止时刻为"deadline"；明确开始—结束区间为"range"。固定日程只有开始时刻也使用"range"且endTime为null。
7. recurrence: 识别重复周期。
   - 极其重要：只有当文本包含"每天"、"每周"、"每个[周几]"、"每月"、"每年"、"每隔X天"、"工作日"等表示【持续循环】的词时才设定。
   - 特别注意：类似"下周一"、"这周五"、"下个月1号"是指【特定的某一天】，不是重复事件，recurrence 必须设为 "none"。
   - 循环待办和循环日程都会生成多个可独立寻址的期次；这里只描述系列规则，不要自行生成多条JSON。
   - 用户只说"每天/每周..."而没说首次发生日期时，保留recurrence，但起止时间设为null，让用户确认第一期；不得默认今天。
8. customIntervalDays: 仅限customDays时使用，否则为null。
9. recurrenceEndDate: 重复结束日期，若无则null。
10. reminderMinutes: 提前多少分钟提醒。
   - 识别用户提到的"提前5分钟"、"提前半小时"、"提前1小时"、"准时提醒"等。
   - todo和planBlock默认5，fixedSchedule默认15。如果是"准时提醒"设为0。

【输出格式】
如果输入包含多个事项，请返回JSON数组；如果是单个事项，也请返回JSON数组（只有一个元素）。
例如：[{"itemKind":"fixedSchedule","title":"项目会议","location":"第一会议室","remark":null,"isAllDay":false,"startTime":"YYYY-MM-DD HH:mm","endTime":"YYYY-MM-DD HH:mm","timeMode":"range","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null,"reminderMinutes":15}]

【重要约束】
必须且只能返回纯JSON格式数组，绝对不要包含任何Markdown标记（如```json），确保能够直接被程序反序列化。

待解析文本: "{input}"''';

  static const String defaultVisionPrompt =
      '''你是一个专业的事项识别助手，请从图片中区分并提取待办、固定日程和规划块。

【当前基准时间】
{now}

【任务】
仔细观察图片，识别其中的日程、待办、会议、提醒等信息，并转换为结构化JSON。每条必须输出itemKind：todo表示要完成的结果；fixedSchedule表示外部决定时间的课程、考试、会议、预约、交通或演出；planBlock表示用户可调整的执行区间；无法判断的时间段用needsConfirmation。

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
   - 这是需要用户完成领取动作的待办，不是固定日程
   - 截图能可靠确认是当前已出餐/已到站通知且没有期限时：isAllDay=true，startTime为当天"00:00"，endTime为当天"23:59"
   - 截图包含明确领取期限时，按期限设置日期待办或具体截止时刻
   - 截图日期来源不可靠时，不得猜测今天，时间字段设为null

===== 通用事项规则 =====
1. itemKind: 必须为todo/fixedSchedule/planBlock/needsConfirmation之一。会议、考试、课程、预约等不能静默输出为todo
2. title: 核心事件名称（如"开会"、"交作业"、"体检"），去除时间和地点
3. location: fixedSchedule的地点单独写入，没有则null；todo和planBlock设为null
4. remark: 人物、携带物品等补充信息；todo和planBlock也在这里保留地点，没有则null
5. 时间字段：todo沿用未安排/日期/截止语义；fixedSchedule时间待定时保留日期并设isAllDay=true，只有开始时刻时startTime为原时刻且endTime=null，明确区间才同时填写；planBlock必须有明确起止
6. timeMode: 未安排为unscheduled；仅日期为dateOnly；待办单一截止时刻为deadline；明确区间及固定日程开始时刻为range
7. recurrence: 重复规则（none/daily/weekly/monthly/yearly/weekdays/customDays）
   - 循环只输出一条系列起始事项，不要为未来每一期重复输出JSON
   - 图片未提供可靠首次日期时保留recurrence，但起止时间设为null并等待用户确认；不得猜测今天
8. customIntervalDays: 仅customDays时使用
9. recurrenceEndDate: 重复结束日期
10. reminderMinutes: 提前多少分钟提醒（todo和planBlock默认5，fixedSchedule默认15）

【输出格式】
如果图片中有多个事项，请返回JSON数组；如果是单个事项，也请返回JSON数组（只有一个元素）。
例如：[{"itemKind":"fixedSchedule","title":"项目会议","location":"第一会议室","remark":null,"isAllDay":false,"startTime":"YYYY-MM-DD HH:mm","endTime":"YYYY-MM-DD HH:mm","timeMode":"range","recurrence":"none","customIntervalDays":null,"recurrenceEndDate":null,"reminderMinutes":15}]

  必须且只能返回纯JSON数组格式，不要包含Markdown标记。''';

  /// 外部分享图片使用的第二条识别通道。它只负责账单，和待办/取餐码
  /// 识别并行执行，避免一张支付截图里同时出现取餐码时互相覆盖结果。
  static const String defaultFinanceVisionPrompt =
      '''你是一个严格的账单识别器，请从图片中提取所有有可靠金额依据的消费、收入或退款记录。

【当前基准日期】
{now}

【识别边界】
1. 只识别账单、支付成功/退款凭证、消费明细、收款记录、订单金额等有明确金额的交易。
2. 每一笔独立交易都要单独输出，不能因为同一张图还包含取餐码、取件码、快递信息或待办信息而省略账单。
3. 取餐码/取件码本身不是账单，不要把码值当金额；但图片中同时有账单和取餐码时，只输出账单，另一条通道会负责取餐码。
4. 金额以人民币“元”的数字输出，不要输出千分位符；金额必须大于0。
5. type只能是expense（支出）、income（收入）或refund（退款）。无法确认交易方向时，默认expense，但必须有可靠金额。
6. 日期能从凭证可靠读出时使用yyyy-MM-dd，否则使用{now}中的日期。不要凭猜测补日期。
7. category尽量使用餐饮、交通、购物、居住、学习、娱乐、健康、社交、订阅、工资、零花钱、奖金、退款或其他；无法判断时为其他。
8. merchant填写商户或交易对象，paymentMethod填写微信、支付宝、银行卡、现金、信用卡或其他；没有可靠内容时为null。

【输出格式】
必须且只能返回纯JSON数组，不要包含Markdown。每个对象必须包含：
{"itemKind":"finance","type":"expense|income|refund","amount":28.50,"category":"餐饮","merchant":"商户名","date":"yyyy-MM-dd","paymentMethod":"微信","note":"可选说明"}
如果没有可靠账单，返回[]。''';

  /// 追加到默认或自定义识别提示词末尾的强制语义护栏。
  /// 用户仍可定制提取风格，但不能覆盖当前数据模型的类型与时间边界。
  static const String itemSemanticGuardrailPrompt = '''
【当前事项协议护栏（优先于前文，必须遵守）】
每条JSON必须增加itemKind，值只能是todo、fixedSchedule、planBlock或needsConfirmation。
todo是要完成的结果；fixedSchedule是课程、考试、会议、预约、交通等外部决定时间的占用；planBlock是用户可调整的执行区间；无法判断的时间段用needsConfirmation。
不得把固定日程静默输出为todo，也不得把待办截止点自动扩展成一小时区间。
todo无日期时保持未安排；fixedSchedule时间待定时保留日期且不捏造时刻，只有开始时刻时不得补结束时间；planBlock必须有明确起止。
重复不等于习惯。没有首次发生日期时保留循环规则但时间留空，交给用户确认，禁止默认今天。
fixedSchedule地点使用location字段；todo和planBlock地点放在remark。默认提醒：todo/planBlock为5分钟，fixedSchedule为15分钟。''';

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'vision_provider': visionProvider,
        'api_key': apiKey,
        'model': model,
        'vision_model': visionModel,
        'api_url': apiUrl,
        'text_prompt': textPrompt,
        'vision_prompt': visionPrompt,
      };

  factory LLMConfig.fromJson(Map<String, dynamic> json) {
    return LLMConfig(
      provider: json['provider']?.toString() ?? 'zhipu',
      visionProvider: json['vision_provider']?.toString(),
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
  static const String _providerApiKeyPrefix = 'provider_api_key_';
  static const String _customTextModelsKey = 'custom_text_models';
  static const String _customVisionModelsKey = 'custom_vision_models';
  static const String _nvidiaNimModelsKey = 'nvidia_nim_models';
  static const String _providerModelsPrefix = 'provider_models_';
  static const String _configApiKeyStorageKey = 'llm_config_api_key';
  static const String _providerApiKeyStoragePrefix = 'llm_provider_api_key_';
  static const String _customTextApiKeyStoragePrefix =
      'llm_custom_text_api_key_';
  static const String _customVisionApiKeyStoragePrefix =
      'llm_custom_vision_api_key_';

  static String _providerApiKeyStorageKey(String provider) =>
      '$_providerApiKeyStoragePrefix$provider';

  static String _customTextApiKeyStorageKey(String id) =>
      '$_customTextApiKeyStoragePrefix$id';

  static String _customVisionApiKeyStorageKey(String id) =>
      '$_customVisionApiKeyStoragePrefix$id';

  static Map<String, dynamic> _withoutApiKey(Map<String, dynamic> json) {
    final copy = Map<String, dynamic>.from(json);
    copy.remove('api_key');
    return copy;
  }

  static const Map<String, String> _visionModelProviders = {
    'glm-4.6v-flash': 'zhipu',
    'glm-4.1v-thinking-flash': 'zhipu',
    'glm-4v-flash': 'zhipu',
    'glm-4.6v': 'zhipu',
    'glm-ocr': 'zhipu',
    'autoglm-phone': 'zhipu',
    'glm-4.1v-thinking-flashx': 'zhipu',
    'mimo-v2.5': 'mimo',
    'mimo-v2-omni': 'mimo',
  };

  static const Map<String, String> _providerApiUrls = {
    'zhipu': 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    'mimo': '${AiChatService.mimoApiBaseUrl}/chat/completions',
    AiChatService.mimoTokenPlanProvider:
        '${AiChatService.mimoTokenPlanOpenAiBaseUrl}/chat/completions',
    'nvidia_nim': 'https://integrate.api.nvidia.com/v1/chat/completions',
    'deepseek': 'https://api.deepseek.com/chat/completions',
  };

  static const Map<String, String> _modelPrefixProviders = {
    'glm-': 'zhipu',
    'mimo-': 'mimo',
    'nvidia/': 'nvidia_nim',
    'meta/': 'nvidia_nim',
    'meta-llama/': 'nvidia_nim',
    'mistralai/': 'nvidia_nim',
    'deepseek-ai/': 'nvidia_nim',
    'google/': 'nvidia_nim',
    'qwen/': 'nvidia_nim',
    'microsoft/': 'nvidia_nim',
  };

  static String _detectProvider(String modelId) {
    final exact = _visionModelProviders[modelId];
    if (exact != null) return exact;
    for (final entry in _modelPrefixProviders.entries) {
      if (modelId.startsWith(entry.key)) return entry.value;
    }
    return '';
  }

  static Future<String> _findProviderInStoredModels(String modelId) async {
    for (final provider in _providerApiUrls.keys) {
      final models = await getProviderModels(provider);
      if (models.contains(modelId)) return provider;
    }
    return '';
  }

  static Future<({String url, String key})> resolveVisionEndpoint(
      String visionModel,
      {String? provider}) async {
    final requestedProvider = provider?.trim() ?? '';

    // The same model ID can be available from both MiMo API products. When
    // the caller has persisted the selected provider, it must win over the
    // model-prefix fallback below.
    if (requestedProvider == 'custom') {
      final customModels = await getCustomVisionModels();
      final custom = customModels
          .where((m) => m.modelId == visionModel || m.id == visionModel)
          .firstOrNull;
      if (custom != null && custom.apiUrl.isNotEmpty) {
        return (url: custom.apiUrl, key: custom.apiKey);
      }
    }

    if (requestedProvider.isNotEmpty &&
        requestedProvider != 'custom' &&
        _providerApiUrls.containsKey(requestedProvider)) {
      final url = _providerApiUrls[requestedProvider]!;
      final key = await getProviderApiKey(requestedProvider);
      return (url: url, key: key);
    }

    // 1. 前缀/精确匹配
    final detectedProvider = _detectProvider(visionModel);
    if (detectedProvider.isNotEmpty) {
      final url = _providerApiUrls[detectedProvider]!;
      final key = await getProviderApiKey(detectedProvider);
      return (url: url, key: key);
    }
    // 2. 自定义视觉模型
    final customModels = await getCustomVisionModels();
    final custom = customModels
        .where((m) => m.modelId == visionModel || m.id == visionModel)
        .firstOrNull;
    if (custom != null && custom.apiUrl.isNotEmpty) {
      return (url: custom.apiUrl, key: custom.apiKey);
    }
    // 3. 遍历已拉取的 provider 模型列表
    final storedProvider = await _findProviderInStoredModels(visionModel);
    if (storedProvider.isNotEmpty) {
      final url = _providerApiUrls[storedProvider]!;
      final key = await getProviderApiKey(storedProvider);
      return (url: url, key: key);
    }
    return (url: '', key: '');
  }

  static Future<LLMConfig?> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString(_configKey);
    if (configStr == null || configStr.isEmpty) return null;
    try {
      final json = Map<String, dynamic>.from(
        jsonDecode(configStr) as Map<String, dynamic>,
      );
      final legacyApiKey = json['api_key']?.toString() ?? '';
      final secureApiKey =
          await SecureStorageService.read(_configApiKeyStorageKey);
      final apiKey = secureApiKey != null && secureApiKey.isNotEmpty
          ? secureApiKey
          : legacyApiKey;
      if (legacyApiKey.isNotEmpty) {
        final migrated = secureApiKey != null && secureApiKey.isNotEmpty
            ? true
            : await SecureStorageService.write(
                _configApiKeyStorageKey,
                legacyApiKey,
              );
        if (migrated) {
          await prefs.setString(
            _configKey,
            jsonEncode(_withoutApiKey(json)),
          );
        }
      }
      json['api_key'] = apiKey;
      return LLMConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveConfig(LLMConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    if (config.apiKey.isEmpty) {
      await SecureStorageService.delete(_configApiKeyStorageKey);
    } else {
      await SecureStorageService.write(_configApiKeyStorageKey, config.apiKey);
    }
    await prefs.setString(
      _configKey,
      jsonEncode(_withoutApiKey(config.toJson())),
    );
  }

  static Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
    await SecureStorageService.delete(_configApiKeyStorageKey);
    await prefs.remove(_nvidiaNimModelsKey);
    for (final provider in [
      'zhipu',
      'mimo',
      AiChatService.mimoTokenPlanProvider,
      'deepseek',
      'nvidia_nim',
    ]) {
      await prefs.remove('$_providerModelsPrefix$provider');
    }
  }

  static Future<String> getZhipuApiKey() async {
    return getProviderApiKey('zhipu');
  }

  static Future<void> saveZhipuApiKey(String apiKey) async {
    await saveProviderApiKey('zhipu', apiKey);
  }

  static Future<String> getProviderApiKey(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    final secureKey = _providerApiKeyStorageKey(provider);
    final secureApiKey = await SecureStorageService.read(secureKey);
    final providerPreferenceKey = '$_providerApiKeyPrefix$provider';
    final legacyApiKey = prefs.getString(providerPreferenceKey) ??
        (provider == 'zhipu' ? prefs.getString(_zhipuApiKeyKey) : null) ??
        '';
    if (secureApiKey != null && secureApiKey.isNotEmpty) {
      if (legacyApiKey.isNotEmpty) {
        await prefs.remove(providerPreferenceKey);
        if (provider == 'zhipu') await prefs.remove(_zhipuApiKeyKey);
      }
      return secureApiKey;
    }
    if (legacyApiKey.isEmpty) return '';

    final migrated = await SecureStorageService.write(secureKey, legacyApiKey);
    if (migrated) {
      await prefs.remove(providerPreferenceKey);
      if (provider == 'zhipu') await prefs.remove(_zhipuApiKeyKey);
    }
    return legacyApiKey;
  }

  static Future<void> saveProviderApiKey(String provider, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    final secureKey = _providerApiKeyStorageKey(provider);
    if (apiKey.isEmpty) {
      await SecureStorageService.delete(secureKey);
    } else {
      await SecureStorageService.write(secureKey, apiKey);
    }
    await prefs.remove('$_providerApiKeyPrefix$provider');
    if (provider == 'zhipu') await prefs.remove(_zhipuApiKeyKey);
  }

  static Future<List<String>> getNvidiaNimModels() async {
    return getProviderModels('nvidia_nim');
  }

  static Future<void> saveNvidiaNimModels(List<String> models) async {
    await saveProviderModels('nvidia_nim', models);
  }

  static Future<List<String>> getProviderModels(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    final newKeyModels = prefs.getStringList('$_providerModelsPrefix$provider');
    if (newKeyModels != null) return newKeyModels;
    if (provider == 'nvidia_nim') {
      return prefs.getStringList(_nvidiaNimModelsKey) ?? [];
    }
    return [];
  }

  static Future<void> saveProviderModels(
      String provider, List<String> models) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = models
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    await prefs.setStringList('$_providerModelsPrefix$provider', normalized);
    if (provider == 'nvidia_nim') {
      await prefs.setStringList(_nvidiaNimModelsKey, normalized);
    }
  }

  static Future<List<CustomTextModel>> getCustomTextModels() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customTextModelsKey) ?? [];
    var needsSanitizing = false;
    final models = <CustomTextModel>[];
    for (final entry in list) {
      final model = CustomTextModel.fromJson(
        jsonDecode(entry) as Map<String, dynamic>,
      );
      final secureApiKey = await SecureStorageService.read(
        _customTextApiKeyStorageKey(model.id),
      );
      final apiKey = secureApiKey ?? model.apiKey;
      if (model.apiKey.isNotEmpty) {
        final migrated = secureApiKey != null ||
            await SecureStorageService.write(
              _customTextApiKeyStorageKey(model.id),
              model.apiKey,
            );
        needsSanitizing = needsSanitizing || migrated;
      }
      models.add(CustomTextModel(
        id: model.id,
        name: model.name,
        modelId: model.modelId,
        apiUrl: model.apiUrl,
        apiKey: apiKey,
      ));
    }
    if (needsSanitizing) {
      await prefs.setStringList(
        _customTextModelsKey,
        models
            .map((model) => jsonEncode(_withoutApiKey(model.toJson())))
            .toList(),
      );
    }
    return models;
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
    if (model.apiKey.isEmpty) {
      await SecureStorageService.delete(_customTextApiKeyStorageKey(model.id));
    } else {
      await SecureStorageService.write(
        _customTextApiKeyStorageKey(model.id),
        model.apiKey,
      );
    }
    await prefs.setStringList(
      _customTextModelsKey,
      models.map((e) => jsonEncode(_withoutApiKey(e.toJson()))).toList(),
    );
  }

  static Future<void> deleteCustomTextModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getCustomTextModels();
    models.removeWhere((m) => m.id == id);
    await SecureStorageService.delete(_customTextApiKeyStorageKey(id));
    await prefs.setStringList(
      _customTextModelsKey,
      models.map((e) => jsonEncode(_withoutApiKey(e.toJson()))).toList(),
    );
  }

  static Future<List<CustomVisionModel>> getCustomVisionModels() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customVisionModelsKey) ?? [];
    var needsSanitizing = false;
    final models = <CustomVisionModel>[];
    for (final entry in list) {
      final model = CustomVisionModel.fromJson(
        jsonDecode(entry) as Map<String, dynamic>,
      );
      final secureApiKey = await SecureStorageService.read(
        _customVisionApiKeyStorageKey(model.id),
      );
      final apiKey = secureApiKey ?? model.apiKey;
      if (model.apiKey.isNotEmpty) {
        final migrated = secureApiKey != null ||
            await SecureStorageService.write(
              _customVisionApiKeyStorageKey(model.id),
              model.apiKey,
            );
        needsSanitizing = needsSanitizing || migrated;
      }
      models.add(CustomVisionModel(
        id: model.id,
        name: model.name,
        modelId: model.modelId,
        apiUrl: model.apiUrl,
        apiKey: apiKey,
      ));
    }
    if (needsSanitizing) {
      await prefs.setStringList(
        _customVisionModelsKey,
        models
            .map((model) => jsonEncode(_withoutApiKey(model.toJson())))
            .toList(),
      );
    }
    return models;
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
    if (model.apiKey.isEmpty) {
      await SecureStorageService.delete(
          _customVisionApiKeyStorageKey(model.id));
    } else {
      await SecureStorageService.write(
        _customVisionApiKeyStorageKey(model.id),
        model.apiKey,
      );
    }
    await prefs.setStringList(
      _customVisionModelsKey,
      models.map((e) => jsonEncode(_withoutApiKey(e.toJson()))).toList(),
    );
  }

  static Future<void> deleteCustomVisionModel(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getCustomVisionModels();
    models.removeWhere((m) => m.id == id);
    await SecureStorageService.delete(_customVisionApiKeyStorageKey(id));
    await prefs.setStringList(
      _customVisionModelsKey,
      models.map((e) => jsonEncode(_withoutApiKey(e.toJson()))).toList(),
    );
  }

  static Future<String> testConnection() async {
    await _ensureAiInteractionAllowed();
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    final requestBody = <String, dynamic>{
      'model': config.model,
      'messages': [
        {'role': 'user', 'content': '请回复"连接成功"'}
      ],
      'temperature': 0.1,
    };
    requestBody[
        AiChatService.usesMimoChatProtocol(config.provider, config.apiUrl)
            ? 'max_completion_tokens'
            : 'max_tokens'] = 50;
    final body = jsonEncode(requestBody);

    // print('========== 测试连接 ==========');
    // print('API: ${config.apiUrl}');
    // print('Model: ${config.model}');
    // print('==============================');

    final response = await http
        .post(
          Uri.parse(
              AiChatService.resolveChatUrl(config.provider, config.apiUrl)),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final usage = AiTokenUsage.fromJson(data['usage']);
    try {
      final usageProvider =
          AiChatService.effectiveProvider(config.provider, config.apiUrl);
      await AiUsageCostService.recordUsage(
        provider: usageProvider.isEmpty ? 'custom' : usageProvider,
        model: config.model,
        operation: 'connection_test',
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
        totalTokens: usage?.totalTokens ?? 0,
        cachedPromptTokens: usage?.cachedPromptTokens ?? 0,
        imageTokens: usage?.imageTokens ?? 0,
        audioTokens: usage?.audioTokens ?? 0,
        videoTokens: usage?.videoTokens ?? 0,
        reasoningTokens: usage?.reasoningTokens ?? 0,
        audioSeconds: usage?.audioSeconds ?? 0,
        usageAvailable: usage != null,
      );
    } catch (_) {
      // Cost tracking must not invalidate a successful text recognition.
    }
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      // print('完整响应: ${response.body}');
      throw Exception(
          '返回数据格式异常: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) {
      // print('完整响应: ${response.body}');
      throw Exception(
          '返回数据格式异常: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
    }
    final content = (message['content'] as String?) ?? '';
    final reasoning = (message['reasoning_content'] as String?) ?? '';
    final fullContent =
        reasoning.isNotEmpty ? '$reasoning\n\n$content' : content;
    // print('测试响应: $fullContent');
    return fullContent;
  }

  static Future<List<Map<String, dynamic>>> parseTodoWithLLM(
      String input) async {
    await _ensureAiInteractionAllowed();
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置，请先在设置中配置API');
    }

    final now = DateTime.now();
    final nowStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final resolvedPrompt = config.textPrompt
        .replaceAll('{now}', nowStr)
        .replaceAll('{input}', input);
    final prompt =
        '$resolvedPrompt\n\n${LLMConfig.itemSemanticGuardrailPrompt}';

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

    // print('========== LLM 文本请求 ==========');
    // print('API: ${config.apiUrl}');
    // print('Model: ${config.model}');
    // print('Prompt:\n$prompt');
    // print('==================================');

    final response = await http
        .post(
          Uri.parse(
              AiChatService.resolveChatUrl(config.provider, config.apiUrl)),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      // print('LLM 请求失败: ${response.statusCode} - ${response.body}');
      throw Exception('API调用失败: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final usage = AiTokenUsage.fromJson(data['usage']);
    try {
      final usageProvider =
          AiChatService.effectiveProvider(config.provider, config.apiUrl);
      await AiUsageCostService.recordUsage(
        provider: usageProvider.isEmpty ? 'custom' : usageProvider,
        model: config.model,
        operation: 'todo_text',
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
        totalTokens: usage?.totalTokens ?? 0,
        cachedPromptTokens: usage?.cachedPromptTokens ?? 0,
        imageTokens: usage?.imageTokens ?? 0,
        audioTokens: usage?.audioTokens ?? 0,
        videoTokens: usage?.videoTokens ?? 0,
        reasoningTokens: usage?.reasoningTokens ?? 0,
        audioSeconds: usage?.audioSeconds ?? 0,
        usageAvailable: usage != null,
      );
    } catch (_) {
      // Cost tracking must not invalidate a successful text recognition.
    }
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }

    final message = choices[0]['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';
    final reasoning = (message['reasoning_content'] as String?) ?? '';
    final fullContent =
        reasoning.isNotEmpty ? '$reasoning\n\n$content' : content;

    // print('========== LLM 文本响应 ==========');
    // print('原始返回:\n$fullContent');
    // print('==================================');

    final results = _extractJsonList(fullContent);

    // print('解析结果: $results');
    // print('==================================');

    return results;
  }

  static Future<List<Map<String, dynamic>>> parseTodoFromImage(
      String imagePath) {
    return _parseImageWithPrompt(
      imagePath,
      operation: 'vision_todo',
      promptBuilder: (config, nowStr) =>
          '${config.visionPrompt.replaceAll('{now}', nowStr)}\n\n'
          '${LLMConfig.itemSemanticGuardrailPrompt}',
    );
  }

  /// Performs the finance half of a shared-image recognition pass. This is
  /// intentionally separate from [parseTodoFromImage]: a vision model should
  /// be allowed to return both a pickup todo and a bill from the same image.
  static Future<List<Map<String, dynamic>>> parseFinanceFromImage(
      String imagePath) {
    return _parseImageWithPrompt(
      imagePath,
      operation: 'vision_finance',
      promptBuilder: (_, nowStr) =>
          LLMConfig.defaultFinanceVisionPrompt.replaceAll('{now}', nowStr),
    );
  }

  static Future<List<Map<String, dynamic>>> _parseImageWithPrompt(
    String imagePath, {
    required String operation,
    required String Function(LLMConfig config, String nowStr) promptBuilder,
  }) async {
    await _ensureAiInteractionAllowed();
    final config = await getConfig();
    if (config == null || !config.isConfigured) {
      throw Exception('大模型未配置，请先在设置中配置API');
    }

    final imageInput = await readImageInput(imagePath);
    final fileSize = imageInput.length;
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('图片太大，请使用小于10MB的图片');
    }

    final base64Image = await Future.microtask(
      () => base64Encode(imageInput.bytes),
    );
    final now = DateTime.now();
    final nowStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final prompt = promptBuilder(config, nowStr);

    final configuredVisionProvider = config.visionProvider?.trim();
    final visionProvider = configuredVisionProvider?.isNotEmpty == true
        ? configuredVisionProvider
        : (config.provider == AiChatService.mimoTokenPlanProvider ||
                AiChatService.inferProviderFromApiUrl(config.apiUrl) ==
                    AiChatService.mimoTokenPlanProvider
            ? AiChatService.mimoTokenPlanProvider
            : null);
    final endpoint = await resolveVisionEndpoint(
      config.visionModel,
      provider: visionProvider,
    );
    final visionUrl = endpoint.url.isNotEmpty
        ? endpoint.url
        : AiChatService.resolveChatUrl(config.provider, config.apiUrl);
    final visionKey = endpoint.key.isNotEmpty ? endpoint.key : config.apiKey;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $visionKey',
    };
    final imageUrl = 'data:${imageInput.mimeType};base64,$base64Image';
    final body = jsonEncode({
      'model': config.visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': imageUrl},
            },
          ],
        },
      ],
      'temperature': 0.1,
    });

    final response = await http
        .post(
          Uri.parse(visionUrl),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      throw Exception('API调用失败: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final usage = AiTokenUsage.fromJson(data['usage']);
    try {
      final usageProvider = AiChatService.effectiveProvider(
        visionProvider ?? config.provider,
        visionUrl,
      );
      await AiUsageCostService.recordUsage(
        provider: usageProvider.isEmpty ? 'custom' : usageProvider,
        model: config.visionModel,
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
        imageCount: 1,
        usageAvailable: usage != null,
      );
    } catch (_) {
      // Cost tracking must not invalidate a successful image recognition.
    }
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回数据格式异常');
    }
    final message = choices[0]['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';
    final reasoning = (message['reasoning_content'] as String?) ?? '';
    final fullContent =
        reasoning.isNotEmpty ? '$reasoning\n\n$content' : content;
    return _extractJsonList(fullContent);
  }

  static Future<void> _ensureAiInteractionAllowed() async {
    final allowed = await MinorModeService.instance.authorizeAiInteraction();
    if (!allowed) {
      throw const MinorModeAccessException('当前未成年人模式年龄段暂不允许使用高级 AI 功能');
    }
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
        if (obj.containsKey('title') ||
            obj.containsKey('itemKind') ||
            obj.containsKey('item_kind') ||
            obj.containsKey('amount') ||
            obj.containsKey('amount_minor')) {
          results.add(obj);
        }
      } catch (_) {}
    }
    if (results.isNotEmpty) return results;

    throw Exception('无法从返回内容中提取JSON: $content');
  }
}
