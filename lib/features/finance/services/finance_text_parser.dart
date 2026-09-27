import 'dart:convert';

import '../models/finance_ai_action.dart';
import '../models/finance_models.dart';
import 'finance_repository.dart';

/// Recognizes the small, deliberately explicit text format used by the
/// finance import entry point and by the AI assistant.
abstract final class FinanceTextParser {
  static const String formatHelp = '''推荐格式（每笔一段）：
#记账
类型: 支出
金额: 28.50
分类: 餐饮
商家: 午餐
日期: 2026-08-29
付款方式: 微信
备注: 工作日午餐

类型支持：支出、收入、退款。金额单位为元，日期省略时默认为今天。''';

  /// The natural-language shortcut shown in the normal entry form.
  ///
  /// It is parsed into drafts and never saved directly. This keeps quick
  /// entry just as reviewable as text recognition while allowing one or more
  /// bills in the same input.
  static const String quickEntryExample = '今天早餐 8 元，微信；中午午餐 25 元，支付宝';
  static const String quickEntryHelp =
      '直接描述一笔或多笔账单；多笔请用换行或分号分开，缺少分类和付款方式也可以稍后补充';

  /// Kept for callers that still use the old single-sentence wording.
  static const String oneSentenceExample = '今天午餐花了 28.5 元，微信支付，分类餐饮';
  static const String oneSentenceHelp = '说法：时间 + 事项 + 金额 + 付款方式 + 分类\n'
      '示例：今天午餐花了 28.5 元，微信支付，分类餐饮';

  static const Map<String, String> _sentencePaymentAliases = {
    'apple pay': 'Apple Pay',
    'paypal': 'PayPal',
    '信用卡': '信用卡',
    '银行卡': '银行卡',
    '借记卡': '银行卡',
    '支付宝': '支付宝',
    '微信': '微信',
    '花呗': '花呗',
    '云闪付': '云闪付',
    '现金': '现金',
  };

  static const Map<String, String> _expenseCategoryAliases = {
    '餐饮': '餐饮',
    '吃饭': '餐饮',
    '吃东西': '餐饮',
    '用餐': '餐饮',
    '早餐': '早餐',
    '早饭': '早餐',
    '午餐': '午餐',
    '午饭': '午餐',
    '晚餐': '晚餐',
    '晚饭': '晚餐',
    '夜宵': '晚餐',
    '咖啡': '咖啡',
    '奶茶': '奶茶',
    '饮料': '餐饮',
    '外卖': '外卖',
    '点餐': '外卖',
    '餐厅': '餐饮',
    '食堂': '餐饮',
    '买菜': '买菜',
    '交通': '交通',
    '地铁': '公交地铁',
    '公交': '公交地铁',
    '打车': '打车',
    '出租车': '打车',
    '网约车': '打车',
    '滴滴': '打车',
    '共享单车': '骑行',
    '单车': '骑行',
    '公交车': '公交地铁',
    '火车': '火车飞机',
    '高铁': '火车飞机',
    '飞机': '火车飞机',
    '机票': '火车飞机',
    '加油': '加油',
    '充电': '加油',
    '停车': '停车',
    '过路费': '交通',
    '高速费': '交通',
    '购物': '购物',
    '买东西': '购物',
    '买了东西': '购物',
    '购买商品': '购物',
    '商场': '购物',
    '超市': '购物',
    '网购': '购物',
    '衣服': '服饰鞋包',
    '鞋子': '服饰鞋包',
    '鞋': '服饰鞋包',
    '化妆品': '美妆个护',
    '日用品': '日用品',
    '数码': '数码',
    '手机': '数码',
    '电脑': '数码',
    '家具': '家居家电',
    '家电': '家居家电',
    '宠物': '宠物用品',
    '淘宝': '购物',
    '京东': '购物',
    '拼多多': '购物',
    '房贷': '房租',
    '房租': '房租',
    '租房': '房租',
    '水电': '水电燃气',
    '水费': '水电燃气',
    '电费': '水电燃气',
    '燃气': '水电燃气',
    '物业': '物业',
    '宽带': '通讯网络',
    '话费': '通讯网络',
    '居住': '居住',
    '住房': '居住',
    '学习': '学习',
    '课程': '课程培训',
    '学费': '课程培训',
    '教材': '书籍',
    '书籍': '书籍',
    '买书': '书籍',
    '培训': '课程培训',
    '考试': '考试报名',
    '报名': '考试报名',
    '学校': '学习',
    '娱乐': '娱乐',
    '电影': '电影演出',
    '看电影': '电影演出',
    '游戏': '游戏',
    '游戏充值': '游戏',
    '电影票': '电影演出',
    '演唱会': '电影演出',
    '音乐': '音乐',
    'ktv': '娱乐',
    '旅游': '娱乐',
    '旅行': '娱乐',
    '健康': '健康',
    '医院': '医疗就诊',
    '看病': '医疗就诊',
    '挂号': '医疗就诊',
    '买药': '药品',
    '买了药': '药品',
    '药品': '药品',
    '药店': '药品',
    '体检': '体检',
    '看牙': '医疗就诊',
    '牙医': '医疗就诊',
    '健身': '健身',
    '医疗': '医疗就诊',
    '社交': '社交',
    '礼物': '礼物',
    '送礼': '礼物',
    '红包': '红包',
    '请客': '聚餐',
    '份子钱': '随礼',
    '人情': '随礼',
    '订阅': '订阅',
    '视频会员': '视频会员',
    '音乐会员': '音乐会员',
    '会员': '订阅',
    '续费': '订阅',
    '月费': '订阅',
    '年费': '订阅',
    '网盘': '云存储',
    'icloud': '云存储',
    'ai服务': 'AI 服务',
    '人工智能': 'AI 服务',
    'chatgpt': 'AI 服务',
    'openai': 'AI 服务',
    'claude': 'AI 服务',
    'gemini': 'AI 服务',
    '模型': 'AI 服务',
    'api': 'AI 服务',
    '贷款利息': '贷款利息',
    '借款利息': '贷款利息',
    '还款利息': '贷款利息',
    '利息': '贷款利息',
    '其他': '其他',
  };

