import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../models/finance_models.dart';
import 'finance_repository.dart';
import '../../../utils/text_utils.dart';

/// 支持导入的第三方账单平台。
enum FinanceBillPlatform {
  wechat,
  alipay,
  bank,
  unionpay,
  thirdPartyApp,
  generic;

  String get label => switch (this) {
    FinanceBillPlatform.wechat => '微信账单',
    FinanceBillPlatform.alipay => '支付宝账单',
    FinanceBillPlatform.bank => '银行账单',
    FinanceBillPlatform.unionpay => '云闪付账单',
    FinanceBillPlatform.thirdPartyApp => '记账软件账单',
    FinanceBillPlatform.generic => '通用账单',
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
      merchant: AppTextUtils.trimToNull(merchant),
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

/// 多平台、多格式账单解析器（支持微信/支付宝/银行流水/云闪付/记账软件/通用表格，格式涵盖 CSV/TSV/XLSX/JSON/OFX/QFX/QIF）。
class FinanceBillImportParser {
  static const Set<String> _closedStatuses = {
    '交易关闭',
    '已关闭',
    '等待付款',
    '未支付',
    '支付失败',
    '已撤销',
    '待付款',
    '已取消',
    '失败',
    'cancelled',
    'canceled',
    'failed',
    'closed',
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
    FinanceBillPlatform? hintedPlatform;
    final List<List<String>> rows;

    if (lowerName.endsWith('.xlsx') || _looksLikeZip(bytes)) {
      final sheets = _parseXlsxSheets(bytes);
      for (final sheetRows in sheets) {
        if (_findHeaderRowIndex(sheetRows) >= 0) {
          return parseRows(
            sheetRows,
            categories: categories,
            paymentMethods: paymentMethods,
            existingTransactions: existingTransactions,
          );
        }
      }
      rows = sheets.isNotEmpty ? sheets.first : const [];
    } else {
      final text = _decodeTextBytes(bytes);
      final trimmed = text.trimLeft();
      if (lowerName.endsWith('.json') ||
          trimmed.startsWith('{') ||
          trimmed.startsWith('[')) {
        final jsonParsed = _parseJsonRows(text);
        rows = jsonParsed.rows;
        hintedPlatform = jsonParsed.platform;
      } else if (lowerName.endsWith('.qif') ||
          trimmed.toUpperCase().startsWith('!TYPE:') ||
          trimmed.toUpperCase().startsWith('!ACCOUNT')) {
        rows = _parseQifRows(text);
        hintedPlatform = FinanceBillPlatform.bank;
      } else if (lowerName.endsWith('.ofx') ||
          lowerName.endsWith('.qfx') ||
          _looksLikeOfx(trimmed)) {
        rows = _parseOfxRows(text);
        hintedPlatform = FinanceBillPlatform.bank;
      } else if (lowerName.endsWith('.tsv')) {
        rows = parseCsv(text, delimiter: '\t');
      } else {
        rows = parseDelimitedText(text);
      }
    }

    return parseRows(
      rows,
      categories: categories,
      paymentMethods: paymentMethods,
      existingTransactions: existingTransactions,
      hintedPlatform: hintedPlatform,
    );
  }

  /// 从二维表格行解析账单，便于测试与不同文件容器复用。
  static FinanceBillParseResult parseRows(
    List<List<String>> rows, {
    required List<FinanceCategory> categories,
    required List<FinancePaymentMethod> paymentMethods,
    List<FinanceTransaction> existingTransactions = const [],
    FinanceBillPlatform? hintedPlatform,
  }) {
    var detectedPlatform = hintedPlatform;
    var headerIndex = -1;
    Map<String, int> columns = const {};

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i].map((cell) => cell.trim()).toList();
      final joined = row.join(' ');
      detectedPlatform ??= _detectPlatformFromBanner(joined);
      final candidateColumns = _matchHeaderColumns(row);
      if (candidateColumns != null) {
        headerIndex = i;
        columns = candidateColumns;
        break;
      }
    }

    if (headerIndex < 0) {
      throw const FormatException(
        '未识别到有效的账单表头，请确认文件包含「交易时间/日期」和「金额」列，或上传微信、支付宝、银行、记账软件导出的 CSV / XLSX / JSON / OFX / QIF 文件',
      );
    }

    final platform = detectedPlatform ?? _inferPlatformFromColumns(columns);
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

    // 预扫描单列金额是否包含明确负号，以便在缺少“收/支”列时判断正数是否代表收入
    final hasAnyNegativeSingleAmount = _hasAnyNegativeAmount(
      rows,
      startIndex: headerIndex + 1,
      amountCol: columns['amount'],
    );

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final timeRaw = _cell(row, columns['time']);
      final timeOfDayRaw = _cell(row, columns['timeOfDay']);
      final combinedTimeRaw =
          (timeRaw.isNotEmpty &&
              timeOfDayRaw.isNotEmpty &&
              !timeRaw.contains(':'))
          ? '$timeRaw $timeOfDayRaw'
          : timeRaw;

      final amountRaw = _cell(row, columns['amount']);
      final incomeAmountRaw = _cell(row, columns['incomeAmount']);
      final expenseAmountRaw = _cell(row, columns['expenseAmount']);
      if (combinedTimeRaw.isEmpty &&
          amountRaw.isEmpty &&
          incomeAmountRaw.isEmpty &&
          expenseAmountRaw.isEmpty) {
        continue;
      }

      final parsedTime = _parseDateTime(combinedTimeRaw);
      if (parsedTime == null) {
        // 跳过文件末尾的统计或提示行
        continue;
      }

      final status = _cell(row, columns['status']);
      if (_isClosedStatus(status)) {
        skippedStatusCount++;
        continue;
      }

      final resolvedAmount = _resolveAmountAndHintedDirection(
        amountRaw: amountRaw,
        incomeAmountRaw: incomeAmountRaw,
        expenseAmountRaw: expenseAmountRaw,
        hasAnyNegativeSingleAmount: hasAnyNegativeSingleAmount,
      );
      if (resolvedAmount == null || resolvedAmount.amountMinor <= 0) {
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
      final rawTargetPaymentMethod = _cleanPlaceholder(
        _cell(row, columns['targetPayment']),
      );
      final orderId = _cleanPlaceholder(_cell(row, columns['orderId']));
      final note = _cleanPlaceholder(_cell(row, columns['note']));

      final typeResolution = _resolveType(
        direction: direction,
        amountHintDirection: resolvedAmount.hintDirection,
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
          ? (_matchTargetPaymentMethodUuid(
                  rawTargetPaymentMethod: rawTargetPaymentMethod,
                  paymentMethods: effectiveMethods,
                ) ??
                _matchTargetCampusMethodUuid(effectiveMethods))
          : null;

      String? duplicateReason;
      if (orderId != null && !seenOrderIds.add(orderId)) {
        duplicateReason = '文件内重复交易单号';
      } else {
        duplicateReason = _findDuplicateReason(
          type: typeResolution.type,
          amountMinor: resolvedAmount.amountMinor,
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
          amountMinor: resolvedAmount.amountMinor,
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

  /// 自动识别分隔符（逗号 / 制表符 / 分号）的表格文本解析器。
  static List<List<String>> parseDelimitedText(String input) {
    final delimiter = _detectDelimiter(input);
    return parseCsv(input, delimiter: delimiter);
  }

  static String _detectDelimiter(String input) {
    final lines = const LineSplitter()
        .convert(input)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(25)
        .toList();
    if (lines.isEmpty) return ',';

    var commaScore = 0;
    var tabScore = 0;
    var semiScore = 0;
    for (final line in lines) {
      commaScore += _countUnquoted(line, ',');
      tabScore += _countUnquoted(line, '\t');
      semiScore += _countUnquoted(line, ';');
    }
    if (tabScore > commaScore && tabScore >= lines.length ~/ 2 + 1) {
      return '\t';
    }
    if (semiScore > commaScore && commaScore == 0 && semiScore >= 2) {
      return ';';
    }
    return ',';
  }

  static int _countUnquoted(String line, String ch) {
    var count = 0;
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && c == ch) {
        count++;
      }
    }
    return count;
  }

  /// RFC 4180 兼容的分隔符文本解析器，支持引号转义与字段内换行。
  static List<List<String>> parseCsv(String input, {String delimiter = ','}) {
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
        } else if (ch == delimiter) {
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

  static List<List<List<String>>> _parseXlsxSheets(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('无法解压 XLSX 账单文件：$e');
    }

    ArchiveFile? sharedStringsFile;
    final sheetFiles = <ArchiveFile>[];
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final lower = file.name.toLowerCase();
      if (lower == 'xl/sharedstrings.xml') {
        sharedStringsFile = file;
      } else if (lower.startsWith('xl/worksheets/sheet') &&
          lower.endsWith('.xml')) {
        sheetFiles.add(file);
      }
    }

    if (sheetFiles.isEmpty) {
      throw const FormatException('XLSX 文件中未找到工作表数据');
    }

    sheetFiles.sort((a, b) {
      final numA = _sheetOrderNumber(a.name);
      final numB = _sheetOrderNumber(b.name);
      return numA.compareTo(numB);
    });

    final sharedStrings = sharedStringsFile != null
        ? _parseSharedStrings(sharedStringsFile.content)
        : const <String>[];

    return sheetFiles
        .map((f) => _parseSingleXlsxSheet(f, sharedStrings))
        .toList();
  }

  static int _sheetOrderNumber(String name) {
    final m = RegExp(
      r'sheet(\d+)\.xml$',
      caseSensitive: false,
    ).firstMatch(name);
    return m != null ? (int.tryParse(m.group(1)!) ?? 999) : 999;
  }

  static List<List<String>> _parseSingleXlsxSheet(
    ArchiveFile sheetFile,
    List<String> sharedStrings,
  ) {
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

  static ({List<List<String>> rows, FinanceBillPlatform? platform})
  _parseJsonRows(String text) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw FormatException('JSON 账单格式无效：$e');
    }

    FinanceBillPlatform? platform;
    List<dynamic>? rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map) {
      final metaStr = [
        decoded['platform']?.toString() ?? '',
        decoded['source']?.toString() ?? '',
        decoded['app']?.toString() ?? '',
      ].join(' ');
      platform = _detectPlatformFromBanner(metaStr);

      const candidateKeys = [
        'transactions',
        'records',
        'items',
        'bills',
        'data',
        'list',
        'rows',
        'entries',
      ];
      for (final key in candidateKeys) {
        final v = decoded[key];
        if (v is List) {
          rawList = v;
          break;
        }
      }
      if (rawList == null) {
        for (final entry in decoded.entries) {
          if (entry.value is List) {
            rawList = entry.value as List;
            break;
          }
        }
      }
      rawList ??= [decoded];
    }

    if (rawList == null || rawList.isEmpty) {
      return (rows: const [], platform: platform);
    }

    final maps = rawList.whereType<Map>().toList();
    if (maps.isEmpty) {
      // 支持二维数组形式的 JSON，例如 [["时间","金额"], ["2026-11-10","12.5"]]
      final matrix = rawList
          .whereType<List>()
          .map((r) => r.map((c) => c?.toString() ?? '').toList())
          .toList();
      return (rows: matrix, platform: platform);
    }

    final headers = <String>[];
    final headerSet = <String>{};
    for (final m in maps) {
      for (final k in m.keys) {
        final keyStr = k.toString();
        if (headerSet.add(keyStr)) {
          headers.add(keyStr);
        }
      }
    }

    final rows = <List<String>>[headers];
    for (final m in maps) {
      rows.add(
        headers.map((h) {
          final v = m[h];
          return v == null ? '' : v.toString();
        }).toList(),
      );
    }
    return (rows: rows, platform: platform ?? FinanceBillPlatform.generic);
  }

