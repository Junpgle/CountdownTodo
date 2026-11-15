import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../models/finance_models.dart';
import 'finance_repository.dart';

/// 支持导入的第三方账单平台。
enum FinanceBillPlatform {
  wechat,
  alipay;

  String get label => switch (this) {
    FinanceBillPlatform.wechat => '微信账单',
    FinanceBillPlatform.alipay => '支付宝账单',
  };
}

/// 解析后的单条账单预览项，确认后可转换为 [FinanceTransaction] 写入账本。
class FinanceBillImportItem {
  final String id;
  final FinanceBillPlatform platform;
  FinanceTransactionType type;
  final int amountMinor;
  final String transactionDate;
  final int occurredAt;
  final int timezoneOffsetMinutes;
  final String merchant;
  final String? itemDescription;
  final String? rawCategory;
  final String? rawPaymentMethod;
  final String? status;
  final String? orderId;
  final String? note;
  final bool isNeutral;
  final String? neutralReason;
  final bool isDuplicate;
  final String? duplicateReason;
  bool selected;
  String? categoryUuid;
  String? paymentMethodUuid;
  String? targetPaymentMethodUuid;

  FinanceBillImportItem({
    String? id,
    required this.platform,
    required this.type,
    required this.amountMinor,
    required this.transactionDate,
    required this.occurredAt,
    required this.timezoneOffsetMinutes,
    required this.merchant,
    this.itemDescription,
    this.rawCategory,
    this.rawPaymentMethod,
    this.status,
    this.orderId,
    this.note,
    this.isNeutral = false,
    this.neutralReason,
    this.isDuplicate = false,
    this.duplicateReason,
    bool? selected,
    this.categoryUuid,
    this.paymentMethodUuid,
    this.targetPaymentMethodUuid,
  }) : id = id ?? const Uuid().v4(),
       selected =
           selected ??
           ((!isNeutral || type == FinanceTransactionType.transfer) &&
               !isDuplicate);

