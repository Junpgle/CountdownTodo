import '../models.dart';

// 新增：文本切片类型，方便 UI 高亮显示
enum SegmentType { text, time, location, recurrence, duration }

// 新增：文本切片对象
class TodoSegment {
  final String text;
  final SegmentType type;
  TodoSegment(this.text, this.type);
}

class ParsedTodoResult {
  String title;
  String? remark;
  bool isAllDay;
  DateTime? startTime;
  DateTime? endTime;
  RecurrenceType recurrence;
  int? customIntervalDays;
  DateTime? recurrenceEndDate;
  bool isValid;
  List<TodoSegment> segments; // 新增：保存整句被切割后的分片明细
  String? originalText;      // 📄 原始分析文本

  ParsedTodoResult({
    required this.title,
    this.remark,
    this.isAllDay = false,
    this.startTime,
    this.endTime,
    this.recurrence = RecurrenceType.none,
    this.customIntervalDays,
    this.recurrenceEndDate,
    this.isValid = true,
    this.segments = const [],
    this.originalText,
  });

  bool get hasContent => title.isNotEmpty;
}

// 内部使用的记录坐标类
class _MatchedSpan {
  final int start;
  final int end;
  final String text;
  final SegmentType type;
  _MatchedSpan(this.start, this.end, this.text, this.type);
}

class TodoParserService {
  // ══════════════════════════════════════════════
  // 公共入口
  // ══════════════════════════════════════════════
  static List<ParsedTodoResult> parseMulti(String input) {
    if (input.trim().isEmpty) return [];

    final results = <ParsedTodoResult>[];
    final sentences = _splitIntoSentences(input);

    for (var sentence in sentences) {
      if (sentence.trim().isEmpty) continue;
      final result = parse(sentence.trim());
      if (result.isValid && result.hasContent) {
        results.add(result);
      }
    }

    if (results.isEmpty && input.trim().isNotEmpty) {
      results.add(ParsedTodoResult(
        title: input.trim(),
        isValid: true,
        segments: [TodoSegment(input.trim(), SegmentType.text)],
      ));
    }

    return results;
  }