  static const Map<String, String> _incomeCategoryAliases = {
    '工资': '工资',
    '基本工资': '基本工资',
    '薪资': '工资',
    '薪水': '工资',
    '发薪': '工资',
    '月薪': '工资',
    '加班费': '加班费',
    '津贴': '津贴补贴',
    '补贴': '津贴补贴',
    '兼职工资': '工资',
    '零花钱': '零花钱',
    '生活费': '生活费',
    '零用钱': '生活费',
    '家里给': '家庭支持',
    '父母给': '家庭支持',
    '奖金': '奖金',
    '年终奖': '年终奖',
    '绩效': '项目奖金',
    '奖励': '竞赛奖励',
    '其他收入': '其他',
    '其他': '其他',
  };

  static final RegExp _blockMarker = RegExp(
    r'^[ \t]*(?:#[ \t]*)?(?:\[[ \t]*)?记账(?:[ \t]*#?[ \t]*\d+)?(?:[ \t]*\])?(?=[ \t]*(?:\||$))',
    multiLine: true,
  );

  /// Returns true only for an explicitly marked block or text that contains
  /// both a bill amount and a clear cash-flow direction.
  static bool looksLikeFinanceFormat(String input) {
    final text = input.replaceAll('：', ':');
    final hasMarker = _blockMarker.hasMatch(text);
    final hasAmount = RegExp(
      r'(?:金额|amount|¥|￥|\bCNY\b)\s*[:=]?\s*[-+]?\d+(?:[,.]\d+)*',
      caseSensitive: false,
    ).hasMatch(text);
    final hasType = RegExp(
      r'(?:类型|方向|收支|type|transaction[_ ]?type)\s*[:=]?\s*(?:支出|收入|退款|expense|income|refund)',
      caseSensitive: false,
    ).hasMatch(text);
    final hasDirectionWord = RegExp(
      r'支出|收入|退款|消费|进账|expense|income|refund',
      caseSensitive: false,
    ).hasMatch(text);
    return hasMarker || (hasAmount && (hasType || hasDirectionWord));
  }