  /// 组合用于展示和落库的备注信息，避免重复拼接相同文本。
  String? buildCombinedNote() {
    final parts = <String>[];
    final desc = itemDescription?.trim();
    final extraNote = note?.trim();
    if (desc != null && desc.isNotEmpty && desc != '/' && desc != merchant) {
      parts.add(desc);
    }
    if (extraNote != null &&
        extraNote.isNotEmpty &&
        extraNote != '/' &&
        extraNote != desc &&
        extraNote != merchant) {
      parts.add(extraNote);
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  FinanceTransaction toTransaction() {
    return FinanceTransaction(
      type: type,
      amountMinor: amountMinor,
      categoryUuid: categoryUuid,
      paymentMethodUuid: paymentMethodUuid,
      targetPaymentMethodUuid: type == FinanceTransactionType.transfer
          ? targetPaymentMethodUuid
          : null,
      transactionDate: transactionDate,
      occurredAt: occurredAt,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      merchant: merchant.trim().isEmpty ? null : merchant.trim(),
      note: buildCombinedNote(),
      source: FinanceEntrySource.import,
    );
  }
}

/// 账单文件解析结果。
class FinanceBillParseResult {
  final FinanceBillPlatform platform;
  final List<FinanceBillImportItem> items;
  final int skippedStatusCount;
  final int neutralCount;
  final int duplicateCount;
  final List<String> warnings;

  const FinanceBillParseResult({
    required this.platform,
    required this.items,
    this.skippedStatusCount = 0,
    this.neutralCount = 0,
    this.duplicateCount = 0,
    this.warnings = const [],
  });
}

/// 微信（CSV / XLSX）与支付宝（CSV）账单解析器。
class FinanceBillImportParser {
  static const Set<String> _closedStatuses = {
    '交易关闭',
    '已关闭',
    '等待付款',
    '未支付',
    '支付失败',
    '已撤销',
    '待付款',
  };

  /// 从文件字节解析账单并完成分类、付款方式自动匹配与重复检测。
  static FinanceBillParseResult parseBytes(
    Uint8List bytes, {
    required String fileName,
    required List<FinanceCategory> categories,
    required List<FinancePaymentMethod> paymentMethods,
    List<FinanceTransaction> existingTransactions = const [],
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('账单文件内容为空');
    }
    final lowerName = fileName.trim().toLowerCase();
    final List<List<String>> rows;
    if (lowerName.endsWith('.xlsx')) {
      rows = _parseXlsxRows(bytes);
    } else if (lowerName.endsWith('.csv') || lowerName.endsWith('.txt')) {
      final text = _decodeTextBytes(bytes);
      rows = parseCsv(text);
    } else if (_looksLikeZip(bytes)) {
      rows = _parseXlsxRows(bytes);
    } else {
      final text = _decodeTextBytes(bytes);
      rows = parseCsv(text);
    }

    return parseRows(
      rows,
      categories: categories,
      paymentMethods: paymentMethods,
      existingTransactions: existingTransactions,
    );
  }

  /// 从二维表格行解析账单，便于测试与不同文件容器复用。
  static FinanceBillParseResult parseRows(
    List<List<String>> rows, {
    required List<FinanceCategory> categories,
    required List<FinancePaymentMethod> paymentMethods,
    List<FinanceTransaction> existingTransactions = const [],
  }) {
    FinanceBillPlatform? hintedPlatform;
    var headerIndex = -1;
    Map<String, int> columns = const {};

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i].map((cell) => cell.trim()).toList();
      final joined = row.join(' ');
      if (joined.contains('微信支付')) {
        hintedPlatform = FinanceBillPlatform.wechat;
      } else if (joined.contains('支付宝')) {
        hintedPlatform = FinanceBillPlatform.alipay;
      }
      final candidateColumns = _matchHeaderColumns(row);
      if (candidateColumns != null) {
        headerIndex = i;
        columns = candidateColumns;
        break;
      }
    }

    if (headerIndex < 0) {
      throw const FormatException(
        '未识别到微信或支付宝账单表头，请确认上传的是官方导出的 CSV 或 XLSX 账单文件',
      );
    }

    final platform = hintedPlatform ?? _inferPlatformFromColumns(columns);
    final activeCategories = categories.where((c) => !c.isArchived).toList();
    final activeMethods = paymentMethods.where((m) => !m.isArchived).toList();
    final effectiveCategories = activeCategories.isNotEmpty
        ? activeCategories
        : categories;
    final effectiveMethods = activeMethods.isNotEmpty
        ? activeMethods
        : paymentMethods;

    final existingActive = existingTransactions
        .where((t) => !t.isDeleted)
        .toList();
    final seenOrderIds = <String>{};
    final items = <FinanceBillImportItem>[];
    final warnings = <String>[];
    var skippedStatusCount = 0;
    var neutralCount = 0;
    var duplicateCount = 0;
    final tzOffset = DateTime.now().timeZoneOffset.inMinutes;

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final timeRaw = _cell(row, columns['time']);
      final amountRaw = _cell(row, columns['amount']);
      if (timeRaw.isEmpty && amountRaw.isEmpty) continue;

      final parsedTime = _parseDateTime(timeRaw);
      if (parsedTime == null) {
        // 跳过文件末尾的统计或提示行
        continue;
      }

      final status = _cell(row, columns['status']);
      if (_isClosedStatus(status)) {
        skippedStatusCount++;
        continue;
      }

      final amountMinor = _parseAmountMinor(amountRaw);
      if (amountMinor == null || amountMinor <= 0) {
        skippedStatusCount++;
        continue;
      }

      final direction = _cell(row, columns['direction']);
      final rawCategory = _cell(row, columns['category']);
      final merchant = _cleanPlaceholder(_cell(row, columns['merchant']));
      final itemDescription = _cleanPlaceholder(_cell(row, columns['item']));
      final rawPaymentMethod = _cleanPlaceholder(
        _cell(row, columns['payment']),
      );
      final orderId = _cleanPlaceholder(_cell(row, columns['orderId']));
      final note = _cleanPlaceholder(_cell(row, columns['note']));

      final typeResolution = _resolveType(
        direction: direction,
        status: status,
        rawCategory: rawCategory,
        merchant: merchant,
        itemDescription: itemDescription,
        note: note,
      );

      final txDate = dateKey(parsedTime);
      final occurredAt = parsedTime.millisecondsSinceEpoch;

      final categoryUuid = _matchCategoryUuid(
        type: typeResolution.type,
        rawCategory: rawCategory,
        merchant: merchant,
        itemDescription: itemDescription,
        categories: effectiveCategories,
      );
      final paymentMethodUuid = _matchPaymentMethodUuid(
        platform: platform,
        rawPaymentMethod: rawPaymentMethod,
        paymentMethods: effectiveMethods,
      );
      final targetPaymentMethodUuid =
          typeResolution.type == FinanceTransactionType.transfer
          ? _matchTargetCampusMethodUuid(effectiveMethods)
          : null;

      String? duplicateReason;
      if (orderId != null && !seenOrderIds.add(orderId)) {
        duplicateReason = '文件内重复交易单号';
      } else {
        duplicateReason = _findDuplicateReason(
          type: typeResolution.type,
          amountMinor: amountMinor,
          transactionDate: txDate,
          occurredAt: occurredAt,
          merchant: merchant ?? '',
          orderId: orderId,
          existing: existingActive,
        );
      }

      final isDuplicate = duplicateReason != null;
      if (typeResolution.isNeutral) neutralCount++;
      if (isDuplicate) duplicateCount++;

      items.add(
        FinanceBillImportItem(
          platform: platform,
          type: typeResolution.type,
          amountMinor: amountMinor,
          transactionDate: txDate,
          occurredAt: occurredAt,
          timezoneOffsetMinutes: tzOffset,
          merchant:
              merchant ??
              itemDescription ??
              (rawCategory.isEmpty ? '未命名商户' : rawCategory),
          itemDescription: itemDescription,
          rawCategory: rawCategory.isEmpty ? null : rawCategory,
          rawPaymentMethod: rawPaymentMethod,
          status: status.isEmpty ? null : status,
          orderId: orderId,
          note: note,
          isNeutral: typeResolution.isNeutral,
          neutralReason: typeResolution.neutralReason,
          isDuplicate: isDuplicate,
          duplicateReason: duplicateReason,
          categoryUuid: categoryUuid,
          paymentMethodUuid: paymentMethodUuid,
          targetPaymentMethodUuid: targetPaymentMethodUuid,
        ),
      );
    }

