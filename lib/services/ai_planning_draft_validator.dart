abstract final class AiPlanningDraftValidator {
  static final RegExp _fromNowRequestPattern = RegExp(
    r'从现在|现在开始|现在起|剩下的时间|剩余时间|余下的时间|今天剩余|今晚剩下',
  );
  static final RegExp _deadlinePattern = RegExp(
    r'(?:截止|截至|到|不晚于)\s*(?:(今天|今晚|明天)\s*)?'
    r'(?:(晚上|夜里|下午|早上|上午|中午)\s*)?'
    r'((?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3}))'
    r'\s*(?::|：|点)\s*(\d{1,2}|半|一刻|三刻)?\s*分?',
  );

  static String? validateFromNow({
    required String requestText,
    required List<Map<String, dynamic>> actions,
    required DateTime now,
  }) {
    if (!_isFromNowRequest(requestText)) return null;

    final blocks = <Map<String, dynamic>>[
      for (final action in actions)
        if (action['action'] == 'create_plan_block' && action['blocks'] is List)
          for (final block in (action['blocks'] as List).whereType<Map>())
            Map<String, dynamic>.from(block),
    ];
    if (blocks.isEmpty) return null;

    final requestStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final deadline = _resolveDeadline(requestText, now);
    final intervals = <({DateTime start, DateTime end})>[];

    for (final block in blocks) {
      final start = _parseDateTime(block['startTime']);
      final end =
          _parseDateTime(block['dueDate'] ?? block['endTime']) ??
          (start != null && block['durationMinutes'] is num
              ? start.add(
                  Duration(minutes: (block['durationMinutes'] as num).toInt()),
                )
              : null);
      if (start == null || end == null || !end.isAfter(start)) continue;

      if (start.isBefore(requestStart)) {
        return '至少一个规划块的开始时间早于本轮请求时的当前时间 '
            '(${_format(requestStart)})。';
      }
      if (deadline != null && end.isAfter(deadline)) {
        return '至少一个规划块结束于用户要求的截止时间 '
            '(${_format(deadline)}) 之后。';
      }
      intervals.add((start: start, end: end));
    }

    intervals.sort((left, right) => left.start.compareTo(right.start));
    for (var i = 1; i < intervals.length; i++) {
      if (intervals[i].start.isBefore(intervals[i - 1].end)) {
        return '规划块之间存在时间重叠。';
      }
    }
    return null;
  }

  static bool _isFromNowRequest(String text) =>
      _fromNowRequestPattern.hasMatch(text);

  static DateTime? _resolveDeadline(String text, DateTime now) {
    final matches = _deadlinePattern.allMatches(text).toList();
    if (matches.isEmpty) return null;

    final match = matches.last;
    final day = match.group(1);
    final period = match.group(2);
    final hourValue = _parseChineseNumber(match.group(3)!);
    final minuteText = match.group(4);
    final minute = switch (minuteText) {
      null || '' => 0,
      '半' => 30,
      '一刻' => 15,
      '三刻' => 45,
      _ => _parseChineseNumber(minuteText),
    };
    if (hourValue == null || minute == null || minute > 59) return null;

    var hour = hourValue;
    if ((period == '晚上' || day == '今晚' || period == '夜里' || period == '下午') &&
        hour < 12) {
      hour += 12;
    } else if (period == '中午' && hour < 11) {
      hour += 12;
    }
    if (hour > 23) return null;

    final dayOffset = day == '明天' ? 1 : 0;
    return DateTime(now.year, now.month, now.day + dayOffset, hour, minute);
  }

  static int? _parseChineseNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (!value.contains('十')) return digits[value];
    final parts = value.split('十');
    final tens = parts.first.isEmpty ? 1 : digits[parts.first];
    final ones = parts.length < 2 || parts[1].isEmpty ? 0 : digits[parts[1]];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));
  }

  static String _format(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