  /// Parses the single-line natural-language shortcut used by the entry form.
  ///
  /// Examples:
  /// - 今天午餐花了 28.5 元，微信支付，分类餐饮
  /// - 昨天收到工资 8000 元，分类工资
  /// - 前天退款 20 元，支付宝
  ///
  /// Amount is required. Other fields are best effort; the caller still
  /// presents the result in the normal editor for review.
  static FinanceEntryDraft? parseOneSentence(
    String input, {
    DateTime? now,
    FinanceEntrySource source = FinanceEntrySource.manual,
  }) {
    final text = _normalizeOneSentence(input);
    if (text.isEmpty) return null;

    final amountMatch = _findSentenceAmountMatch(text);
    final amount = _parseAmount(amountMatch?.group(1));
    if (amount == null || amount <= 0 || amountMatch == null) return null;

    final current = now ?? DateTime.now();
    final type = _parseType(text);
    final explicitCategory = _extractSentenceValue(
      text,
      RegExp(
        r'(?:分类|类别|归类为?|记到)\s*[:=]?\s*([^,，。；;]+)',
      ),
    );
    final category = explicitCategory == null
        ? _inferSentenceCategory(text, type)
        : _inferSentenceCategory(explicitCategory, type) ?? explicitCategory;
    final payment = _normalizeSentencePayment(
      _extractSentenceValue(
        text,
        RegExp(
          r'(?:付款方式|支付方式|付款(?!给)|支付(?!宝|给)|用(?!于)|通过)'
          r'\s*[:=]?\s*([^,，。；;]+)',
        ),
      ),
      text,
    );
    final note = _extractSentenceValue(
      text,
      RegExp(r'(?:备注|说明)\s*[:=]?\s*([^,，。；;]+)'),
    );
    final explicitMerchant = _extractSentenceValue(
      text,
      RegExp(r'(?:商家|商户|店铺|项目|名称)\s*[:=]?\s*([^,，。；;]+)'),
    );
    final merchant = explicitMerchant ??
        _deriveSentenceMerchant(
          text,
          amountMatch,
          category: category,
          payment: payment,
          note: note,
        );

    return FinanceEntryDraft(
      type: type,
      amountMinor: amount,
      transactionDate: dateKey(_parseSentenceDate(text, current)),
      categoryName: category,
      paymentMethodName: payment,
      merchant: merchant,
      note: note,
      source: source,
      originalText: input.trim(),
    );
  }

  /// Parses the flexible natural-language input used by the normal entry
  /// form. Structured blocks continue to use [parse]; ordinary text can be a
  /// single sentence or multiple entries separated by a newline, semicolon,
  /// or Chinese full stop.
  static List<FinanceEntryDraft> parseQuickEntries(
    String input, {
    DateTime? now,
    FinanceEntrySource source = FinanceEntrySource.manual,
  }) {
    final normalized =
        input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return const [];

    final structuredText = normalized.replaceAll('：', ':');
    final hasStructuredFields = RegExp(
      r'(?:^|\n)\s*(?:#?记账|类型|方向|收支|金额|分类|日期|付款方式)\s*[:=]',
      multiLine: true,
    ).hasMatch(structuredText);
    if (_blockMarker.hasMatch(structuredText) || hasStructuredFields) {
      final structured = parse(
        normalized,
        now: now,
        source: source,
      );
      if (structured.isNotEmpty) return structured;
    }

    final segments = _splitQuickEntrySegments(normalized);
    final drafts = <FinanceEntryDraft>[];
    for (final segment in segments) {
      final draft = parseOneSentence(
        segment,
        now: now,
        source: source,
      );
      if (draft != null) drafts.add(draft);
    }

    // A line break or punctuation may only be visual wrapping inside one
    // entry. Prefer the whole-text parse whenever it yields one draft.
    final wholeDraft = parseOneSentence(
      normalized.replaceAll('\n', ' '),
      now: now,
      source: source,
    );
    if (wholeDraft != null && drafts.length <= 1) return [wholeDraft];
    return _deduplicate(drafts);
  }

  /// Parses one or more explicit bill blocks. Invalid/incomplete blocks are
  /// ignored so a mixed clipboard payload can still yield valid entries.
  static List<FinanceEntryDraft> parse(
    String input, {
    DateTime? now,
    FinanceEntrySource source = FinanceEntrySource.import,
  }) {
    final normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('：', ':')
        .trim();
    if (normalized.isEmpty) return const [];

    final blocks = _splitBlocks(normalized);
    final drafts = <FinanceEntryDraft>[];
    for (final block in blocks) {
      final fields = _parseFields(block);
      final draft = _draftFromFields(
        fields,
        block,
        now: now,
        source: source,
        originalText: input,
      );
      if (draft != null) drafts.add(draft);
    }
    return _deduplicate(drafts);
  }

