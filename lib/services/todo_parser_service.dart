import '../models.dart';

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
  });

  bool get hasContent => title.isNotEmpty;
}

class TimeParseResult {
  final int hour;
  final int minute;
  final String remaining;
  TimeParseResult(this.hour, this.minute, this.remaining);
}

class DateParseResult {
  final DateTime date;
  final String remaining;
  DateParseResult(this.date, this.remaining);
}

class NDayParseResult {
  final int days;
  final String remaining;
  NDayParseResult(this.days, this.remaining);
}

class RecurrenceParseResult {
  final RecurrenceType type;
  final int? customDays;
  final String remaining;
  RecurrenceParseResult(this.type, this.customDays, this.remaining);

  RecurrenceType get t => type;
  int? get c => customDays;
  String get r => remaining;
}

// ────────────────────────────────────────────────
// 新增：持续时长解析结果
// ────────────────────────────────────────────────
class DurationParseResult {
  final int minutes;
  final String remaining;
  DurationParseResult(this.minutes, this.remaining);
}

// ────────────────────────────────────────────────
// 新增：重复结束日期解析结果
// ────────────────────────────────────────────────
class RecurrenceEndParseResult {
  final DateTime? endDate;
  final int? totalTimes; // 共N次
  final String remaining;
  RecurrenceEndParseResult(this.endDate, this.totalTimes, this.remaining);
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
      results.add(ParsedTodoResult(title: input.trim(), isValid: true));
    }

    return results;
  }

  // ══════════════════════════════════════════════
  // 分句
  // ══════════════════════════════════════════════

  static List<String> _splitIntoSentences(String input) {
    final sentences = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < input.length; i++) {
      final remaining = input.substring(i);

      // 改进：支持更多分隔模式
      final sepLen = _sentenceSeparatorLength(remaining);
      if (sepLen > 0) {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) sentences.add(segment);
        buffer.clear();
        i += sepLen - 1; // -1 因为循环还会 i++
      } else {
        buffer.write(input[i]);
      }
    }

    final last = buffer.toString().trim();
    if (last.isNotEmpty) sentences.add(last);

    return sentences;
  }

  /// 返回分隔符长度，0 表示当前位置不是分隔符
  static int _sentenceSeparatorLength(String remaining) {
    // 中文标点 + 换行
    const singles = ['；', ';', '\n'];
    for (final s in singles) {
      if (remaining.startsWith(s)) return s.length;
    }

    // 词组分隔符（保留原有 + 扩展）
    const phrases = [
      '，然后', '，还有', '，另外',
      '、然后', '、还有', '、另外',
      '，接着', '，再', ',然后', ',还有',
      '然后', // 单独"然后"也分句（置后，避免误截"然后呢"等词）
    ];
    for (final p in phrases) {
      if (remaining.startsWith(p)) return p.length;
    }
    return 0;
  }

  // ══════════════════════════════════════════════
  // 单条解析主流程
  // ══════════════════════════════════════════════

  static ParsedTodoResult parse(String input) {
    String text = input.trim();
    if (text.isEmpty) return ParsedTodoResult(title: '', isValid: false);

    String? remark;
    bool isAllDay = false;
    DateTime? startTime;
    DateTime? endTime;
    RecurrenceType recurrence = RecurrenceType.none;
    int? customIntervalDays;
    DateTime? recurrenceEndDate;

    // ① 提取备注
    final remarkResult = _extractRemark(text);
    if (remarkResult != null) {
      remark = remarkResult.$1;
      text = remarkResult.$2;
    }

    // ② 提取时间范围（优先）
    final timeRange = _extractTimeRange(text);
    if (timeRange != null) {
      startTime = timeRange.$1;
      endTime = timeRange.$2;
      text = timeRange.$3;
    } else {
      // ③ 提取单个时间
      final singleTime = _extractSingleTime(text);
      if (singleTime != null) {
        startTime = singleTime.$1;
        text = singleTime.$2;
        isAllDay = singleTime.$3;
      }

      // ④ 如果有 startTime 且非全天，尝试提取持续时长推算 endTime
      if (startTime != null && !isAllDay) {
        final dur = _extractDuration(text);
        if (dur != null) {
          endTime = startTime.add(Duration(minutes: dur.minutes));
          text = dur.remaining;
        } else {
          // 默认给 1 小时结束时间（仅有具体时刻时）
          endTime = startTime.add(const Duration(hours: 1));
        }
      }
    }

    // ⑤ 提取重复规则
    final recurrenceInfo = _extractRecurrence(text);
    if (recurrenceInfo != null) {
      recurrence = recurrenceInfo.type;
      customIntervalDays = recurrenceInfo.customDays;
      text = recurrenceInfo.remaining;

      // ⑥ 如果有重复，尝试提取重复结束条件
      if (recurrence != RecurrenceType.none) {
        final recEnd = _extractRecurrenceEnd(text);
        if (recEnd != null) {
          recurrenceEndDate = recEnd.endDate;
          text = recEnd.remaining;
        }
      }
    }

    // ⑦ 清理标题
    text = _cleanTitle(text);
    if (text.isEmpty) {
      return ParsedTodoResult(title: input.trim(), isValid: true);
    }

    return ParsedTodoResult(
      title: text,
      remark: remark,
      isAllDay: isAllDay,
      startTime: startTime,
      endTime: endTime,
      recurrence: recurrence,
      customIntervalDays: customIntervalDays,
      recurrenceEndDate: recurrenceEndDate,
      isValid: true,
    );
  }

  // ══════════════════════════════════════════════
  // ① 备注提取（改进：支持通用地点模式）
  // ══════════════════════════════════════════════

  static (String remark, String remaining)? _extractRemark(String text) {
    // @人名
    final atPattern = RegExp(r'@(\S+)');
    final atMatch = atPattern.firstMatch(text);
    if (atMatch != null) {
      final remark = atMatch.group(1)!;
      final remaining = text
          .replaceFirst(atMatch.group(0)!, '')
          .replaceAll('@', ' ')
          .trim();
      return (remark, remaining);
    }

    // 地点模式（从具体到通用）
    final locationPatterns = [
      // 具体场所关键词
      RegExp(
          r'在([^\s，,。！!？?\d]{1,10}(?:图书馆|教室|办公室|会议室|学校|公司|食堂|超市|公园|医院|餐厅|咖啡厅|酒店|机场|车站|广场|体育馆|商场|社区|中心))'),
      // 地点标记
      RegExp(r'地点[：:]\s*([^\s，,。！!]{1,20})'),
      RegExp(r'地址[：:]\s*([^\s，,。！!]{1,20})'),
      // 通用"在XX"兜底（2-8字，不能是时间词）
      RegExp(
          r'在(?!今天|明天|后天|下周|上周|这周|周[一二三四五六日天])([^\s，,。！!？?\d]{2,8})(?:这里|那里|此处)?'),
    ];

    for (final p in locationPatterns) {
      final m = p.firstMatch(text);
      if (m != null) {
        final remark = m.group(1)!;
        final remaining = text.replaceFirst(m.group(0)!, '').trim();
        return (remark, remaining);
      }
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // ② 时间范围提取
  // ══════════════════════════════════════════════

  static (DateTime?, DateTime?, String)? _extractTimeRange(String text) {
    final now = DateTime.now();
    final baseDate = DateTime(now.year, now.month, now.day);

    final fullPattern = RegExp(
        r'(今天|明天|后天|下周[一二三四五六日天]|这周[一二三四五六日天]|周[一二三四五六日天])?\s*'
        r'(上午|下午|早上|晚上|中午|凌晨)?\s*'
        r'(\d{1,2})[点时](?:(\d{1,2})分?)?\s*'
        r'到\s*'
        r'(上午|下午|早上|晚上|中午|凌晨)?\s*'
        r'(\d{1,2})[点时](?:(\d{1,2})分?)?');

    final match = fullPattern.firstMatch(text);
    if (match == null) return null;

    DateTime date = baseDate;
    final dateStr = match.group(1);
    if (dateStr != null) {
      date = _parseDatePrefix(dateStr) ?? baseDate;
    }

    final prefix1 = match.group(2);
    int startHour = int.parse(match.group(3)!);
    int startMinute = int.tryParse(match.group(4) ?? '') ?? 0;

    final prefix2 = match.group(5);
    int endHour = int.parse(match.group(6)!);
    int endMinute = int.tryParse(match.group(7) ?? '') ?? 0;

    startHour = _adjustHour(prefix1, startHour);
    endHour = _adjustHour(prefix2 ?? prefix1, endHour); // 结束时段继承开始时段

    DateTime startDateTime =
    DateTime(date.year, date.month, date.day, startHour, startMinute);
    DateTime endDateTime =
    DateTime(date.year, date.month, date.day, endHour, endMinute);

    if (endDateTime.isBefore(startDateTime)) {
      endDateTime = endDateTime.add(const Duration(days: 1));
    }

    final remaining = text.substring(match.end).trim();
    return (startDateTime, endDateTime, remaining);
  }

  // ══════════════════════════════════════════════
  // ③ 单个时间提取
  // ══════════════════════════════════════════════

  static (DateTime?, String, bool)? _extractSingleTime(String text) {
    // N天/周/月后
    final nDays = _extractNDaysLater(text);
    if (nDays != null) {
      return _buildSingleTimeResult(
          DateTime.now().add(Duration(days: nDays.days)), nDays.remaining);
    }

    // 星期几
    final weekday = _extractWeekday(text);
    if (weekday != null) {
      final date = _getWeekdayDate(weekday.$1, weekday.$2);
      if (date != null) {
        return _buildSingleTimeResult(date, weekday.$3);
      }
    }

    // 具体日期（MM月DD日 / YYYY-MM-DD 等）
    final specific = _extractSpecificDate(text);
    if (specific != null) {
      return _buildSingleTimeResult(specific.date, specific.remaining);
    }

    // 今天/明天/后天
    final rel = _extractTodayTomorrow(text);
    if (rel != null) {
      return _buildSingleTimeResult(rel.date, rel.remaining);
    }

    // 纯时间（今天）
    final timeOnly = _extractTimeOnly(text);
    if (timeOnly != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dt = DateTime(
          today.year, today.month, today.day, timeOnly.hour, timeOnly.minute);
      return (dt, timeOnly.remaining, false);
    }

    return null;
  }

  /// 把日期 + 剩余文本拼出单时间结果（抽公共逻辑）
  static (DateTime, String, bool) _buildSingleTimeResult(
      DateTime date, String remaining) {
    final timeInfo = _extractTimeFromText(remaining);
    if (timeInfo.hour != null) {
      final dt = DateTime(
          date.year, date.month, date.day, timeInfo.hour!, timeInfo.minute!);
      return (dt, timeInfo.remaining, false);
    } else {
      // 全天：startTime 设为当天 00:00
      final dt = DateTime(date.year, date.month, date.day, 0, 0);
      return (dt, remaining, true);
    }
  }

  // ══════════════════════════════════════════════
  // ④ 新增：持续时长解析
  // 支持：2小时、半小时、1.5小时、30分钟、1小时30分
  // ══════════════════════════════════════════════

  static DurationParseResult? _extractDuration(String text) {
    // 1小时30分 / 2小时30分钟
    final combined = RegExp(r'(\d+(?:\.\d+)?)\s*小时\s*(\d+)\s*分钟?');
    final cm = combined.firstMatch(text);
    if (cm != null) {
      final h = double.parse(cm.group(1)!);
      final m = int.parse(cm.group(2)!);
      return DurationParseResult(
          (h * 60).round() + m, text.substring(cm.end).trim());
    }

    // N小时 / N.5小时
    final hoursPattern = RegExp(r'(\d+(?:\.\d+)?)\s*小时');
    final hm = hoursPattern.firstMatch(text);
    if (hm != null) {
      final h = double.parse(hm.group(1)!);
      return DurationParseResult(
          (h * 60).round(), text.substring(hm.end).trim());
    }

    // 半小时
    if (text.contains('半小时')) {
      return DurationParseResult(
          30, text.replaceFirst('半小时', '').trim());
    }

    // N分钟
    final minPattern = RegExp(r'(\d+)\s*分钟');
    final mm = minPattern.firstMatch(text);
    if (mm != null) {
      final m = int.parse(mm.group(1)!);
      return DurationParseResult(m, text.substring(mm.end).trim());
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // ⑤ 重复规则提取（原有逻辑，略作整理）
  // ══════════════════════════════════════════════

  static RecurrenceParseResult? _extractRecurrence(String text) {
    final patterns = [
      (RegExp(r'每天|天天|每日'), RecurrenceType.daily, 0),
      (RegExp(r'每周|每星期|每礼拜'), RecurrenceType.weekly, 0),
      (RegExp(r'每月|每个月'), RecurrenceType.monthly, 0),
      (RegExp(r'每一年|每年'), RecurrenceType.yearly, 0),
      (RegExp(r'工作日|周一到周五|星期一至星期五'), RecurrenceType.weekdays, 0),
      (RegExp(r'每两天|隔一天|每隔一天'), RecurrenceType.customDays, 2),
      (RegExp(r'(\d+)\s*天\s*一次'), RecurrenceType.customDays, -1),
      (RegExp(r'(\d+)\s*周\s*一次'), RecurrenceType.customDays, -7),
    ];

    for (final p in patterns) {
      final match = p.$1.firstMatch(text);
      if (match == null) continue;

      String remaining = text.substring(match.end).trim();
      int? interval;

      if (p.$3 == -1) {
        final n = RegExp(r'(\d+)').firstMatch(match.group(0)!);
        interval = int.tryParse(n?.group(1) ?? '');
      } else if (p.$3 == -7) {
        final n = RegExp(r'(\d+)').firstMatch(match.group(0)!);
        interval = (int.tryParse(n?.group(1) ?? '') ?? 1) * 7;
      } else if (p.$3 > 0) {
        interval = p.$3;
      }

      return RecurrenceParseResult(p.$2, interval, remaining);
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // ⑥ 新增：重复结束条件解析
  // 支持：直到X月X日、共N次、持续N天/周/月
  // ══════════════════════════════════════════════

  static RecurrenceEndParseResult? _extractRecurrenceEnd(String text) {
    final now = DateTime.now();

    // 直到/到 + 日期
    final untilDatePattern = RegExp(
        r'(?:直到|到)\s*(\d{4}年)?(\d{1,2})月(\d{1,2})(?:日|号)?');
    final udm = untilDatePattern.firstMatch(text);
    if (udm != null) {
      final year = udm.group(1) != null
          ? int.parse(udm.group(1)!.replaceAll('年', ''))
          : now.year;
      final month = int.parse(udm.group(2)!);
      final day = int.parse(udm.group(3)!);
      final endDate = DateTime(year, month, day);
      return RecurrenceEndParseResult(
          endDate, null, text.substring(udm.end).trim());
    }

    // 直到月底/年底
    final untilEndPattern = RegExp(r'(?:直到|到)\s*(月底|年底|月末|年末)');
    final uem = untilEndPattern.firstMatch(text);
    if (uem != null) {
      final isYear =
      uem.group(1)!.contains('年');
      final endDate = isYear
          ? DateTime(now.year, 12, 31)
          : DateTime(now.year, now.month + 1, 0); // 当月最后一天
      return RecurrenceEndParseResult(
          endDate, null, text.substring(uem.end).trim());
    }

    // 共N次
    final timesPattern = RegExp(r'共(\d+)次');
    final tm = timesPattern.firstMatch(text);
    if (tm != null) {
      final times = int.parse(tm.group(1)!);
      return RecurrenceEndParseResult(
          null, times, text.substring(tm.end).trim());
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // 时间辅助：N天后
  // ══════════════════════════════════════════════

  static NDayParseResult? _extractNDaysLater(String text) {
    final patterns = [
      (RegExp(r'(\d+)\s*天\s*后'), 1),
      (RegExp(r'(\d+)\s*周\s*后'), 7),
      (RegExp(r'(\d+)\s*个?\s*月\s*后'), 30),
      (RegExp(r'(\d+)\s*年\s*后'), 365),
    ];

    for (final p in patterns) {
      final m = p.$1.firstMatch(text);
      if (m != null) {
        final v = int.tryParse(m.group(1)!) ?? 0;
        if (v > 0) {
          return NDayParseResult(v * p.$2, text.substring(m.end).trim());
        }
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════
  // 时间辅助：星期几
  // ══════════════════════════════════════════════

  static (int weekday, bool isNextWeek, String remaining)? _extractWeekday(
      String text) {
    final nextPattern = RegExp(r'下\s*周\s*(一|二|三|四|五|六|日|天)');
    final nm = nextPattern.firstMatch(text);
    if (nm != null) {
      return (_weekdayCharToInt(nm.group(1)!), true,
      text.substring(nm.end).trim());
    }

    final thisPattern = RegExp(r'这\s*周\s*(一|二|三|四|五|六|日|天)');
    final tm = thisPattern.firstMatch(text);
    if (tm != null) {
      return (_weekdayCharToInt(tm.group(1)!), false,
      text.substring(tm.end).trim());
    }

    final generalPattern = RegExp(r'(下周)?(周|星期)(一|二|三|四|五|六|日|天)');
    final gm = generalPattern.firstMatch(text);
    if (gm != null) {
      final isNext = gm.group(1) != null;
      return (_weekdayCharToInt(gm.group(3)!), isNext,
      text.substring(gm.end).trim());
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // 时间辅助：具体日期
  // ══════════════════════════════════════════════

  static DateParseResult? _extractSpecificDate(String text) {
    final now = DateTime.now();

    final patterns = [
      RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})(?:日|号)?'),
      RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})'),
      RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})(?:日|号)?'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m == null) continue;

      int year, month, day;
      if (m.groupCount == 3) {
        year = int.parse(m.group(1)!);
        month = int.parse(m.group(2)!);
        day = int.parse(m.group(3)!);
      } else {
        month = int.parse(m.group(1)!);
        day = int.parse(m.group(2)!);
        year = (month < now.month || (month == now.month && day < now.day))
            ? now.year + 1
            : now.year;
      }

      return DateParseResult(DateTime(year, month, day), text.substring(m.end).trim());
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // 时间辅助：今天/明天/后天
  // ══════════════════════════════════════════════

  static DateParseResult? _extractTodayTomorrow(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<String, int> offsets = {
      '今天': 0, '今日': 0,
      '明天': 1, '明日': 1,
      '后天': 2, '后日': 2,
    };

    for (final entry in offsets.entries) {
      if (text.startsWith(entry.key)) {
        return DateParseResult(
          today.add(Duration(days: entry.value)),
          text.substring(entry.key.length).trim(),
        );
      }
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // 时间辅助：日期前缀 → DateTime
  // ══════════════════════════════════════════════

  static DateTime? _parseDatePrefix(String prefix) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (prefix) {
      case '今天': case '今日': return today;
      case '明天': case '明日': return today.add(const Duration(days: 1));
      case '后天': case '后日': return today.add(const Duration(days: 2));
    }

    // 下周X / 这周X / 周X
    final m = RegExp(r'(下周|这周)?(周|星期)?(一|二|三|四|五|六|日|天)$').firstMatch(prefix);
    if (m != null) {
      final isNext = m.group(1) == '下周';
      final weekday = _weekdayCharToInt(m.group(3)!);
      return _getWeekdayDate(weekday, isNext);
    }

    return null;
  }

  // ══════════════════════════════════════════════
  // 时间辅助：纯时间提取（修复 _adjustHour 歧义）
  // ══════════════════════════════════════════════

  static TimeParseResult? _extractTimeOnly(String text) {
    final patterns = [
      RegExp(r'(上午|早上|中午|下午|晚上|凌晨)\s*(\d{1,2})[点时](\d{1,2})?分?'),
      RegExp(r'(上午|早上|中午|下午|晚上|凌晨)\s*(\d{1,2}):(\d{2})'),
      RegExp(r'(\d{1,2})[点时](\d{1,2})?分?'),
      RegExp(r'(\d{1,2}):(\d{2})'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m == null) continue;

      String? prefix;
      int hour, minute = 0;

      if (m.groupCount >= 3 && _isTimePrefix(m.group(1))) {
        prefix = m.group(1);
        hour = int.parse(m.group(2)!);
        minute = int.tryParse(m.group(3) ?? '') ?? 0;
      } else {
        hour = int.parse(m.group(1)!);
        minute = int.tryParse(m.group(2) ?? '') ?? 0;
      }

      hour = _adjustHour(prefix, hour);
      hour = hour.clamp(0, 23);
      minute = minute.clamp(0, 59);

      return TimeParseResult(hour, minute, text.substring(m.end).trim());
    }

    return null;
  }

  static bool _isTimePrefix(String? s) {
    const prefixes = ['上午', '早上', '中午', '下午', '晚上', '凌晨'];
    return prefixes.contains(s);
  }

  // ══════════════════════════════════════════════
  // 时间辅助：小时调整（修复下午逻辑）
  // ══════════════════════════════════════════════

  static int _adjustHour(String? prefix, int hour) {
    if (prefix == null) return hour;
    switch (prefix) {
      case '凌晨':
      // 凌晨 1-5 点，原样
        return hour <= 5 ? hour : hour;
      case '上午':
      case '早上':
      // 12小时制，最大到12
        return hour <= 12 ? hour : hour;
      case '中午':
        return hour < 12 ? 12 : hour;
      case '下午':
      case '晚上':
      // 关键修复：下午1点 = 13，下午12点 = 12
        if (hour == 12) return 12;
        if (hour < 12) return hour + 12;
        return hour; // 已经是24h制
      default:
        return hour;
    }
  }

  // ══════════════════════════════════════════════
  // 时间辅助：从文本提取时间信息
  // ══════════════════════════════════════════════

  static _TimeInfo _extractTimeFromText(String text) {
    if (text.isEmpty) return _TimeInfo(null, null, text);
    final t = _extractTimeOnly(text);
    if (t != null) return _TimeInfo(t.hour, t.minute, t.remaining);
    return _TimeInfo(null, null, text);
  }

  // ══════════════════════════════════════════════
  // 时间辅助：星期几计算（修复 weekday 映射）
  // ══════════════════════════════════════════════

  static int _weekdayCharToInt(String char) {
    // Dart weekday: 1=周一 ... 7=周日，与此处一致
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '日': 7, '天': 7,
    };
    return map[char] ?? 1;
  }

  static DateTime? _getWeekdayDate(int weekday, bool isNextWeek) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Dart 的 weekday: 1=Mon ... 7=Sun，直接比较
    int daysUntil = weekday - today.weekday;

    if (isNextWeek) {
      // 强制下周
      if (daysUntil <= 0) daysUntil += 7;
      daysUntil += 7;
    } else {
      // 本周或最近那个
      if (daysUntil <= 0) daysUntil += 7;
    }

    return today.add(Duration(days: daysUntil));
  }

  // ══════════════════════════════════════════════
  // 标题清理
  // ══════════════════════════════════════════════

  static String _cleanTitle(String text) {
    String result = text;
    result = result.replaceAll(
        RegExp(r'^(提醒?|通知|记得|要|需要|必须|一定|请|麻烦)\s*'), '');
    result = result.replaceAll(RegExp(r'(?:提醒?|通知|记得)\s*$'), '');
    result = result.replaceAll(RegExp(r'^\s*[,，、]\s*'), '');
    result = result.replaceAll(RegExp(r'[,，、]\s*$'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (result.length > 100) result = result.substring(0, 100);
    return result;
  }
}

class _TimeInfo {
  final int? hour;
  final int? minute;
  final String remaining;
  _TimeInfo(this.hour, this.minute, this.remaining);
}