    if (items.isEmpty) {
      warnings.add('未解析到可导入的有效账单记录');
    }

    return FinanceBillParseResult(
      platform: platform,
      items: items,
      skippedStatusCount: skippedStatusCount,
      neutralCount: neutralCount,
      duplicateCount: duplicateCount,
      warnings: warnings,
    );
  }

  static bool _looksLikeZip(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);
  }

  static String _decodeTextBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return utf16.decode(bytes.sublist(2));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return utf16.decode(bytes.sublist(2));
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return gbk.decode(bytes);
    }
  }

  /// RFC 4180 兼容的 CSV 解析器，支持引号转义与字段内换行。
  static List<List<String>> parseCsv(String input) {
    final rows = <List<String>>[];
    var currentRow = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          currentRow.add(buffer.toString().trim());
          buffer.clear();
        } else if (ch == '\r') {
          if (i + 1 < input.length && input[i + 1] == '\n') {
            i++;
          }
          currentRow.add(buffer.toString().trim());
          buffer.clear();
          rows.add(currentRow);
          currentRow = <String>[];
        } else if (ch == '\n') {
          currentRow.add(buffer.toString().trim());
          buffer.clear();
          rows.add(currentRow);
          currentRow = <String>[];
        } else {
          buffer.write(ch);
        }
      }
    }

    if (buffer.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(buffer.toString().trim());
      rows.add(currentRow);
    }
    return rows;
  }

  static List<List<String>> _parseXlsxRows(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('无法解压 XLSX 账单文件：$e');
    }

    ArchiveFile? sharedStringsFile;
    ArchiveFile? sheetFile;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final lower = file.name.toLowerCase();
      if (lower == 'xl/sharedstrings.xml') {
        sharedStringsFile = file;
      } else if (lower == 'xl/worksheets/sheet1.xml') {
        sheetFile = file;
      } else if (sheetFile == null &&
          lower.startsWith('xl/worksheets/sheet') &&
          lower.endsWith('.xml')) {
        sheetFile = file;
      }
    }

    if (sheetFile == null) {
      throw const FormatException('XLSX 文件中未找到工作表数据');
    }

    final sharedStrings = sharedStringsFile != null
        ? _parseSharedStrings(sharedStringsFile.content)
        : const <String>[];
    final sheetXml = utf8.decode(sheetFile.content, allowMalformed: true);
    final document = XmlDocument.parse(sheetXml);

    final rows = <List<String>>[];
    for (final rowElement in document.findAllElements('row')) {
      final rowMap = <int, String>{};
      var nextCol = 0;
      var maxCol = -1;

      for (final cell in rowElement.findElements('c')) {
        final ref = cell.getAttribute('r');
        final colIndex = ref != null ? _columnIndexFromRef(ref) : nextCol;
        nextCol = colIndex + 1;
        if (colIndex > maxCol) maxCol = colIndex;

        final type = cell.getAttribute('t');
        var value = '';
        if (type == 's') {
          final rawIdx = cell.getElement('v')?.innerText.trim();
          final idx = rawIdx != null ? int.tryParse(rawIdx) : null;
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            value = sharedStrings[idx];
          }
        } else if (type == 'inlineStr') {
          final isEl = cell.getElement('is');
          if (isEl != null) {
            value = isEl.findAllElements('t').map((e) => e.innerText).join();
          }
        } else if (type == 'b') {
          value = cell.getElement('v')?.innerText.trim() == '1'
              ? 'TRUE'
              : 'FALSE';
        } else {
          value = cell.getElement('v')?.innerText ?? '';
        }
        rowMap[colIndex] = value.trim();
      }

      if (maxCol < 0) {
        rows.add(const []);
      } else {
        rows.add(List<String>.generate(maxCol + 1, (i) => rowMap[i] ?? ''));
      }
    }
    return rows;
  }

  static List<String> _parseSharedStrings(List<int> content) {
    final xmlText = utf8.decode(content, allowMalformed: true);
    final doc = XmlDocument.parse(xmlText);
    return doc
        .findAllElements('si')
        .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  }

  static int _columnIndexFromRef(String ref) {
    var col = 0;
    for (var i = 0; i < ref.length; i++) {
      final code = ref.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 64);
      } else if (code >= 97 && code <= 122) {
        col = col * 26 + (code - 96);
      } else {
        break;
      }
    }
    return col > 0 ? col - 1 : 0;
  }

  static Map<String, int>? _matchHeaderColumns(List<String> row) {
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final h = row[i].replaceAll(RegExp(r'\s+'), '');
      if (h.isEmpty) continue;
      if (h == '交易时间' || h == '付款时间' || h == '交易创建时间') {
        map.putIfAbsent('time', () => i);
      } else if (h == '收/支') {
        map['direction'] = i;
      } else if (h == '金额(元)' || h == '金额（元）' || h == '金额') {
        map['amount'] = i;
      } else if (h == '交易分类' || h == '交易类型') {
        map.putIfAbsent('category', () => i);
      } else if (h == '交易对方') {
        map['merchant'] = i;
      } else if (h == '商品' || h == '商品说明' || h == '商品名称') {
        map['item'] = i;
      } else if (h == '支付方式' || h == '收/付款方式' || h == '付款方式') {
        map['payment'] = i;
      } else if (h == '当前状态' || h == '交易状态') {
        map['status'] = i;
      } else if (h == '交易单号' || h == '交易订单号' || h == '交易号') {
        map['orderId'] = i;
      } else if (h == '备注') {
        map['note'] = i;
      }
    }
    if (map.containsKey('time') &&
        map.containsKey('amount') &&
        map.containsKey('direction')) {
      return map;
    }
    return null;
  }

  static FinanceBillPlatform _inferPlatformFromColumns(
    Map<String, int> columns,
  ) {
    // 仅作为兜底；实际微信与支付宝表头字段几乎一致，这里按常见顺序兜底为微信。
    return columns.containsKey('category')
        ? FinanceBillPlatform.wechat
        : FinanceBillPlatform.alipay;
  }

  static String _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  static String? _cleanPlaceholder(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/' || trimmed == '-') return null;
    return trimmed;
  }

  static bool _isClosedStatus(String status) {
    if (status.isEmpty) return false;
    for (final closed in _closedStatuses) {
      if (status.contains(closed)) return true;
    }
    return false;
  }

  static DateTime? _parseDateTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    // 处理 Excel 序列号日期
    final serial = double.tryParse(value);
    if (serial != null && serial > 20000 && serial < 100000) {
      final days = serial.floor();
      final msOfDay = ((serial - days) * 86400000).round();
      return DateTime(
        1899,
        12,
        30,
      ).add(Duration(days: days, milliseconds: msOfDay));
    }

    final normalized = value.replaceAll('/', '-');
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return direct;

    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
    ).firstMatch(normalized);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '0') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
    final second = int.tryParse(match.group(6) ?? '0') ?? 0;
    return DateTime(year, month, day, hour, minute, second);
  }

  static int? _parseAmountMinor(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned
        .replaceAll('¥', '')
        .replaceAll('￥', '')
        .replaceAll(',', '')
        .replaceAll('元', '')
        .replaceAll('+', '')
        .replaceAll('-', '')
        .trim();
    return parseFinanceAmount(cleaned);
  }

  static ({FinanceTransactionType type, bool isNeutral, String? neutralReason})
  _resolveType({
    required String direction,
    required String status,
    required String rawCategory,
    required String? merchant,
    required String? itemDescription,
    required String? note,
  }) {
    final isRefundSignal =
        status.contains('退款') ||
        rawCategory.contains('退款') ||
        (itemDescription?.contains('退款') == true);
    final isCampusTransfer = _isCampusCardTransfer(
      rawCategory: rawCategory,
      merchant: merchant,
      itemDescription: itemDescription,
      note: note,
    );

    if (direction == '支出') {
      if (isCampusTransfer) {
        return (
          type: FinanceTransactionType.transfer,
          isNeutral: true,
          neutralReason: '账户互转 · 不计收支',
        );
      }
      return (
        type: FinanceTransactionType.expense,
        isNeutral: false,
        neutralReason: null,
      );
    }
    if (direction == '收入') {
      if (isRefundSignal) {
        return (
          type: FinanceTransactionType.refund,
          isNeutral: false,
          neutralReason: null,
        );
      }
      return (
        type: FinanceTransactionType.income,
        isNeutral: false,
        neutralReason: null,
      );
    }
    if (isRefundSignal && status.contains('退款成功')) {
      return (
        type: FinanceTransactionType.refund,
        isNeutral: false,
        neutralReason: null,
      );
    }
    return (
      type: isCampusTransfer
          ? FinanceTransactionType.transfer
          : FinanceTransactionType.expense,
      isNeutral: true,
      neutralReason: isCampusTransfer ? '账户互转 · 不计收支' : '不计收支',
    );
  }

  static String? _matchTargetCampusMethodUuid(
    List<FinancePaymentMethod> paymentMethods,
  ) {
    for (final method in paymentMethods) {
      final name = method.name.trim().toLowerCase();
      if (name.contains('校园卡') ||
          name.contains('一卡通') ||
          name.contains('饭卡') ||
          name.contains('餐卡')) {
        return method.uuid;
      }
    }
    return null;
  }

  /// 识别从银行卡/零钱等账户向校园卡充值的资金转移，避免与校园卡内实际消费重复计入支出。
  static bool _isCampusCardTransfer({
    required String rawCategory,
    required String? merchant,
    required String? itemDescription,
    required String? note,
  }) {
    final combined = [
      rawCategory,
      merchant ?? '',
      itemDescription ?? '',
      note ?? '',
    ].join(' ').toLowerCase();

    const directKeywords = [
      '校园卡充值',
      '校园一卡通充值',
      '一卡通充值',
      '饭卡充值',
      '餐卡充值',
      '校园卡圈存',
      '一卡通圈存',
      '校园卡转账',
    ];
    for (final keyword in directKeywords) {
      if (combined.contains(keyword)) return true;
    }

    final hasCampusSubject =
        combined.contains('校园卡') ||
        combined.contains('一卡通') ||
        combined.contains('饭卡') ||
        combined.contains('餐卡') ||
        combined.contains('完美校园') ||
        combined.contains('易校园');
    final hasTransferAction =
        combined.contains('充值') ||
        combined.contains('圈存') ||
        combined.contains('转账');
    return hasCampusSubject && hasTransferAction;
  }

  static String? _matchPaymentMethodUuid({
    required FinanceBillPlatform platform,
    required String? rawPaymentMethod,
    required List<FinancePaymentMethod> paymentMethods,
  }) {
    if (paymentMethods.isEmpty) return null;

    if (rawPaymentMethod != null && rawPaymentMethod.isNotEmpty) {
      final lower = rawPaymentMethod.toLowerCase();
      // 1. 精确或包含用户自定义/系统付款方式名称
      for (final method in paymentMethods) {
        final name = method.name.trim().toLowerCase();
        if (name.isNotEmpty && (lower == name || lower.contains(name))) {
          return method.uuid;
        }
      }
      // 2. 常见渠道关键词映射
      if (lower.contains('零钱') || lower.contains('微信')) {
        final wechat = _findMethodBySystemOrName(
          paymentMethods,
          'finance-system-payment-wechat',
          '微信',
        );
        if (wechat != null) return wechat;
      }
      if (lower.contains('花呗') ||
          lower.contains('余额宝') ||
          lower.contains('支付宝')) {
        final alipay = _findMethodBySystemOrName(
          paymentMethods,
          'finance-system-payment-alipay',
          '支付宝',
        );
        if (alipay != null) return alipay;
      }
      if (lower.contains('信用卡') || lower.contains('贷记卡')) {
        final credit = _findMethodBySystemOrName(
          paymentMethods,
          'finance-system-payment-credit',
          '信用卡',
        );
        if (credit != null) return credit;
      }
      if (lower.contains('银行') || lower.contains('储蓄卡')) {
        final bank = _findMethodBySystemOrName(
          paymentMethods,
          'finance-system-payment-bank',
          '银行卡',
        );
        if (bank != null) return bank;
      }
    }

    // 3. 平台兜底
    final fallbackSystemUuid = platform == FinanceBillPlatform.wechat
        ? 'finance-system-payment-wechat'
        : 'finance-system-payment-alipay';
    final fallbackName = platform == FinanceBillPlatform.wechat ? '微信' : '支付宝';
    return _findMethodBySystemOrName(
          paymentMethods,
          fallbackSystemUuid,
          fallbackName,
        ) ??
        paymentMethods.first.uuid;
  }

  static String? _findMethodBySystemOrName(
    List<FinancePaymentMethod> methods,
    String systemUuid,
    String name,
  ) {
    for (final m in methods) {
      if (m.uuid == systemUuid) return m.uuid;
    }
    for (final m in methods) {
      if (m.name.contains(name)) return m.uuid;
    }
    return null;
  }

  static String? _matchCategoryUuid({
    required FinanceTransactionType type,
    required String rawCategory,
    required String? merchant,
    required String? itemDescription,
    required List<FinanceCategory> categories,
  }) {
    final targetCatType = type == FinanceTransactionType.income
        ? FinanceCategoryType.income
        : FinanceCategoryType.expense;
    final scoped = categories.where((c) => c.type == targetCatType).toList();
    if (scoped.isEmpty) return null;

    if (type == FinanceTransactionType.refund) {
      for (final c in scoped) {
        if (c.uuid == 'finance-system-category-refund' || c.name == '退款') {
          return c.uuid;
        }
      }
    }

    final text = [
      rawCategory,
      merchant ?? '',
      itemDescription ?? '',
    ].join(' ').toLowerCase();

    // 1. 优先匹配子分类名称（名称更具体，避免“交通出行”抢先命中父分类“交通”）
    final subcategories = scoped.where((c) => c.parentUuid != null).toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final c in subcategories) {
      final name = c.name.trim().toLowerCase();
      if (name.length >= 2 && text.contains(name)) {
        return c.uuid;
      }
    }

    // 2. 常见商户/账单分类关键词映射
    const keywordToCategoryNames = <String, List<String>>{
      '外卖': ['外卖', '餐饮'],
      '美团': ['外卖', '餐饮'],
      '饿了么': ['外卖', '餐饮'],
      '咖啡': ['咖啡', '餐饮'],
      '星巴克': ['咖啡', '餐饮'],
      '瑞幸': ['咖啡', '餐饮'],
      '奶茶': ['奶茶', '餐饮'],
      '蜜雪': ['奶茶', '餐饮'],
      '喜茶': ['奶茶', '餐饮'],
      '霸王茶姬': ['奶茶', '餐饮'],
      '餐饮': ['餐饮'],
      '美食': ['餐饮'],
      '食堂': ['餐饮'],
      '餐厅': ['餐饮'],
      '麦当劳': ['餐饮'],
      '肯德基': ['餐饮'],
      '打车': ['打车', '交通'],
      '滴滴': ['打车', '交通'],
      '高德': ['打车', '交通'],
      '地铁': ['公交地铁', '交通'],
      '公交': ['公交地铁', '交通'],
      '乘车': ['公交地铁', '交通'],
      '12306': ['火车飞机', '交通'],
      '铁路': ['火车飞机', '交通'],
      '航空': ['火车飞机', '交通'],
      '机票': ['火车飞机', '交通'],
      '交通': ['交通'],
      '加油': ['加油', '交通'],
      '停车': ['停车', '交通'],
      '单车': ['骑行', '交通'],
      '哈啰': ['骑行', '交通'],
      '淘宝': ['网购', '购物'],
      '天猫': ['网购', '购物'],
      '京东': ['网购', '购物'],
      '拼多多': ['网购', '购物'],
      '超市': ['日用品', '购物'],
      '便利店': ['日用品', '购物'],
      '7-11': ['日用品', '购物'],
      '罗森': ['日用品', '购物'],
      '日用': ['日用品', '购物'],
      '服饰': ['服饰鞋包', '购物'],
      '数码': ['数码', '购物'],
      '苹果': ['数码', '购物'],
      '电影': ['娱乐'],
      '游戏': ['娱乐'],
      '会员': ['娱乐', '订阅'],
      '医院': ['医疗'],
      '药房': ['医疗'],
      '药店': ['医疗'],
      '医疗': ['医疗'],
      '水电': ['水电煤', '住房'],
      '电费': ['水电煤', '住房'],
      '房租': ['房租', '住房'],
      '工资': ['工资'],
      '奖金': ['奖金'],
      '红包': ['红包', '人情'],
      '理财': ['理财收益', '其他'],
      '利息': ['利息收益', '其他'],
    };

    for (final entry in keywordToCategoryNames.entries) {
      if (text.contains(entry.key)) {
        for (final targetName in entry.value) {
          for (final c in scoped) {
            if (c.name.contains(targetName)) return c.uuid;
          }
        }
      }
    }

    // 3. 匹配一级分类名称
    final topCategories = scoped.where((c) => c.parentUuid == null).toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final c in topCategories) {
      final name = c.name.trim().toLowerCase();
      if (name.length >= 2 && text.contains(name)) {
        return c.uuid;
      }
    }

    // 4. 兜底到"其他"分类
    for (final c in scoped) {
      if (c.name == '其他') return c.uuid;
    }
    return scoped.first.uuid;
  }

  static String? _findDuplicateReason({
    required FinanceTransactionType type,
    required int amountMinor,
    required String transactionDate,
    required int occurredAt,
    required String merchant,
    required String? orderId,
    required List<FinanceTransaction> existing,
  }) {
    final normalizedMerchant = merchant.trim().toLowerCase();
    for (final tx in existing) {
      if (tx.type != type ||
          tx.amountMinor != amountMinor ||
          tx.transactionDate != transactionDate) {
        continue;
      }
      if (orderId != null &&
          orderId.isNotEmpty &&
          tx.note?.contains(orderId) == true) {
        return '已导入过该交易单号';
      }
      final existingOccurredAt = tx.occurredAt;
      if (existingOccurredAt != null &&
          (existingOccurredAt - occurredAt).abs() <= 120000) {
        return '已存在相同时间与金额的账单';
      }
      final existingMerchant = tx.merchant?.trim().toLowerCase() ?? '';
      if (normalizedMerchant.isNotEmpty &&
          existingMerchant.isNotEmpty &&
          normalizedMerchant == existingMerchant) {
        return '已存在同日同商户同金额账单';
      }
    }
    return null;
  }
}