  /// Converts typed results from a vision model into finance drafts while
  /// leaving todo/meal-pickup results untouched for the todo confirmation UI.
  static List<FinanceEntryDraft> fromRecognitionResults(
    Iterable<Map<String, dynamic>> results, {
    DateTime? now,
    FinanceEntrySource source = FinanceEntrySource.import,
    String? originalText,
  }) {
    final drafts = <FinanceEntryDraft>[];
    for (final result in results) {
      if (!isFinanceResult(result)) continue;
      final normalized = <String, dynamic>{...result};
      if (normalized['originalText'] == null && originalText != null) {
        normalized['originalText'] = originalText;
      }
      final draft = FinanceEntryDraft.fromJson(normalized)
        ..source = source
        ..originalText ??= originalText;
      if (draft.amountMinor > 0) {
        if (draft.transactionDate.trim().isEmpty) {
          draft.transactionDate = dateKey(now ?? DateTime.now());
        }
        drafts.add(draft);
      }
    }
    return _deduplicate(drafts);
  }

  /// Extracts the assistant's separate finance event protocol.
  ///
  /// The assistant returns a draft, never a saved transaction. The UI then
  /// opens the normal editor so the user can correct it before saving.
  static List<FinanceEntryDraft> extractAssistantDrafts(
    String content, {
    DateTime? now,
  }) {
    final drafts = <FinanceEntryDraft>[];
    final marker = RegExp(
      r'\[FINANCE_START\](.*?)\[FINANCE_END\]',
      dotAll: true,
    );
    for (final match in marker.allMatches(content)) {
      final payload = _decodeMaps(match.group(1) ?? '');
      for (final map in payload) {
        final draft = FinanceEntryDraft.fromJson(map)
          ..source = FinanceEntrySource.ai;
        if (draft.amountMinor > 0) {
          if (draft.transactionDate.trim().isEmpty) {
            draft.transactionDate = dateKey(now ?? DateTime.now());
          }
          drafts.add(draft);
        }
      }
    }
    return _deduplicate(drafts);
  }

  /// Extracts read-only finance queries and confirmation-required mutations.
  ///
  /// The preferred wrapper is `[FINANCE_ACTION_START]`; accepting a finance
  /// action inside `[ACTION_START]` as a fallback makes pasted responses from
  /// older/custom prompts recoverable without treating todo actions as bills.
  static List<FinanceAiAction> extractAssistantActions(String content) {
    final actions = <FinanceAiAction>[];
    final blocks = <String>[];
    for (final marker in [
      RegExp(
        r'\[FINANCE_ACTION_START\](.*?)\[FINANCE_ACTION_END\]',
        dotAll: true,
      ),
      RegExp(r'\[ACTION_START\](.*?)\[ACTION_END\]', dotAll: true),
    ]) {
      blocks.addAll(
        marker.allMatches(content).map((match) => match.group(1) ?? ''),
      );
    }

    for (final block in blocks) {
      for (final map in _decodeMaps(block)) {
        final direct = FinanceAiAction.tryParse(map);
        if (direct != null) actions.add(direct);

        final nested = map['actions'] ??
            map['updates'] ??
            map['queries'] ??
            map['financeActions'] ??
            map['finance_actions'];
        if (nested is List) {
          for (final item in nested.whereType<Map>()) {
            final nestedMap = <String, dynamic>{
              'action': map['action'] ?? map['actionType'],
              ...Map<String, dynamic>.from(item),
            };
            final parsed = FinanceAiAction.tryParse(nestedMap);
            if (parsed != null) actions.add(parsed);
          }
        }
      }
    }
    return actions;
  }