  static List<List<String>> _parseQifRows(String text) {
    final lines = const LineSplitter().convert(text);
    final rows = <List<String>>[
      ['交易时间', '金额', '交易对方', '商品说明', '交易分类', '交易单号', '支付方式', '收/支'],
    ];

    String date = '';
    String amount = '';
    String payee = '';
    String memo = '';
    String category = '';
    String refNum = '';
    String currentAccount = '';

    void flushRecord() {
      if (date.isEmpty && amount.isEmpty) return;
      var direction = '';
      var cleanCategory = category;
      var account = currentAccount;
      if (category.startsWith('[') && category.endsWith(']')) {
        direction = '转账';
        cleanCategory = '转账';
      }
      rows.add([
        date,
        amount,
        payee,
        memo,
        cleanCategory,
        refNum,
        account,
        direction,
      ]);
      date = '';
      amount = '';
      payee = '';
      memo = '';
      category = '';
      refNum = '';
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) {
        final upper = line.toUpperCase();
        if (upper.contains('CCARD')) {
          currentAccount = '信用卡';
        } else if (upper.contains('CASH')) {
          currentAccount = '现金';
        } else if (upper.contains('BANK')) {
          currentAccount = '银行卡';
        }
        continue;
      }
      if (line == '^') {
        flushRecord();
        continue;
      }
      final code = line[0];
      final val = line.substring(1).trim();
      switch (code) {
        case 'D':
          date = val;
        case 'T':
        case 'U':
          if (amount.isEmpty) amount = val;
        case 'P':
          payee = val;
        case 'M':
          memo = val;
        case 'L':
          category = val;
        case 'N':
          refNum = val;
      }
    }
    flushRecord();
    return rows;
  }

  static bool _looksLikeOfx(String trimmed) {
    final upper = trimmed.toUpperCase();
    return upper.contains('<OFX>') || upper.contains('OFXHEADER:');
  }

  static List<List<String>> _parseOfxRows(String text) {
    final rows = <List<String>>[
      ['交易时间', '金额', '交易对方', '商品说明', '交易类型', '交易单号', '支付方式', '收/支'],
    ];

    final acctTypeMatch = RegExp(
      r'<ACCTTYPE>\s*([^\r\n<]+)',
      caseSensitive: false,
    ).firstMatch(text);
    final acctIdMatch = RegExp(
      r'<ACCTID>\s*([^\r\n<]+)',
      caseSensitive: false,
    ).firstMatch(text);
    var defaultAccount = '银行卡';
    final acctType = acctTypeMatch?.group(1)?.trim().toUpperCase() ?? '';
    if (acctType == 'CREDITCARD' ||
        RegExp(r'<CCSTMTRS>', caseSensitive: false).hasMatch(text)) {
      defaultAccount = '信用卡';
    } else if (acctIdMatch != null) {
      final id = acctIdMatch.group(1)!.trim();
      final tail = id.length > 4 ? id.substring(id.length - 4) : id;
      defaultAccount = '银行卡($tail)';
    }

    final trnBlocks = RegExp(
      r'<STMTTRN>(.*?)</STMTTRN>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(text);

    for (final match in trnBlocks) {
      final block = match.group(1) ?? '';
      String extractTag(String tag) {
        final m = RegExp(
          '<$tag>\\s*([^\\r\\n<]+)',
          caseSensitive: false,
        ).firstMatch(block);
        return m?.group(1)?.trim() ?? '';
      }

      final dtPosted = extractTag('DTPOSTED');
      final trnAmt = extractTag('TRNAMT');
      if (dtPosted.isEmpty || trnAmt.isEmpty) continue;

      final trnType = extractTag('TRNTYPE').toUpperCase();
      final name = extractTag('NAME');
      final memo = extractTag('MEMO');
      final fitid = extractTag('FITID');

      var direction = '';
      if (trnType == 'XFER') {
        direction = '转账';
      } else if (trnType == 'DEBIT' ||
          trnType == 'POS' ||
          trnType == 'ATM' ||
          trnType == 'FEE' ||
          trnType == 'PAYMENT') {
        direction = '支出';
      } else if (trnType == 'CREDIT' || trnType == 'DEP' || trnType == 'INT') {
        direction = '收入';
      }

      rows.add([
        dtPosted,
        trnAmt,
        name.isNotEmpty ? name : memo,
        memo,
        trnType,
        fitid,
        defaultAccount,
        direction,
      ]);
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

  static int _findHeaderRowIndex(List<List<String>> rows) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i].map((cell) => cell.trim()).toList();
      if (_matchHeaderColumns(row) != null) return i;
    }
    return -1;
  }

  static FinanceBillPlatform? _detectPlatformFromBanner(String joined) {
    final lower = joined.toLowerCase();
    if (joined.contains('微信支付') || lower.contains('wechat')) {
      return FinanceBillPlatform.wechat;
    }
    if (joined.contains('支付宝') || lower.contains('alipay')) {
      return FinanceBillPlatform.alipay;
    }
    if (joined.contains('云闪付') ||
        joined.contains('中国银联') ||
        lower.contains('unionpay')) {
      return FinanceBillPlatform.unionpay;
    }
    const appKeywords = [
      '钱迹',
      '随手记',
      '鲨鱼记账',
      '挖财',
      '网易有钱',
      '一木记账',
      'icost',
      'timi',
      'bluecoins',
      'qianji',
    ];
    for (final k in appKeywords) {
      if (lower.contains(k)) return FinanceBillPlatform.thirdPartyApp;
    }
    const bankKeywords = [
      '招商银行',
      '工商银行',
      '建设银行',
      '农业银行',
      '中国银行',
      '交通银行',
      '浦发银行',
      '中信银行',
      '平安银行',
      '兴业银行',
      '广发银行',
      '民生银行',
      '光大银行',
      '邮储银行',
      '银行对账单',
      '银行交易流水',
      '交易流水明细',
      '活期明细',
    ];
    for (final k in bankKeywords) {
      if (joined.contains(k)) return FinanceBillPlatform.bank;
    }
    return null;
  }

  static Map<String, int>? _matchHeaderColumns(List<String> row) {
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final raw = row[i].replaceAll(RegExp(r'\s+'), '');
      if (raw.isEmpty) continue;
      final lower = raw.toLowerCase();

      // 日期/时间列
      if (raw == '交易时间' ||
          raw == '付款时间' ||
          raw == '交易创建时间' ||
          raw == '记账时间' ||
          raw == '消费时间' ||
          lower == 'datetime' ||
          lower == 'timestamp' ||
          lower == 'createdat') {
        if (map.containsKey('time') && !map.containsKey('timeOfDay')) {
          map['timeOfDay'] = i;
        } else {
          map.putIfAbsent('time', () => i);
        }
      } else if (raw == '日期' ||
          raw == '交易日期' ||
          raw == '记账日期' ||
          raw == '发生日期' ||
          raw == '账单日期' ||
          raw == '时间' ||
          lower == 'date' ||
          lower == 'time' ||
          lower == 'transactiondate' ||
          lower == 'postingdate' ||
          lower == 'transdate') {
        if (!map.containsKey('time')) {
          map['time'] = i;
        } else if ((raw == '时间' || lower == 'time') &&
            !map.containsKey('timeOfDay')) {
          map['timeOfDay'] = i;
        } else if ((raw == '日期' ||
                raw == '交易日期' ||
                raw == '记账日期' ||
                raw == '发生日期' ||
                lower == 'date' ||
                lower == 'transactiondate' ||
                lower == 'postingdate' ||
                lower == 'transdate') &&
            !map.containsKey('timeOfDay')) {
          map['timeOfDay'] = map['time']!;
          map['time'] = i;
        }
      } else if (raw == '收/支' ||
          raw == '收支' ||
          raw == '收支类型' ||
          raw == '收支方向' ||
          raw == '记账类型' ||
          raw == '借/贷' ||
          raw == '借贷标志' ||
          lower == 'direction' ||
          lower == 'drcr' ||
          lower == 'type') {
        map['direction'] = i;
      } else if (raw == '收入金额' ||
          raw == '存入金额' ||
          raw == '贷方发生额' ||
          raw == '贷方金额' ||
          raw == '收入' ||
          raw == '收入(元)' ||
          raw == '收入（元）' ||
          lower == 'credit' ||
          lower == 'deposit' ||
          lower == 'inflow') {
        map['incomeAmount'] = i;
      } else if (raw == '支出金额' ||
          raw == '支取金额' ||
          raw == '借方发生额' ||
          raw == '借方金额' ||
          raw == '支出' ||
          raw == '支出(元)' ||
          raw == '支出（元）' ||
          lower == 'debit' ||
          lower == 'withdrawal' ||
          lower == 'outflow') {
        map['expenseAmount'] = i;
      } else if (raw == '金额(元)' ||
          raw == '金额（元）' ||
          raw == '金额' ||
          raw == '交易金额' ||
          raw == '交易金额(元)' ||
          raw == '交易金额（元）' ||
          raw == '发生额' ||
          raw == '记账金额' ||
          raw == '实付金额' ||
          lower == 'amount' ||
          lower == 'total' ||
          lower == 'value' ||
          lower == 'money') {
        map.putIfAbsent('amount', () => i);
      } else if (raw == '交易分类' ||
          raw == '分类' ||
          raw == '类别' ||
          raw == '账目分类' ||
          raw == '一级分类' ||
          lower == 'category') {
        map.putIfAbsent('category', () => i);
      } else if (raw == '交易类型' || raw == '类型' || raw == '业务类型') {
        map.putIfAbsent('category', () => i);
        map.putIfAbsent('direction', () => i);
      } else if (raw == '交易对方' ||
          raw == '商户' ||
          raw == '商户名称' ||
          raw == '商家' ||
          raw == '交易对象' ||
          raw == '对方户名' ||
          raw == '对方账号名称' ||
          lower == 'merchant' ||
          lower == 'payee' ||
          lower == 'counterparty') {
        map.putIfAbsent('merchant', () => i);
      } else if (raw == '商品' ||
          raw == '商品说明' ||
          raw == '商品名称' ||
          raw == '交易摘要' ||
          raw == '摘要' ||
          raw == '内容' ||
          raw == '项目' ||
          lower == 'description' ||
          lower == 'item' ||
          lower == 'title' ||
          lower == 'summary' ||
          lower == 'name') {
        map.putIfAbsent('item', () => i);
      } else if (raw == '支付方式' ||
          raw == '收/付款方式' ||
          raw == '付款方式' ||
          raw == '账户' ||
          raw == '账户1' ||
          raw == '转出账户' ||
          raw == '交易账户' ||
          raw == '卡号' ||
          raw == '交易卡号' ||
          lower == 'account' ||
          lower == 'payment' ||
          lower == 'paymentmethod' ||
          lower == 'card') {
        map.putIfAbsent('payment', () => i);
      } else if (raw == '账户2' ||
          raw == '转入账户' ||
          raw == '目标账户' ||
          raw == '对方账户' ||
          lower == 'targetaccount' ||
          lower == 'toaccount') {
        map.putIfAbsent('targetPayment', () => i);
      } else if (raw == '当前状态' ||
          raw == '交易状态' ||
          raw == '状态' ||
          lower == 'status' ||
          lower == 'state') {
        map.putIfAbsent('status', () => i);
      } else if (raw == '交易单号' ||
          raw == '交易订单号' ||
          raw == '交易号' ||
          raw == '订单号' ||
          raw == '流水号' ||
          raw == '交易流水号' ||
          lower == 'orderid' ||
          lower == 'transactionid' ||
          lower == 'fitid' ||
          lower == 'id') {
        map.putIfAbsent('orderId', () => i);
      } else if (raw == '备注' ||
          raw == '附言' ||
          raw == '交易附言' ||
          raw == '说明' ||
          raw == '标签' ||
          lower == 'note' ||
          lower == 'notes' ||
          lower == 'memo' ||
          lower == 'remark' ||
          lower == 'comment' ||
          lower == 'tag') {
        map.putIfAbsent('note', () => i);
      }
    }

    final hasAmount =
        map.containsKey('amount') ||
        map.containsKey('incomeAmount') ||
        map.containsKey('expenseAmount');
    if (map.containsKey('time') && hasAmount) {
      return map;
    }
    return null;
  }

  static FinanceBillPlatform _inferPlatformFromColumns(
    Map<String, int> columns,
  ) {
    if (columns.containsKey('incomeAmount') ||
        columns.containsKey('expenseAmount')) {
      return FinanceBillPlatform.bank;
    }
    if (columns.containsKey('targetPayment')) {
      return FinanceBillPlatform.thirdPartyApp;
    }
    if (columns.containsKey('status') && columns.containsKey('orderId')) {
      return columns.containsKey('category')
          ? FinanceBillPlatform.wechat
          : FinanceBillPlatform.alipay;
    }
    return FinanceBillPlatform.generic;
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
    final lower = status.toLowerCase();
    for (final closed in _closedStatuses) {
      if (lower.contains(closed.toLowerCase())) return true;
    }
    return false;
  }

  static DateTime? _parseDateTime(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    // 1. 处理 Excel 序列号日期
    final serial = double.tryParse(value);
    if (serial != null) {
      if (serial > 20000 && serial < 100000) {
        final days = serial.floor();
        final msOfDay = ((serial - days) * 86400000).round();
        return DateTime(
          1899,
          12,
          30,
        ).add(Duration(days: days, milliseconds: msOfDay));
      }
      // Unix 时间戳（秒或毫秒）
      if (serial >= 1000000000000 && serial <= 9999999999999) {
        return DateTime.fromMillisecondsSinceEpoch(serial.round());
      }
      if (serial >= 1000000000 &&
          serial <= 9999999999 &&
          !value.contains('.')) {
        return DateTime.fromMillisecondsSinceEpoch(serial.round() * 1000);
      }
    }

    // 2. 紧凑数字格式（银行流水 / OFX 常见：20261110 或 20261110123000）
    final ofxOrCompact = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:(\d{2})(\d{2})(\d{2})?)?',
    ).firstMatch(value);
    if (ofxOrCompact != null &&
        !value.contains('-') &&
        !value.contains('/') &&
        !value.contains('.')) {
      final year = int.parse(ofxOrCompact.group(1)!);
      final month = int.parse(ofxOrCompact.group(2)!);
      final day = int.parse(ofxOrCompact.group(3)!);
      final hour = int.tryParse(ofxOrCompact.group(4) ?? '0') ?? 0;
      final minute = int.tryParse(ofxOrCompact.group(5) ?? '0') ?? 0;
      final second = int.tryParse(ofxOrCompact.group(6) ?? '0') ?? 0;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day, hour, minute, second);
      }
    }

    // 3. 中文日期格式：2026年11月10日 12:30:00
    final cnMatch = RegExp(
      r'^(\d{4})年(\d{1,2})月(\d{1,2})日(?:\s*(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
    ).firstMatch(value);
    if (cnMatch != null) {
      return DateTime(
        int.parse(cnMatch.group(1)!),
        int.parse(cnMatch.group(2)!),
        int.parse(cnMatch.group(3)!),
        int.tryParse(cnMatch.group(4) ?? '0') ?? 0,
        int.tryParse(cnMatch.group(5) ?? '0') ?? 0,
        int.tryParse(cnMatch.group(6) ?? '0') ?? 0,
      );
    }

    // 4. QIF / 美式日期：MM/DD/YYYY 或 MM/DD'YY
    final usMatch = RegExp(
      r"^(\d{1,2})/(\d{1,2})[/'](\d{2,4})(?:\s+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?$",
    ).firstMatch(value);
    if (usMatch != null) {
      var year = int.parse(usMatch.group(3)!);
      if (year < 100) year += 2000;
      final month = int.parse(usMatch.group(1)!);
      final day = int.parse(usMatch.group(2)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(
          year,
          month,
          day,
          int.tryParse(usMatch.group(4) ?? '0') ?? 0,
          int.tryParse(usMatch.group(5) ?? '0') ?? 0,
          int.tryParse(usMatch.group(6) ?? '0') ?? 0,
        );
      }
    }

    // 5. 标准 YYYY-MM-DD / YYYY/MM/DD / YYYY.MM.DD
    final normalized = value.replaceAll('/', '-').replaceAll('.', '-');
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return direct.toLocal();

    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T\s]+(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?',
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

  static bool _hasAnyNegativeAmount(
    List<List<String>> rows, {
    required int startIndex,
    required int? amountCol,
  }) {
    if (amountCol == null) return false;
    for (var i = startIndex; i < rows.length; i++) {
      final raw = _cell(rows[i], amountCol);
      final parsed = _parseSignedAmountMinor(raw);
      if (parsed != null && parsed.isNegative) return true;
    }
    return false;
  }

  static ({int amountMinor, String hintDirection})?
  _resolveAmountAndHintedDirection({
    required String amountRaw,
    required String incomeAmountRaw,
    required String expenseAmountRaw,
    required bool hasAnyNegativeSingleAmount,
  }) {
    final incomeParsed = _parseSignedAmountMinor(incomeAmountRaw);
    final expenseParsed = _parseSignedAmountMinor(expenseAmountRaw);
    if (incomeParsed != null && incomeParsed.amountMinor > 0) {
      return (amountMinor: incomeParsed.amountMinor, hintDirection: '收入');
    }
    if (expenseParsed != null && expenseParsed.amountMinor > 0) {
      return (amountMinor: expenseParsed.amountMinor, hintDirection: '支出');
    }

    final singleParsed = _parseSignedAmountMinor(amountRaw);
    if (singleParsed == null || singleParsed.amountMinor <= 0) return null;
    if (singleParsed.isNegative) {
      return (amountMinor: singleParsed.amountMinor, hintDirection: '支出');
    }
    if (singleParsed.hasExplicitPlus || hasAnyNegativeSingleAmount) {
      return (amountMinor: singleParsed.amountMinor, hintDirection: '收入');
    }
    return (amountMinor: singleParsed.amountMinor, hintDirection: '');
  }

  static ({int amountMinor, bool isNegative, bool hasExplicitPlus})?
  _parseSignedAmountMinor(String raw) {
    var cleaned = raw.trim();
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '--') return null;

    var isNegative = false;
    var hasExplicitPlus = false;
    if (cleaned.startsWith('(') && cleaned.endsWith(')')) {
      isNegative = true;
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    if (cleaned.contains('-')) {
      isNegative = true;
    } else if (cleaned.contains('+')) {
      hasExplicitPlus = true;
    }

    cleaned = cleaned
        .replaceAll(
          RegExp(r'\b(CNY|RMB|USD|HKD|EUR|GBP|JPY)\b', caseSensitive: false),
          '',
        )
        .replaceAll('¥', '')
        .replaceAll('￥', '')
        .replaceAll('\$', '')
        .replaceAll('€', '')
        .replaceAll('£', '')
        .replaceAll(',', '')
        .replaceAll('元', '')
        .replaceAll('+', '')
        .replaceAll('-', '')
        .trim();
    final minor = parseFinanceAmount(cleaned);
    if (minor == null) return null;
    return (
      amountMinor: minor,
      isNegative: isNegative,
      hasExplicitPlus: hasExplicitPlus,
    );
  }

  static ({FinanceTransactionType type, bool isNeutral, String? neutralReason})
  _resolveType({
    required String direction,
    required String amountHintDirection,
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

    final dirLower = direction.trim().toLowerCase();
    final isTransferDir =
        dirLower == '转账' ||
        dirLower == '转出' ||
        dirLower == '转入' ||
        dirLower == '账户互转' ||
        dirLower == 'transfer' ||
        dirLower == 'xfer';
    final isExpenseDir =
        dirLower == '支出' ||
        dirLower == '支' ||
        dirLower == '借' ||
        dirLower == '借方' ||
        dirLower == '借记' ||
        dirLower == '付款' ||
        dirLower == '消费' ||
        dirLower == 'expense' ||
        dirLower == 'debit' ||
        dirLower == 'out' ||
        dirLower == 'outflow' ||
        dirLower == 'dr' ||
        dirLower == 'payment';
    final isIncomeDir =
        dirLower == '收入' ||
        dirLower == '收' ||
        dirLower == '贷' ||
        dirLower == '贷方' ||
        dirLower == '贷记' ||
        dirLower == '收款' ||
        dirLower == '入账' ||
        dirLower == 'income' ||
        dirLower == 'credit' ||
        dirLower == 'in' ||
        dirLower == 'inflow' ||
        dirLower == 'cr' ||
        dirLower == 'deposit';
    final isRefundDir = dirLower == '退款' || dirLower == 'refund';
    final isNeutralDir =
        dirLower == '不计收支' ||
        dirLower == '中性交易' ||
        dirLower == 'neutral' ||
        dirLower == 'ignore';

    if (isTransferDir) {
      return (
        type: FinanceTransactionType.transfer,
        isNeutral: true,
        neutralReason: '账户互转 · 不计收支',
      );
    }
    if (isRefundDir || (isRefundSignal && status.contains('退款成功'))) {
      return (
        type: FinanceTransactionType.refund,
        isNeutral: false,
        neutralReason: null,
      );
    }
    if (isExpenseDir) {
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
    if (isIncomeDir) {
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
    if (isNeutralDir) {
      return (
        type: isCampusTransfer
            ? FinanceTransactionType.transfer
            : FinanceTransactionType.expense,
        isNeutral: true,
        neutralReason: isCampusTransfer ? '账户互转 · 不计收支' : '不计收支',
      );
    }

    // 未提供收/支列或为其他文本时，结合金额符号与上下文兜底
    if (amountHintDirection == '收入') {
      return (
        type: isRefundSignal
            ? FinanceTransactionType.refund
            : FinanceTransactionType.income,
        isNeutral: false,
        neutralReason: null,
      );
    }
    if (amountHintDirection == '支出') {
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

    if (isCampusTransfer) {
      return (
        type: FinanceTransactionType.transfer,
        isNeutral: true,
        neutralReason: '账户互转 · 不计收支',
      );
    }

    // 无符号通用表格（如纯正数列表）：根据分类/摘要判断收入或默认支出
    final combinedHint = '$rawCategory ${itemDescription ?? ''} ${note ?? ''}'
        .toLowerCase();
    if (combinedHint.contains('工资') ||
        combinedHint.contains('奖金') ||
        combinedHint.contains('薪资') ||
        combinedHint.contains('报销') ||
        combinedHint.contains('分红') ||
        combinedHint.contains('利息') ||
        combinedHint.contains('salary') ||
        combinedHint.contains('payroll')) {
      return (
        type: FinanceTransactionType.income,
        isNeutral: false,
        neutralReason: null,
      );
    }
    if (isRefundSignal) {
      return (
        type: FinanceTransactionType.refund,
        isNeutral: false,
        neutralReason: null,
      );
    }

    return (
      type: FinanceTransactionType.expense,
      isNeutral: false,
      neutralReason: null,
    );
  }

  static String? _matchTargetPaymentMethodUuid({
    required String? rawTargetPaymentMethod,
    required List<FinancePaymentMethod> paymentMethods,
  }) {
    if (rawTargetPaymentMethod == null ||
        rawTargetPaymentMethod.trim().isEmpty ||
        paymentMethods.isEmpty) {
      return null;
    }
    return _matchPaymentMethodByText(
      rawTargetPaymentMethod.trim(),
      paymentMethods,
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
      final matched = _matchPaymentMethodByText(
        rawPaymentMethod,
        paymentMethods,
      );
      if (matched != null) return matched;
    }

    // 3. 平台兜底
    final (fallbackSystemUuid, fallbackName) = switch (platform) {
      FinanceBillPlatform.wechat => ('finance-system-payment-wechat', '微信'),
      FinanceBillPlatform.alipay => ('finance-system-payment-alipay', '支付宝'),
      FinanceBillPlatform.bank ||
      FinanceBillPlatform.unionpay => ('finance-system-payment-bank', '银行卡'),
      FinanceBillPlatform.thirdPartyApp ||
      FinanceBillPlatform.generic => ('', ''),
    };
    if (fallbackSystemUuid.isNotEmpty) {
      final found = _findMethodBySystemOrName(
        paymentMethods,
        fallbackSystemUuid,
        fallbackName,
      );
      if (found != null) return found;
    }
    return paymentMethods.first.uuid;
  }

  static String? _matchPaymentMethodByText(
    String rawPaymentMethod,
    List<FinancePaymentMethod> paymentMethods,
  ) {
    final lower = rawPaymentMethod.toLowerCase();
    // 1. 精确或包含用户自定义/系统付款方式名称
    for (final method in paymentMethods) {
      final name = method.name.trim().toLowerCase();
      if (name.isNotEmpty && (lower == name || lower.contains(name))) {
        return method.uuid;
      }
    }
    // 2. 常见渠道关键词映射
    if (lower.contains('零钱') ||
        lower.contains('微信') ||
        lower.contains('wechat')) {
      final wechat = _findMethodBySystemOrName(
        paymentMethods,
        'finance-system-payment-wechat',
        '微信',
      );
      if (wechat != null) return wechat;
    }
    if (lower.contains('花呗') ||
        lower.contains('余额宝') ||
        lower.contains('支付宝') ||
        lower.contains('alipay')) {
      final alipay = _findMethodBySystemOrName(
        paymentMethods,
        'finance-system-payment-alipay',
        '支付宝',
      );
      if (alipay != null) return alipay;
    }
    if (lower.contains('现金') || lower.contains('cash')) {
      final cash = _findMethodBySystemOrName(
        paymentMethods,
        'finance-system-payment-cash',
        '现金',
      );
      if (cash != null) return cash;
    }
    if (lower.contains('信用卡') ||
        lower.contains('贷记卡') ||
        lower.contains('credit') ||
        lower.contains('visa') ||
        lower.contains('mastercard')) {
      final credit = _findMethodBySystemOrName(
        paymentMethods,
        'finance-system-payment-credit',
        '信用卡',
      );
      if (credit != null) return credit;
    }
    if (lower.contains('银行') ||
        lower.contains('储蓄卡') ||
        lower.contains('借记卡') ||
        lower.contains('银联') ||
        lower.contains('云闪付') ||
        lower.contains('debit') ||
        lower.contains('checking') ||
        lower.contains('savings')) {
      final bank = _findMethodBySystemOrName(
        paymentMethods,
        'finance-system-payment-bank',
        '银行卡',
      );
      if (bank != null) return bank;
    }
    return null;
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
