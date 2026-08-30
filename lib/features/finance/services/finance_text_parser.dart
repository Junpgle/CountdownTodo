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

  static FinanceTransactionType _parseType(String text) {
    final value = text.toLowerCase();
    if (value.contains('退款') || value.contains('refund')) {
      return FinanceTransactionType.refund;
    }
    if (value.contains('收入') ||
        value.contains('进账') ||
        value.contains('收款') ||
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