  static String cleanAssistantContent(String content) {
    return content
        .replaceAll(
          RegExp(r'\[FINANCE_START\].*?\[FINANCE_END\]', dotAll: true),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[FINANCE_ACTION_START\].*?\[FINANCE_ACTION_END\]',
            dotAll: true,
          ),
          '',
        )
        .trim();
  }

  static bool isFinanceResult(Map<String, dynamic> result) {
    final kind = (result['itemKind'] ??
            result['item_kind'] ??
            result['eventType'] ??
            result['event_type'] ??
            result['kind'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (result['isFinance'] == true || result['is_finance'] == true) {
      return true;
    }
    if (const {
      'finance',
      'finance_entry',
      'transaction',
      '账单',
      'expense',
      'income',
      'refund',
    }.contains(kind)) {
      return true;
    }
    final hasAmount = result.containsKey('amount') ||
        result.containsKey('amount_yuan') ||
        result.containsKey('amountYuan') ||
        result.containsKey('total') ||
        result.containsKey('total_amount') ||
        result.containsKey('totalAmount') ||
        result.containsKey('money') ||
        result.containsKey('price') ||
        result.containsKey('amount_minor') ||
        result.containsKey('amountMinor');
    final type = (result['type'] ??
            result['transaction_type'] ??
            result['transactionType'])
        ?.toString()
        .trim()
        .toLowerCase();
    final hasCashFlowType = const {
      'expense',
      'income',
      'refund',
      '支出',
      '收入',
      '退款',
      '进账',
      '入账',
      '收款',
    }.contains(type);
    return hasAmount &&
        (hasCashFlowType ||
            result.containsKey('category') ||
            result.containsKey('merchant') ||
            result.containsKey('paymentMethod') ||
            result.containsKey('payment_method'));
  }

  static List<FinanceEntryDraft> _deduplicate(
    Iterable<FinanceEntryDraft> drafts,
  ) {
    final result = <FinanceEntryDraft>[];
    final seen = <String>{};
    for (final draft in drafts) {
      final key = [
        draft.type.name,
        draft.amountMinor,
        draft.transactionDate,
        draft.categoryUuid ?? draft.categoryName ?? '',
        draft.merchant ?? '',
        draft.note ?? '',
      ].join('|').toLowerCase();
      if (seen.add(key)) result.add(draft);
    }
    return result;
  }

  static List<String> _splitBlocks(String text) {
    final matches = _blockMarker.allMatches(text).toList();
    if (matches.isEmpty) return [text];

    final blocks = <String>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
      final block = text.substring(start, end).trim();
      if (block.isNotEmpty) blocks.add(block);
    }
    return blocks;
  }

  static List<String> _splitQuickEntrySegments(String text) {
    final sentenceSegments = text
        .split(RegExp(r'[\n；;。！？!?]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final segments = <String>[];
    for (final segment in sentenceSegments) {
      segments.addAll(_splitCommaSeparatedQuickEntries(segment));
    }
    return segments;
  }

  static List<String> _splitCommaSeparatedQuickEntries(String text) {
    final clauses = text
        .split(RegExp(r'\s*[,，]\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (clauses.length < 2) return [text];

    final groups = <String>[];
    var current = '';
    for (final clause in clauses) {
      final startsEntry = _findSentenceAmountMatch(clause) != null;
      if (startsEntry && current.trim().isNotEmpty) {
        groups.add(current.trim());
        current = clause;
      } else if (current.isEmpty) {
        current = clause;
      } else {
        current = '$current，$clause';
      }
    }
    if (current.trim().isNotEmpty) groups.add(current.trim());
    return groups.length > 1 ? groups : [text];
  }

  static Map<String, String> _parseFields(String block) {
    final fields = <String, String>{};
    final lines = block.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line == '---') continue;
      final separator =
          line.contains(':') ? line.indexOf(':') : line.indexOf('=');
      if (separator > 0) {
        final key = _normalizeKey(line.substring(0, separator));
        final value = line.substring(separator + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) fields[key] = value;
      }
    }

    // Also accept a compact form:
    // #记账 | 支出 | 28.50 | 餐饮 | 午餐 | 2026-08-29 | 微信 | 备注
    final compactParts = block
        .split(RegExp(r'\s*[|｜]\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (compactParts.length >= 2) {
      final values = compactParts
          .where((part) => !part.replaceAll('#', '').contains('记账'))
          .toList();
      if (values.isNotEmpty) {
        fields.putIfAbsent('类型', () => values[0]);
        if (values.length > 1) fields.putIfAbsent('金额', () => values[1]);
        if (values.length > 2) fields.putIfAbsent('分类', () => values[2]);
        if (values.length > 3) fields.putIfAbsent('商家', () => values[3]);
        if (values.length > 4) fields.putIfAbsent('日期', () => values[4]);
        if (values.length > 5) {
          fields.putIfAbsent('付款方式', () => values[5]);
        }
        if (values.length > 6) fields.putIfAbsent('备注', () => values[6]);
      }
    }
    return fields;
  }

  static FinanceEntryDraft? _draftFromFields(
    Map<String, String> fields,
    String block, {
    required DateTime? now,
    required FinanceEntrySource source,
    required String originalText,
  }) {
    final amountText = _first(fields, const [
      '金额',
      'amount',
      '总额',
      '价格',
      '消费金额',
    ]);
    final amount = _parseAmount(amountText) ?? _findAmount(block);
    if (amount == null || amount <= 0) return null;

    final typeText = _first(fields, const [
      '类型',
      '方向',
      '收支',
      'type',
      'transactiontype',
    ]);
    final type = _parseType(typeText ?? block);
    final dateText = _first(fields, const ['日期', 'date', '账单日期', '时间']);
    final date = _parseDate(dateText, now ?? DateTime.now());
    final merchant = _first(fields, const [
      '商家',
      '商户',
      '标题',
      '名称',
      '项目',
      'merchant',
      'title',
    ]);
    final category = _first(fields, const ['分类', '类别', 'category']);
    final payment = _first(fields, const [
      '付款方式',
      '支付方式',
      '支付',
      '账户',
      'paymentmethod',
      'payment',
    ]);
    final note = _first(fields, const ['备注', '说明', '详情', 'note', 'remark']);

    return FinanceEntryDraft(
      type: type,
      amountMinor: amount,
      transactionDate: dateKey(date),
      categoryName: category,
      paymentMethodName: payment,
      merchant: merchant,
      note: note,
      source: source,
      originalText: originalText,
    );
  }

  static String _normalizeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
  }

  static String? _first(Map<String, String> fields, List<String> keys) {
    for (final key in keys) {
      final value = fields[_normalizeKey(key)];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static int? _parseAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw
        .trim()
        .replaceAll(',', '')
        .replaceAll(RegExp(r'^[¥￥$€£]\s*'), '')
        .replaceAll(RegExp(r'\s*(?:元|块|人民币|CNY)\s*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^\+'), '')
        .replaceFirst(RegExp(r'^-'), '');
    return parseFinanceAmount(normalized);
  }

  static int? _findAmount(String text) {
    final match = RegExp(
      r'(?:¥|￥|金额\s*[:=]?\s*|消费\s*[:=]?\s*|实付\s*[:=]?\s*|合计\s*[:=]?\s*|总额\s*[:=]?\s*)(-?\s*\d+(?:[,.]\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    return _parseAmount(match?.group(1));
  }

  static RegExpMatch? _findSentenceAmountMatch(String text) {
    final patterns = [
      RegExp(r'(?:¥|￥)\s*(\d+(?:[,.]\d+)*)', caseSensitive: false),
      RegExp(
        r'(\d+(?:[,.]\d+)*)\s*(?:元|块钱?|人民币|CNY|RMB)(?![A-Za-z])',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:金额|花(?:了|费)?|支出|收入|收到|退款|消费|支付|付款|付了|共|合计|实付)'
        r'\s*[:=]?\s*(?:¥|￥)?\s*(\d+(?:[,.]\d+)*)',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match;
    }

    // A natural sentence often omits both the comma and the currency unit,
    // for example "午餐28.5微信支付". Pick a likely amount from the remaining
    // numeric tokens, while excluding dates and clock-like values.
    final fallback = RegExp(
      r'(?<![\d.])((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)(?![\d.])',
    );
    RegExpMatch? best;
    var bestScore = -1;
    for (final match in fallback.allMatches(text)) {
      if (!_isLikelySentenceAmount(text, match)) continue;
      final before = text.substring(0, match.start);
      final recentBefore =
          before.length > 10 ? before.substring(before.length - 10) : before;
      var score = match.group(1)!.contains('.') ? 2 : 0;
      if (RegExp(
        r'(?:花(?:了|费)?|消费|支付|付款|金额|支出|收入|收到|退款|共|合计|实付)\s*[:=]?\s*$',
      ).hasMatch(recentBefore)) {
        score += 10;
      }
      // In an unlabelled sentence the last valid number is the most likely
      // amount (e.g. "买了2个苹果 午餐28").
      if (best == null || score >= bestScore) {
        best = match;
        bestScore = score;
      }
    }
    return best;
  }

  static bool _isLikelySentenceAmount(String text, RegExpMatch match) {
    final before = text.substring(0, match.start);
    final after = text.substring(match.end);
    if (RegExp(r'^\s*(?:年|月|日|号|点|时|分)').hasMatch(after)) {
      return false;
    }
    if (RegExp(r'(?:年|月|日|号)\s*$').hasMatch(before)) return false;
    if (RegExp(r'[-/.]\s*$').hasMatch(before) ||
        RegExp(r'^\s*[-/.]').hasMatch(after)) {
      return false;
    }
    if (RegExp(r':\s*$').hasMatch(before) || RegExp(r'^\s*:').hasMatch(after)) {
      return false;
    }
    return true;
  }

  static String _normalizeOneSentence(String input) {
    return input
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('：', ':')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _extractSentenceValue(String text, RegExp pattern) {
    final value = pattern.firstMatch(text)?.group(1);
    if (value == null) return null;
    var normalized = value.trim();
    normalized = normalized
        .replaceFirst(RegExp(r'^[,，。；;、\s]+'), '')
        .replaceFirst(RegExp(r'[,，。；;、\s]+$'), '')
        .trim();
    final nextField = RegExp(
      r'(?:^|\s)(?:分类|类别|归类为?|记到|付款方式|支付方式|付款|支付|备注|说明|商家|商户|店铺|项目|名称)\s*[:=]?',
    ).firstMatch(normalized);
    if (nextField != null) {
      if (nextField.start == 0) return null;
      normalized = normalized.substring(0, nextField.start).trim();
    }
    return normalized.isEmpty ? null : normalized;
  }

  static String? _normalizeSentencePayment(String? explicit, String text) {
    final explicitValue = _knownSentencePayment(explicit);
    if (explicitValue != null) return explicitValue;
    final paymentInText = _knownSentencePayment(text);
    if (explicit != null && explicit.trim().isNotEmpty) {
      if (paymentInText != null &&
          RegExp(
            r'^(?:分类|类别|归类为?|记到|备注|说明|商家|商户|店铺|项目|名称)\s*[:=]?',
          ).hasMatch(explicit.trim())) {
        return paymentInText;
      }
      return explicit.trim();
    }
    return paymentInText;
  }

  static String? _knownSentencePayment(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().toLowerCase();
    for (final entry in _sentencePaymentAliases.entries) {
      if (normalized.contains(entry.key.toLowerCase())) return entry.value;
    }
    return null;
  }

  static String? _inferSentenceCategory(
    String text,
    FinanceTransactionType type,
  ) {
    if (type == FinanceTransactionType.refund) return '退款';
    final aliases = type == FinanceTransactionType.income
        ? _incomeCategoryAliases
        : _expenseCategoryAliases;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    String? matchedCategory;
    var matchedLength = 0;
    for (final entry in aliases.entries) {
      final alias = entry.key.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (normalized.contains(alias) && alias.length > matchedLength) {
        matchedCategory = entry.value;
        matchedLength = alias.length;
      }
    }
    return matchedCategory;
  }

  /// Maps natural-language finance terms to the canonical local category name.
  /// The entry screen uses this same mapping when resolving the result to a
  /// real local category UUID, so aliases do not remain as display-only text.
  static String? inferCategoryName(
    String text,
    FinanceTransactionType type,
  ) {
    return _inferSentenceCategory(text, type);
  }

  static String? _deriveSentenceMerchant(
    String text,
    RegExpMatch amountMatch, {
    String? category,
    String? payment,
    String? note,
  }) {
    final candidates = <String>[
      text.substring(0, amountMatch.start),
      text.substring(amountMatch.end).split(RegExp(r'[,，。；;]')).first,
    ];
    for (final candidate in candidates) {
      var value = candidate.trim();
      if (value.isEmpty) continue;
      value = _removeSentenceDate(value);
      value = value.replaceAll(
        RegExp(
          r'记一笔|记账|记录|一共|合计|实付|金额|支出|收入|退款|消费|花(?:了|费)?|'
          r'用了?|支付了?|付款了?|付了|买了?|购买了?|收到|入账|进账|收款|赚到?|'
          r'用于|在|于|给|为',
        ),
        '',
      );
      value = value
          .replaceAll(RegExp(r'^[:：,，。；;、\s]+'), '')
          .replaceAll(RegExp(r'[:：,，。；;、\s]+$'), '')
          .trim();
      value = value.replaceFirst(RegExp(r'^(?:的|一笔)'), '').trim();
      if (value.isEmpty || value.length > 80) continue;
      if ((_sameSentenceValue(value, category) &&
              !_isDefaultSubcategoryName(category)) ||
          _sameSentenceValue(value, payment) ||
          _sameSentenceValue(value, note) ||
          _knownSentencePayment(value) != null ||
          RegExp(r'^(?:分类|类别|付款方式|支付方式|备注|说明)').hasMatch(value)) {
        continue;
      }
      return value;
    }
    return null;
  }

  static bool _sameSentenceValue(String value, String? other) {
    return other != null &&
        value.trim().toLowerCase() == other.trim().toLowerCase();
  }

  static bool _isDefaultSubcategoryName(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return FinanceDefaults.categories.any(
      (item) =>
          item['parent_uuid'] != null &&
          item['name']?.toString().trim().toLowerCase() == normalized,
    );
  }

  static String _removeSentenceDate(String value) {
    return value
        .replaceAll(RegExp(r'今天|昨天|前天|明天'), '')
        .replaceAll(
          RegExp(
            r'\d{4}\s*(?:年|[-/.])\s*\d{1,2}\s*'
            r'(?:月|[-/.])\s*\d{1,2}\s*日?',
          ),
          '',
        )
        .replaceAll(RegExp(r'\d{1,2}\s*月\s*\d{1,2}\s*日?'), '')
        .replaceAll(RegExp(r'\d{1,2}\s*/\s*\d{1,2}'), '');
  }

  static DateTime _parseSentenceDate(String text, DateTime now) {
    final relative = RegExp(r'今天|昨天|前天|明天').firstMatch(text)?.group(0);
    if (relative != null) return _parseDate(relative, now);

    final full = RegExp(
      r'(?<!\d)(\d{4})\s*(?:年|[-/.])\s*(\d{1,2})\s*'
      r'(?:月|[-/.])\s*(\d{1,2})\s*日?',
    ).firstMatch(text);
    if (full != null) {
      final parsed = _safeSentenceDate(
        int.tryParse(full.group(1) ?? ''),
        int.tryParse(full.group(2) ?? ''),
        int.tryParse(full.group(3) ?? ''),
      );
      if (parsed != null) return parsed;
    }

    final monthDay = RegExp(
      r'(?<!\d)(\d{1,2})\s*月\s*(\d{1,2})\s*日?',
    ).firstMatch(text);
    if (monthDay != null) {
      final parsed = _safeSentenceDate(
        now.year,
        int.tryParse(monthDay.group(1) ?? ''),
        int.tryParse(monthDay.group(2) ?? ''),
      );
      if (parsed != null) return parsed;
    }

    final slashMonthDay = RegExp(
      r'(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)',
    ).firstMatch(text);
    if (slashMonthDay != null) {
      final parsed = _safeSentenceDate(
        now.year,
        int.tryParse(slashMonthDay.group(1) ?? ''),
        int.tryParse(slashMonthDay.group(2) ?? ''),
      );
      if (parsed != null) return parsed;
    }
    return _day(now);
  }

  static DateTime? _safeSentenceDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return null;
    final candidate = DateTime(year, month, day);
    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    return _day(candidate);
  }

  static FinanceTransactionType _parseType(String text) {
    final value = text.toLowerCase();
    if (value.contains('退款') || value.contains('refund')) {
      return FinanceTransactionType.refund;
    }
    if (value.contains('收入') ||
        value.contains('进账') ||
        value.contains('收款') ||
        value.contains('收到') ||
        value.contains('到账') ||
        value.contains('赚到') ||
        value.contains('income') ||
        value.contains('入账')) {
      return FinanceTransactionType.income;
    }
    return FinanceTransactionType.expense;
  }

  static DateTime _parseDate(String? raw, DateTime now) {
    if (raw == null || raw.trim().isEmpty) return _day(now);
    final value = raw.trim().toLowerCase();
    if (value.contains('今天') || value == 'today') return _day(now);
    if (value.contains('昨天') || value == 'yesterday') {
      return _day(now.subtract(const Duration(days: 1)));
    }
    if (value.contains('前天')) {
      return _day(now.subtract(const Duration(days: 2)));
    }
    if (value.contains('明天') || value == 'tomorrow') {
      return _day(now.add(const Duration(days: 1)));
    }

    final normalized = value
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', '')
        .replaceAll('/', '-')
        .replaceAll('.', '-');
    final match =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
    if (match != null) {
      final parsed = DateTime.tryParse(
        '${match.group(1)}-${match.group(2)!.padLeft(2, '0')}-${match.group(3)!.padLeft(2, '0')}',
      );
      if (parsed != null) return _day(parsed);
    }
    return _day(now);
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static List<Map<String, dynamic>> _decodeMaps(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (decoded is Map) {
        final entries =
            decoded['entries'] ?? decoded['finance'] ?? decoded['transactions'];
        if (entries is List) {
          return entries
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
        return [Map<String, dynamic>.from(decoded)];
      }
    } catch (_) {
      // The assistant may have returned a nearly-valid block. The normal
      // chat message remains visible; only the editable finance card is
      // skipped in that case.
    }
    return const [];
  }
}