  static List<String> _splitIntoSentences(String input) {
    final sentences = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < input.length; i++) {
      final remaining = input.substring(i);
      final sepLen = _sentenceSeparatorLength(remaining);
      if (sepLen > 0) {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) sentences.add(segment);
        buffer.clear();
        i += sepLen - 1;
      } else {
        buffer.write(input[i]);
      }
    }

    final last = buffer.toString().trim();
    if (last.isNotEmpty) sentences.add(last);

    return sentences;
  }

  static int _sentenceSeparatorLength(String remaining) {
    const singles = ['；', ';', '\n'];
    for (final s in singles) {
      if (remaining.startsWith(s)) return s.length;
    }
    const phrases = [
      '，然后', '，还有', '，另外', '、然后', '、还有', '、另外',
      '，接着', '，再', ',然后', ',还有', '然后',
    ];
    for (final p in phrases) {
      if (remaining.startsWith(p)) return p.length;
    }
    return 0;
  }

  // ══════════════════════════════════════════════
  // 核心提取逻辑：基于区间蒙版（Masking）彻底分离各部分
  // ══════════════════════════════════════════════
  static ParsedTodoResult parse(String input) {
    String original = input.trim();
    if (original.isEmpty) return ParsedTodoResult(title: '', isValid: false);

    // masked 蒙版：提取过的部分变成等长的空格，防止重叠匹配且保持原下标坐标不变
    String masked = original;
    List<_MatchedSpan> spans = [];

    // 蒙版函数
    void applyMask(Match m, SegmentType type) {
      spans.add(_MatchedSpan(m.start, m.end, original.substring(m.start, m.end), type));
      masked = masked.replaceRange(m.start, m.end, ' ' * (m.end - m.start));
    }

    String? remark;
    RecurrenceType recurrence = RecurrenceType.none;
    int? customIntervalDays;
    DateTime? recurrenceEndDate;
    int? durationMin;
    DateTime? parsedDate;
    String? timePrefixHint; // 用于传递 "明晚" 隐含的 "晚上"
    bool hasTimeInfo = false;
    DateTime? startTime;
    DateTime? endTime;
    bool isAllDay = false;

    // 保存原始文本（如果外部没传）
    String? currentOriginalText = original;

    // 1. 提取地点 / 备注 (Location)
    final atMatch = RegExp(r'@(\S+)').firstMatch(masked);
    if (atMatch != null) {
      remark = atMatch.group(1)!;
      applyMask(atMatch, SegmentType.location);
    } else {
      final locPatterns = [
        RegExp(r'在([\u4e00-\u9fa5]{2,10}(?:图书馆|教室|办公室|会议室|学校|公司|食堂|超市|公园|医院|餐厅|咖啡厅|酒店|机场|车站|广场|体育馆|商场|社区|中心|家里|家|店里|楼上|楼下))'),
        RegExp(r'地点[：:]\s*([^\s，,。！!]{1,20})'),
        RegExp(r'备注[：:]\s*([^\s，,。！!]{1,30})'),
      ];
      for (var p in locPatterns) {
        final m = p.firstMatch(masked);
        if (m != null) {
          remark = m.groupCount >= 1 ? m.group(1) : m.group(0);
          applyMask(m, SegmentType.location);
          break;
        }
      }
    }

    // 2. 提取重复规则 (Recurrence)
    final recPatterns = [
      (RegExp(r'每天|天天|每日'), RecurrenceType.daily, 0),
      (RegExp(r'每周|每星期|每礼拜'), RecurrenceType.weekly, 0),
      (RegExp(r'每月|每个月'), RecurrenceType.monthly, 0),
      (RegExp(r'每一年|每年'), RecurrenceType.yearly, 0),
      (RegExp(r'工作日|周一到周五|星期一至星期五'), RecurrenceType.weekdays, 0),
      (RegExp(r'每两天|隔一天|每隔一天'), RecurrenceType.customDays, 2),
      (RegExp(r'(?<num>\d+)\s*天\s*一次'), RecurrenceType.customDays, -1),
      (RegExp(r'(?<num>\d+)\s*周\s*一次'), RecurrenceType.customDays, -7),
    ];
    for (var p in recPatterns) {
      final m = p.$1.firstMatch(masked);
      if (m != null) {
        recurrence = p.$2;
        if (p.$3 == -1) {
          customIntervalDays = int.tryParse(m.namedGroup('num') ?? '');
        } else if (p.$3 == -7) {
          customIntervalDays = (int.tryParse(m.namedGroup('num') ?? '') ?? 1) * 7;
        } else if (p.$3 > 0) {
          customIntervalDays = p.$3;
        }
        applyMask(m, SegmentType.recurrence);
        break;
      }
    }

    // 3. 提取重复结束 (Recurrence End)
    if (recurrence != RecurrenceType.none) {
      final udm = RegExp(r'(?:直到|到)\s*(?<y>\d{4}年)?(?<m>\d{1,2})月(?<d>\d{1,2})(?:日|号)?').firstMatch(masked);
      if (udm != null) {
        final yStr = udm.namedGroup('y');
        final year = yStr != null ? int.parse(yStr.replaceAll('年', '')) : DateTime.now().year;
        recurrenceEndDate = DateTime(year, int.parse(udm.namedGroup('m')!), int.parse(udm.namedGroup('d')!));
        applyMask(udm, SegmentType.recurrence);
      }
    }

    // 4. 提取时长 (Duration)
    final durCombined = RegExp(r'(?<h>\d+(?:\.\d+)?)\s*小时\s*(?<m>\d+)\s*分钟?').firstMatch(masked);
    if (durCombined != null) {
      durationMin = (double.parse(durCombined.namedGroup('h')!) * 60).round() + int.parse(durCombined.namedGroup('m')!);
      applyMask(durCombined, SegmentType.duration);
    } else {
      final durHours = RegExp(r'(?<h>\d+(?:\.\d+)?|一|二|两|三|四|半)\s*个?小时').firstMatch(masked);
      if (durHours != null) {
        durationMin = (_parseCnNum(durHours.namedGroup('h')!) * 60).round();
        applyMask(durHours, SegmentType.duration);
      } else {
        final durHalf = RegExp(r'半小时').firstMatch(masked);
        if (durHalf != null) {
          durationMin = 30;
          applyMask(durHalf, SegmentType.duration);
        } else {
          final durMins = RegExp(r'(?<m>\d+)\s*分钟').firstMatch(masked);
          if (durMins != null) {
            durationMin = int.parse(durMins.namedGroup('m')!);
            applyMask(durMins, SegmentType.duration);
          }
        }
      }
    }

    // 5. 提取单独的日期 (Date) - 独立剥离，不受时间影响
    final relDate = RegExp(r'(今天|今日|今早|今晚|明天|明日|明早|明晚|后天|后日|后早|后晚)').firstMatch(masked);
    if (relDate != null) {
      final str = relDate.group(1)!;
      if (str.endsWith('早')) timePrefixHint = '早上';
      if (str.endsWith('晚')) timePrefixHint = '晚上';
      parsedDate = _parseRelativeDay(str);
      applyMask(relDate, SegmentType.time);
    } else {
      final nDays = RegExp(r'(?<num>\d+|一|二|两|三|四|五|六|七|八|九|十)\s*天\s*后').firstMatch(masked);
      if (nDays != null) {
        int v = _parseCnNum(nDays.namedGroup('num')!).toInt();
        parsedDate = DateTime.now().add(Duration(days: v));
        applyMask(nDays, SegmentType.time);
      } else {
        final weekday = RegExp(r'(?<next>下周|这周)?(?:周|星期)(?<day>一|二|三|四|五|六|日|天)').firstMatch(masked);
        if (weekday != null) {
          parsedDate = _getWeekdayDate(_weekdayCharToInt(weekday.namedGroup('day')!), weekday.namedGroup('next') == '下周');
          applyMask(weekday, SegmentType.time);
        } else {
          // 修改点1: 确保所有的提取分组 (<y>, <m>, <d>) 都存在于每个表达式中，避免 namedGroup('y') 抛出异常
          final specificPatterns = [
            RegExp(r'(?:(?<y>\d{4})年)?(?<m>\d{1,2})\s*月\s*(?<d>\d{1,2})(?:日|号)?'),
            RegExp(r'(?<y>\d{4})[/\-](?<m>\d{1,2})[/\-](?<d>\d{1,2})'),
          ];
          for (var p in specificPatterns) {
            final m = p.firstMatch(masked);
            if (m != null) {
              final now = DateTime.now();
              int month = int.parse(m.namedGroup('m')!);
              int day = int.parse(m.namedGroup('d')!);
              int year = m.namedGroup('y') != null
                  ? int.parse(m.namedGroup('y')!)
                  : ((month < now.month || (month == now.month && day < now.day)) ? now.year + 1 : now.year);
              parsedDate = DateTime(year, month, day);
              applyMask(m, SegmentType.time);
              break;
            }
          }
        }
      }
    }

    // 6. 提取时间段 / 单一时间 (Time)
    RegExpMatch? timeRangeMatch;
    final trPatterns = [
      RegExp(r'(?<p1>上午|下午|早上|晚上|中午|凌晨)?\s*(?<sh>\d{1,2})[点时](?:(?<sm>\d{1,2})分?)?\s*(?:到|至|-|~)\s*(?<p2>上午|下午|早上|晚上|中午|凌晨)?\s*(?<eh>\d{1,2})[点时](?:(?<em>\d{1,2})分?)?'),
      RegExp(r'(?<p1>上午|下午|早上|晚上|中午|凌晨)?\s*(?<sh>\d{1,2}):(?<sm>\d{2})\s*(?:到|至|-|~)\s*(?<p2>上午|下午|早上|晚上|中午|凌晨)?\s*(?<eh>\d{1,2}):(?<em>\d{2})'),
    ];
    for (var p in trPatterns) {
      timeRangeMatch = p.firstMatch(masked);
      if (timeRangeMatch != null) break;
    }

    RegExpMatch? singleTimeMatch;
    if (timeRangeMatch != null) {
      hasTimeInfo = true;
      applyMask(timeRangeMatch, SegmentType.time);
    } else {
      // 修改点2: 将前缀 <p1> 改为可选，统一匹配有前缀和无前缀的时间，确保 <p1> 这个捕获组总是存在。
      final stPatterns = [
        RegExp(r'(?<p1>上午|早上|中午|下午|晚上|凌晨)?\s*(?<sh>\d{1,2})[点时](?:(?<sm>\d{1,2})分?)?'),
        RegExp(r'(?<p1>上午|早上|中午|下午|晚上|凌晨)?\s*(?<sh>\d{1,2}):(?<sm>\d{2})'),
      ];
      for (var p in stPatterns) {
        singleTimeMatch = p.firstMatch(masked);
        if (singleTimeMatch != null) break;
      }
      if (singleTimeMatch != null) {
        hasTimeInfo = true;
        applyMask(singleTimeMatch, SegmentType.time);
      }
    }

    // ================= 组合与计算结果 =================
    final now = DateTime.now();
    DateTime baseDate = parsedDate ?? DateTime(now.year, now.month, now.day);

    if (hasTimeInfo) {
      if (timeRangeMatch != null) {
        String? p1 = timeRangeMatch.namedGroup('p1') ?? timePrefixHint;
        int sH = int.parse(timeRangeMatch.namedGroup('sh')!);
        int sM = int.tryParse(timeRangeMatch.namedGroup('sm') ?? '') ?? 0;

        String? p2 = timeRangeMatch.namedGroup('p2') ?? p1;
        int eH = int.parse(timeRangeMatch.namedGroup('eh')!);
        int eM = int.tryParse(timeRangeMatch.namedGroup('em') ?? '') ?? 0;

        sH = _adjustHour(p1, sH);
        eH = _adjustHour(p2, eH);

        startTime = DateTime(baseDate.year, baseDate.month, baseDate.day, sH, sM);
        endTime = DateTime(baseDate.year, baseDate.month, baseDate.day, eH, eM);
        if (endTime.isBefore(startTime)) endTime = endTime.add(const Duration(days: 1));
      } else if (singleTimeMatch != null) {
        String? p1 = singleTimeMatch.namedGroup('p1') ?? timePrefixHint;
        int sH = int.parse(singleTimeMatch.namedGroup('sh')!);
        int sM = int.tryParse(singleTimeMatch.namedGroup('sm') ?? '') ?? 0;
        sH = _adjustHour(p1, sH);
        startTime = DateTime(baseDate.year, baseDate.month, baseDate.day, sH, sM);
      }
    } else if (parsedDate != null) {
      isAllDay = true;
      startTime = DateTime(baseDate.year, baseDate.month, baseDate.day, 0, 0);
    }

    // 根据时长补全 EndTime
    if (startTime != null && !isAllDay && endTime == null) {
      if (durationMin != null) {
        endTime = startTime.add(Duration(minutes: durationMin));
      } else {
        endTime = startTime.add(const Duration(hours: 1)); // 默认给 1 小时
      }
    }

    // ================= 组装切片 (Segments) =================
    spans.sort((a, b) => a.start.compareTo(b.start));
    List<TodoSegment> finalSegments = [];
    int cursor = 0;

    for (var span in spans) {
      if (span.start > cursor) {
        String chunk = original.substring(cursor, span.start);
        if (chunk.trim().isNotEmpty) {
          finalSegments.add(TodoSegment(chunk, SegmentType.text));
        }
      }
      finalSegments.add(TodoSegment(span.text, span.type));
      cursor = span.end;
    }
    if (cursor < original.length) {
      String chunk = original.substring(cursor);
      if (chunk.trim().isNotEmpty) {
        finalSegments.add(TodoSegment(chunk, SegmentType.text));
      }
    }

    // ================= 提取标题 =================
    String finalTitle = finalSegments
        .where((s) => s.type == SegmentType.text)
        .map((s) => s.text.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');

    finalTitle = _cleanTitle(finalTitle);
    if (finalTitle.isEmpty) finalTitle = _cleanTitle(original);

    return ParsedTodoResult(
      title: finalTitle,
      remark: remark,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      recurrence: recurrence,
      customIntervalDays: customIntervalDays,
      recurrenceEndDate: recurrenceEndDate,
      isValid: true,
      segments: finalSegments, // 暴露给外部
      originalText: original, // 📄 原始分析文本
    );
  }

  // ══════════════════════════════════════════════
  // 时间辅助方法区域
  // ══════════════════════════════════════════════
  static double _parseCnNum(String s) {
    if (double.tryParse(s) != null) return double.parse(s);
    const map = {'一':1.0, '二':2.0, '两':2.0, '三':3.0, '四':4.0, '五':5.0, '六':6.0, '七':7.0, '八':8.0, '九':9.0, '十':10.0, '半':0.5};
    return map[s] ?? 0;
  }

  static DateTime _parseRelativeDay(String prefix) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (['明天', '明日', '明早', '明晚'].contains(prefix)) return today.add(const Duration(days: 1));
    if (['后天', '后日', '后早', '后晚'].contains(prefix)) return today.add(const Duration(days: 2));
    return today; // 今天
  }

  static int _weekdayCharToInt(String char) {
    const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
    return map[char] ?? 1;
  }

  static DateTime _getWeekdayDate(int weekday, bool isNextWeek) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int daysUntil = weekday - today.weekday;
    if (daysUntil <= 0) daysUntil += 7;
    if (isNextWeek) daysUntil += 7;
    return today.add(Duration(days: daysUntil));
  }

  static int _adjustHour(String? prefix, int hour) {
    if (prefix == null) return hour;
    switch (prefix) {
      case '凌晨': return hour;
      case '上午': case '早上': return hour;
      case '中午': return hour < 12 ? 12 : hour;
      case '下午': case '晚上': return hour == 12 ? 12 : (hour < 12 ? hour + 12 : hour);
      default: return hour;
    }
  }

  static String _cleanTitle(String text) {
    String result = text.replaceAll(RegExp(r'^\s*[,，、；;]\s*'), '')
        .replaceAll(RegExp(r'[,，、；;]\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (result.isEmpty) return text.trim();
    return result.length > 100 ? result.substring(0, 100) : result;
  }
}