part of '../ai_todo_context_builder.dart';

final RegExp _explicitIsoDateRangePattern = RegExp(
  r'(\d{4}-\d{2}-\d{2})\s*(?:至|到|-|~)\s*(\d{4}-\d{2}-\d{2})',
);

final RegExp _explicitIsoDatePattern = RegExp(
  r'(?<!\d)(\d{4}-\d{2}-\d{2})(?!\d)',
);

final RegExp _explicitChineseDateRangePattern = RegExp(
  r'(?:(\d{4})\s*年\s*)?'
  r'(\d{1,2}|[一二三四五六七八九十]{1,2})\s*月\s*'
  r'(\d{1,2}|[一二三四五六七八九十]{1,3})\s*(?:日|号)\s*'
  r'(?:至|到|~|～|－|–|—|-)\s*'
  r'(?:(\d{4})\s*年\s*)?'
  r'(\d{1,2}|[一二三四五六七八九十]{1,2})\s*月\s*'
  r'(\d{1,2}|[一二三四五六七八九十]{1,3})\s*(?:日|号)',
);

final RegExp _explicitChineseDatePattern = RegExp(
  r'(?:(\d{4})\s*年\s*)?'
  r'(\d{1,2}|[一二三四五六七八九十]{1,2})\s*月\s*'
  r'(\d{1,2}|[一二三四五六七八九十]{1,3})\s*(?:日|号)',
);

final RegExp _monthPeriodPattern = RegExp(
  r'(?:(?:\d{4}\s*年|今年|去年)\s*)?(?:0?[1-9]|1[0-2])\s*月(?:份)?'
  r'(?!\s*(?:\d{1,2}\s*(?:日|号)|个))|'
  r'上上个月|上上月|上个月|上月|本月|这个月',
);

final RegExp _rollingMonthRangePattern = RegExp(
  r'(?<![\d一二两三四五六七八九十])(?:最近|过去|近)?\s*'
  r'(?:(\d{1,2}|[一二两三四五六七八九十]{1,3})\s*个月|半年)',
);

final RegExp _relativeDayRangePattern = RegExp(
  r'(?:最近|过去|近)\s*(?:(?:\d{1,6}|[零〇一二两三四五六七八九十百千]{1,12})\s*(?:天|日)|'
  r'(?:\d{1,3}|[一二两三四五六七八九十]{1,3})\s*(?:周|星期|礼拜))',
);

final RegExp _relativeWeekPeriodPattern = RegExp(
  r'上上(?:周|星期|礼拜)|上(?:周|星期|礼拜)|本(?:周|星期|礼拜)|这(?:周|星期|礼拜)',
);

final RegExp _relativeQuarterPeriodPattern = RegExp(
  r'上上(?:个)?季度|上(?:个)?季度|上一季度|前一季度|本季度|这个季度|当前季度|这季度|'
  r'(?:(?:今年|去年)\s*|\d{4}\s*年\s*)?(?:第\s*)?[一二三四1-4]\s*季度',
);

final RegExp _relativeYearPeriodPattern = RegExp(
  r'(?:最近|过去|近)(?:一年|1年|12个月)|今年|去年|\d{4}\s*年',
);

final RegExp _relativeYearQualifiedDatePattern = RegExp(
  r'(?:今年|去年)\s*\d{1,2}\s*月(?:\s*\d{1,2}\s*(?:日|号))?',
);

final RegExp _relativeSingleDayPeriodPattern = RegExp(
  r'大前天|大前日|前天|前日|昨天|昨日|今天|今日|明天|明日|大后天|大后日|后天|后日',
);

final RegExp _futureDaysRangePattern = RegExp(
  r'(?:未来|接下来)\s*(?:\d{1,6}|[零〇一二两三四五六七八九十百千]{1,12})\s*(?:天|日)',
);

AiContextDateRange? _resolveCustomInjectionDateRange({
  DateTime? customStart,
  DateTime? customEnd,
  bool injectMoreContext = false,
  DateTime? now,
}) {
  if (customStart == null || customEnd == null) return null;
  final selectedStart = CalendarDateMath.dateOnly(customStart);
  final selectedEndExclusive = DateTime(
    customEnd.year,
    customEnd.month,
    customEnd.day + 1,
  );
  if (!injectMoreContext) {
    return AiContextDateRange(selectedStart, selectedEndExclusive);
  }

  final current = now ?? DateTime.now();
  final today = CalendarDateMath.dateOnly(current);
  final futureEndExclusive = DateTime(today.year, today.month, today.day + 30);
  return AiContextDateRange(
    selectedStart.isBefore(today) ? selectedStart : today,
    selectedEndExclusive.isAfter(futureEndExclusive)
        ? selectedEndExclusive
        : futureEndExclusive,
  );
}

List<FixedScheduleItem> _scopeFixedSchedulesByTime(
  List<FixedScheduleItem> schedules, {
  required String userMessage,
  required DateTime now,
}) {
  final active = schedules.where((item) => !item.isDeleted).toList()
    ..sort((left, right) {
      final dateCompare = left.date.compareTo(right.date);
      if (dateCompare != 0) return dateCompare;
      return (left.startTime ?? 0).compareTo(right.startTime ?? 0);
    });
  final period = _resolveCoursePeriod(userMessage, now);
  if (period != null) {
    return active.where((item) {
      final date = DateTime.tryParse(item.date);
      return date != null &&
          !date.isBefore(period.start) &&
          date.isBefore(period.end);
    }).toList();
  }
  if (userMessage.trim().isEmpty) return active;
  final today = CalendarDateMath.dateOnly(now);
  return active.where((item) {
    final date = DateTime.tryParse(item.date);
    return date != null && !date.isBefore(today);
  }).toList();
}

List<CourseItem> _selectCoursesForPeriod(
  List<CourseItem> courses,
  _DateRange? period,
  DateTime now,
) {
  if (period != null) {
    return courses.where((c) {
      final date = DateTime.tryParse(c.date);
      if (date == null) return false;
      final day = CalendarDateMath.dateOnly(date);
      return !day.isBefore(period.start) && day.isBefore(period.end);
    }).toList();
  }

  final today = CalendarDateMath.dateOnly(now);
  return courses.where((c) {
    final date = DateTime.tryParse(c.date);
    if (date == null) return false;
    final day = CalendarDateMath.dateOnly(date);
    return !day.isBefore(today);
  }).toList();
}

_DateRange? _resolveRollingMonthRange(String text, DateTime now) {
  final match = _rollingMonthRangePattern.firstMatch(text);
  if (match == null) return null;
  final months = _parseRollingMonthCount(match.group(1) ?? '6');
  if (months == null || months < 1) return null;

  final todayStart = CalendarDateMath.dateOnly(now);
  final targetMonth = DateTime(todayStart.year, todayStart.month - months);
  final lastDayOfTargetMonth = DateTime(
    targetMonth.year,
    targetMonth.month + 1,
    0,
  ).day;
  final start = DateTime(
    targetMonth.year,
    targetMonth.month,
    now.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : now.day,
  );
  return _DateRange(
    label: '最近$months个月',
    start: start,
    end: AppTimeFormats.localDayStartOffset(todayStart, 1),
  );
}

_DateRange? _resolveRecentDayRange(String text, DateTime now) {
  final numericDays = RegExp(r'(?:最近|过去|近)\s*(\d{1,6})\s*(?:天|日)')
      .firstMatch(text);
  final chineseDays = RegExp(
    r'(?:最近|过去|近)\s*([零〇一二两三四五六七八九十百千]{1,12})\s*(?:天|日)',
  ).firstMatch(text);
  final numericWeeks = RegExp(r'(?:最近|过去|近)\s*(\d{1,3})\s*(?:周|星期|礼拜)')
      .firstMatch(text);
  final chineseWeeks = RegExp(
    r'(?:最近|过去|近)\s*([一二两三四五六七八九十]{1,3})\s*(?:周|星期|礼拜)',
  ).firstMatch(text);
  final weeks = numericWeeks != null
      ? int.tryParse(numericWeeks.group(1)!)
      : chineseWeeks != null
      ? _parseSimpleChineseNumber(chineseWeeks.group(1)!)
      : null;
  final days = numericDays != null
      ? int.tryParse(numericDays.group(1)!)
      : chineseDays != null
      ? _parseChineseDayCount(chineseDays.group(1)!)
      : weeks != null
      ? weeks * 7
      : null;
  if (days == null || days <= 0) return null;

  final todayStart = CalendarDateMath.dateOnly(now);
  return _DateRange(
    label: '最近$days天',
    start: AppTimeFormats.localDayStartOffset(todayStart, -(days - 1)),
    end: AppTimeFormats.localDayStartOffset(todayStart, 1),
  );
}

_DateRange? _resolveCoursePeriod(String text, DateTime now) {
  final explicit = _resolveExplicitDateRange(text);
  if (explicit != null) return explicit;
  final rollingMonthRange = _resolveRollingMonthRange(text, now);
  if (rollingMonthRange != null) return rollingMonthRange;
  final recentDayRange = _resolveRecentDayRange(text, now);
  if (recentDayRange != null) return recentDayRange;
  final todayStart = CalendarDateMath.dateOnly(now);
  final currentMonthStart = DateTime(now.year, now.month);
  if (text.contains('上个月') || text.contains('上月')) {
    return _DateRange(
      label: '上个月',
      start: DateTime(now.year, now.month - 1),
      end: currentMonthStart,
    );
  }
  if (text.contains('本月') || text.contains('这个月')) {
    return _DateRange(
      label: '本月',
      start: currentMonthStart,
      end: DateTime(now.year, now.month + 1),
    );
  }
  final weekdayMatch = RegExp(r'(?:星期|礼拜|周)([一二三四五六日天])').firstMatch(text);
  if (weekdayMatch != null) {
    final targetWeekday = switch (weekdayMatch.group(1)) {
      '一' => DateTime.monday,
      '二' => DateTime.tuesday,
      '三' => DateTime.wednesday,
      '四' => DateTime.thursday,
      '五' => DateTime.friday,
      '六' => DateTime.saturday,
      '日' || '天' => DateTime.sunday,
      _ => null,
    };
    if (targetWeekday != null) {
      final thisWeekStart = AppTimeFormats.localDayStartOffset(
        todayStart,
        -(now.weekday - DateTime.monday),
      );
      final weekdayOffset = targetWeekday - DateTime.monday;
      final DateTime targetDay;
      if (text.contains('上周') || text.contains('上星期') || text.contains('上礼拜')) {
        targetDay = AppTimeFormats.localDayStartOffset(
          thisWeekStart,
          weekdayOffset - 7,
        );
      } else if (text.contains('下周') ||
          text.contains('下星期') ||
          text.contains('下礼拜')) {
        targetDay = AppTimeFormats.localDayStartOffset(
          thisWeekStart,
          weekdayOffset + 7,
        );
      } else if (text.contains('本周') ||
          text.contains('这周') ||
          text.contains('本星期') ||
          text.contains('这星期')) {
        targetDay = AppTimeFormats.localDayStartOffset(
          thisWeekStart,
          weekdayOffset,
        );
      } else {
        final daysAhead = (targetWeekday - now.weekday + 7) % 7;
        targetDay = AppTimeFormats.localDayStartOffset(todayStart, daysAhead);
      }
      return _DateRange(
        label: '指定星期',
        start: targetDay,
        end: AppTimeFormats.localDayStartOffset(targetDay, 1),
      );
    }
  }
  final futureDays = _parseFutureDays(text);
  if (futureDays != null) {
    return _DateRange(
      label: '未来$futureDays天',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, futureDays),
    );
  }
  if (text.contains('未来一周') ||
      text.contains('接下来一周') ||
      text.contains('未来7天') ||
      text.contains('未来七天') ||
      text.contains('接下来7天') ||
      text.contains('接下来七天')) {
    return _DateRange(
      label: '未来一周',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, 7),
    );
  }
  if (text.contains('今天') || text.contains('今日')) {
    return _DateRange(
      label: '今日',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('明天') || text.contains('明日')) {
    final start = AppTimeFormats.localDayStartOffset(todayStart, 1);
    return _DateRange(
      label: '明日',
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 1),
    );
  }
  if (text.contains('后天') || text.contains('后日')) {
    final start = AppTimeFormats.localDayStartOffset(todayStart, 2);
    return _DateRange(
      label: '后日',
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 1),
    );
  }
  if (text.contains('下周')) {
    final thisWeekStart = AppTimeFormats.localDayStartOffset(
      todayStart,
      -(now.weekday - 1),
    );
    final start = AppTimeFormats.localDayStartOffset(thisWeekStart, 7);
    return _DateRange(
      label: '下周',
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 7),
    );
  }
  if (text.contains('本周') || text.contains('这周')) {
    final start = AppTimeFormats.localDayStartOffset(
      todayStart,
      -(now.weekday - 1),
    );
    return _DateRange(
      label: '本周',
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 7),
    );
  }
  return null;
}

int? _parseFutureDays(String text) {
  final digitMatch = RegExp(r'(?:未来|接下来)\s*(\d{1,6})\s*(?:天|日)')
      .firstMatch(text);
  if (digitMatch != null) {
    final parsed = int.tryParse(digitMatch.group(1)!);
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }

  final hanMatch = RegExp(r'(?:未来|接下来)\s*([零〇一二两三四五六七八九十百千]{1,12})\s*(?:天|日)')
      .firstMatch(text);
  if (hanMatch != null) {
    final parsed = _parseChineseDayCount(hanMatch.group(1)!);
    if (parsed != null && parsed > 0) {
      return parsed;
    }
  }
  return null;
}

int? _parseChineseDayCount(String text) {
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
  const units = {'十': 10, '百': 100, '千': 1000};
  var total = 0;
  var pendingDigit = 0;
  var hasPendingDigit = false;
  var previousWasZero = false;
  var previousUnit = 10000;

  for (final character in text.split('')) {
    final value = digits[character];
    if (value != null) {
      if (value == 0) {
        pendingDigit = 0;
        hasPendingDigit = true;
        previousWasZero = true;
        continue;
      }
      if (hasPendingDigit && !previousWasZero) return null;
      pendingDigit = value;
      hasPendingDigit = true;
      previousWasZero = false;
      continue;
    }

    final unit = units[character];
    if (unit == null || unit >= previousUnit || previousWasZero) {
      return null;
    }
    total += (hasPendingDigit ? pendingDigit : 1) * unit;
    if (total > 999999) return null;
    pendingDigit = 0;
    hasPendingDigit = false;
    previousWasZero = false;
    previousUnit = unit;
  }

  final result = total + pendingDigit;
  return result <= 999999 ? result : null;
}

int? _parseSimpleChineseNumber(String text) {
  const digits = {
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
  if (text == '十') return 10;
  if (text.startsWith('十')) {
    final unit = digits[text.substring(1)];
    return unit == null ? null : 10 + unit;
  }
  if (text.endsWith('十')) {
    final tens = digits[text.substring(0, text.length - 1)];
    return tens == null ? null : tens * 10;
  }
  final tenIdx = text.indexOf('十');
  if (tenIdx > 0 && tenIdx < text.length - 1) {
    final tens = digits[text.substring(0, tenIdx)];
    final units = digits[text.substring(tenIdx + 1)];
    if (tens != null && units != null) return tens * 10 + units;
  }
  return digits[text];
}

_TimeLogPeriod? _resolveTimeLogPeriod(String text, DateTime now) {
  final explicit = _resolveExplicitDateRange(text);
  if (explicit != null) {
    return _TimeLogPeriod(
      label: explicit.label,
      start: explicit.start,
      end: explicit.end,
    );
  }
  final explicitChineseRange = _explicitChineseDateRangePattern.firstMatch(
    text,
  );
  if (explicitChineseRange != null) {
    return _parseExplicitChineseDateRange(explicitChineseRange, now);
  }
  final dateMatches = RegExp(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)')
      .allMatches(text)
      .toList();
  if (dateMatches.length == 1) {
    final match = dateMatches.single;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final start = DateTime(year, month, day);
    if (start.year == year && start.month == month && start.day == day) {
      return _TimeLogPeriod(
        label: match.group(0)!,
        start: start,
        end: AppTimeFormats.localDayStartOffset(start, 1),
      );
    }
  }
  final todayStart = CalendarDateMath.dateOnly(now);
  final rollingMonthRange = _resolveRollingMonthRange(text, now);
  if (rollingMonthRange != null) {
    return _TimeLogPeriod(
      label: rollingMonthRange.label,
      start: rollingMonthRange.start,
      end: rollingMonthRange.end,
    );
  }
  _TimeLogPeriod? exactDayPeriod(int year, int month, int day) {
    final start = DateTime(year, month, day);
    if (start.year != year || start.month != month || start.day != day) {
      return null;
    }
    return _TimeLogPeriod(
      label: AppTimeFormats.date(start),
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 1),
    );
  }

  final explicitChineseDay = RegExp(
    r'(?:^|[^\d])(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|号)',
  ).firstMatch(text);
  if (explicitChineseDay != null) {
    final period = exactDayPeriod(
      int.parse(explicitChineseDay.group(1)!),
      int.parse(explicitChineseDay.group(2)!),
      int.parse(explicitChineseDay.group(3)!),
    );
    if (period != null) return period;
  }
  final relativeMonthDay = RegExp(
    r'(今年|去年)\s*(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|号)',
  ).firstMatch(text);
  if (relativeMonthDay != null) {
    final year = relativeMonthDay.group(1) == '去年' ? now.year - 1 : now.year;
    final period = exactDayPeriod(
      year,
      int.parse(relativeMonthDay.group(2)!),
      int.parse(relativeMonthDay.group(3)!),
    );
    if (period != null) return period;
  }
  final monthDay = RegExp(r'(?:^|[^\d])(\d{1,2})\s*月\s*(\d{1,2})\s*(?:日|号)')
      .firstMatch(text);
  if (monthDay != null) {
    final month = int.parse(monthDay.group(1)!);
    final year = month > now.month ? now.year - 1 : now.year;
    final period = exactDayPeriod(year, month, int.parse(monthDay.group(2)!));
    if (period != null) return period;
  }
  final explicitYearMonth = RegExp(
    r'(?:^|[^\d])(\d{4})\s*年\s*(0?[1-9]|1[0-2])\s*月(?:份)?(?!\s*\d{1,2}\s*(?:日|号))',
  ).firstMatch(text);
  if (explicitYearMonth != null) {
    final year = int.parse(explicitYearMonth.group(1)!);
    final month = int.parse(explicitYearMonth.group(2)!);
    return _TimeLogPeriod(
      label: '$year年$month月',
      start: DateTime(year, month),
      end: DateTime(year, month + 1),
    );
  }
  final relativeYearMonth = RegExp(
    r'(今年|去年)\s*(0?[1-9]|1[0-2])\s*月(?:份)?(?!\s*\d{1,2}\s*(?:日|号))',
  ).firstMatch(text);
  if (relativeYearMonth != null) {
    final year = relativeYearMonth.group(1) == '去年' ? now.year - 1 : now.year;
    final month = int.parse(relativeYearMonth.group(2)!);
    return _TimeLogPeriod(
      label: '$year年$month月',
      start: DateTime(year, month),
      end: DateTime(year, month + 1),
    );
  }
  final monthOnly = RegExp(
    r'(?:^|[^\d])(0?[1-9]|1[0-2])\s*月(?:份)?(?!\s*\d{1,2}\s*(?:日|号))',
  ).firstMatch(text);
  if (monthOnly != null) {
    final month = int.parse(monthOnly.group(1)!);
    final year = month > now.month ? now.year - 1 : now.year;
    return _TimeLogPeriod(
      label: '$year年$month月',
      start: DateTime(year, month),
      end: DateTime(year, month + 1),
    );
  }
  final explicitQuarter = RegExp(
    r'(?:(今年|去年)\s*|(\d{4})\s*年\s*)?(?:第\s*)?([一二三四1-4])\s*季度',
  ).firstMatch(text);
  if (explicitQuarter != null) {
    final quarter = switch (explicitQuarter.group(3)) {
      '一' || '1' => 1,
      '二' || '2' => 2,
      '三' || '3' => 3,
      '四' || '4' => 4,
      _ => throw const FormatException('无效季度'),
    };
    final currentQuarter = ((now.month - 1) ~/ 3) + 1;
    final explicitYear = explicitQuarter.group(2);
    final relativeYear = explicitQuarter.group(1);
    final year = explicitYear != null
        ? int.parse(explicitYear)
        : relativeYear == '今年'
        ? now.year
        : relativeYear == '去年'
        ? now.year - 1
        : quarter > currentQuarter
        ? now.year - 1
        : now.year;
    final start = DateTime(year, (quarter - 1) * 3 + 1);
    final end = year == now.year && quarter == currentQuarter
        ? AppTimeFormats.localDayStartOffset(todayStart, 1)
        : DateTime(year, start.month + 3);
    return _TimeLogPeriod(label: '$year年第$quarter季度', start: start, end: end);
  }
  final explicitYear = RegExp(
    r'(?:^|[^\d])(\d{4})\s*年(?:份)?(?!\s*(?:\d{1,2}\s*月|第?\s*[一二三四1-4]\s*季度))',
  ).firstMatch(text);
  if (explicitYear != null) {
    final year = int.parse(explicitYear.group(1)!);
    return _TimeLogPeriod(
      label: '$year年',
      start: DateTime(year),
      end: year == now.year
          ? AppTimeFormats.localDayStartOffset(todayStart, 1)
          : DateTime(year + 1),
    );
  }
  if (_matchesAny(text, [
    '最近一年',
    '最近1年',
    '最近12个月',
    '过去一年',
    '过去1年',
    '过去12个月',
    '近一年',
    '近1年',
    '近12个月',
  ])) {
    final previousYear = todayStart.year - 1;
    final previousYearMonthEnd = DateTime(
      previousYear,
      todayStart.month + 1,
      0,
    ).day;
    final start = DateTime(
      previousYear,
      todayStart.month,
      todayStart.day > previousYearMonthEnd
          ? previousYearMonthEnd
          : todayStart.day,
    );
    return _TimeLogPeriod(
      label: '最近一年',
      start: start,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('上上个月') || text.contains('上上月')) {
    return _TimeLogPeriod(
      label: '上上个月',
      start: DateTime(now.year, now.month - 2),
      end: DateTime(now.year, now.month - 1),
    );
  }
  if (text.contains('上个月') || text.contains('上月')) {
    return _TimeLogPeriod(
      label: '上个月',
      start: DateTime(now.year, now.month - 1),
      end: DateTime(now.year, now.month),
    );
  }
  _TimeLogPeriod relativeDay(int offset, String label) {
    final start = AppTimeFormats.localDayStartOffset(todayStart, offset);
    return _TimeLogPeriod(
      label: label,
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 1),
    );
  }

  if (text.contains('大前天') || text.contains('大前日')) {
    return relativeDay(-3, '大前天');
  }
  if (text.contains('前天') || text.contains('前日')) {
    return relativeDay(-2, '前天');
  }
  if (text.contains('大后天') || text.contains('大后日')) {
    return relativeDay(3, '大后天');
  }
  if (text.contains('后天') || text.contains('后日')) {
    return relativeDay(2, '后天');
  }
  if (text.contains('明天') || text.contains('明日')) {
    return relativeDay(1, '明天');
  }
  if (text.contains('今天') || text.contains('今日')) {
    return _TimeLogPeriod(
      label: '今日',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('昨天') || text.contains('昨日')) {
    final start = AppTimeFormats.localDayStartOffset(todayStart, -1);
    return _TimeLogPeriod(label: '昨日', start: start, end: todayStart);
  }
  if (_matchesAny(text, ['上上周', '上上星期', '上上礼拜'])) {
    final thisWeekStart = AppTimeFormats.localDayStartOffset(
      todayStart,
      -(now.weekday - DateTime.monday),
    );
    final end = AppTimeFormats.localDayStartOffset(thisWeekStart, -7);
    return _TimeLogPeriod(
      label: '上上周',
      start: AppTimeFormats.localDayStartOffset(end, -7),
      end: end,
    );
  }
  if (text.contains('上周') || text.contains('上星期') || text.contains('上礼拜')) {
    final thisWeekStart = AppTimeFormats.localDayStartOffset(
      todayStart,
      -(now.weekday - DateTime.monday),
    );
    final start = AppTimeFormats.localDayStartOffset(thisWeekStart, -7);
    return _TimeLogPeriod(label: '上周', start: start, end: thisWeekStart);
  }
  final recentDayRange = _resolveRecentDayRange(text, now);
  if (recentDayRange != null) {
    return _TimeLogPeriod(
      label: recentDayRange.label,
      start: recentDayRange.start,
      end: recentDayRange.end,
    );
  }
  final currentQuarterStart = DateTime(
    now.year,
    ((now.month - 1) ~/ 3) * 3 + 1,
  );
  if (_matchesAny(text, ['上上季度', '上上个季度'])) {
    return _TimeLogPeriod(
      label: '上上季度',
      start: DateTime(currentQuarterStart.year, currentQuarterStart.month - 6),
      end: DateTime(currentQuarterStart.year, currentQuarterStart.month - 3),
    );
  }
  if (_matchesAny(text, ['上季度', '上一季度', '上个季度', '前一季度'])) {
    return _TimeLogPeriod(
      label: '上季度',
      start: DateTime(currentQuarterStart.year, currentQuarterStart.month - 3),
      end: currentQuarterStart,
    );
  }
  if (_matchesAny(text, ['本季度', '这个季度', '当前季度', '这季度'])) {
    return _TimeLogPeriod(
      label: '本季度',
      start: currentQuarterStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('去年')) {
    return _TimeLogPeriod(
      label: '去年',
      start: DateTime(now.year - 1),
      end: DateTime(now.year),
    );
  }
  if (text.contains('今年')) {
    return _TimeLogPeriod(
      label: '今年',
      start: DateTime(now.year),
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('本周') || text.contains('这周')) {
    final start = AppTimeFormats.localDayStartOffset(
      todayStart,
      -(now.weekday - 1),
    );
    return _TimeLogPeriod(
      label: '本周',
      start: start,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('本月') || text.contains('这个月')) {
    final start = DateTime(now.year, now.month);
    return _TimeLogPeriod(
      label: '本月',
      start: start,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  return null;
}

bool _focusOverlapsPeriod(_FocusRecord record, _TimeLogPeriod period) {
  final periodStart = period.start.millisecondsSinceEpoch;
  final periodEnd = period.end.millisecondsSinceEpoch;
  return record.focusIntervals.any(
    (interval) => interval.endMs > periodStart && interval.startMs < periodEnd,
  );
}

int _focusOverlapSeconds(_FocusRecord record, _TimeLogPeriod period) {
  final periodStart = period.start.millisecondsSinceEpoch;
  final periodEnd = period.end.millisecondsSinceEpoch;
  return record.focusIntervals.fold<int>(0, (sum, interval) {
    final start = interval.startMs > periodStart
        ? interval.startMs
        : periodStart;
    final end = interval.endMs < periodEnd ? interval.endMs : periodEnd;
    return end <= start ? sum : sum + (end - start) ~/ 1000;
  });
}

_DateRange? _resolveExplicitDateRange(String text) {
  final match = _explicitIsoDateRangePattern.firstMatch(text);
  if (match == null) return null;
  final start = _parseStrictIsoDate(match.group(1)!);
  final end = _parseStrictIsoDate(match.group(2)!);
  if (start == null || end == null) return null;
  if (end.isBefore(start)) return null;
  return _DateRange(
    label: '自定义',
    start: start,
    end: AppTimeFormats.localDayStartOffset(end, 1),
  );
}

_TimeLogPeriod? _parseExplicitChineseDateRange(
  RegExpMatch match,
  DateTime now,
) {
  final startMonth = _parseChineseOrNumericDateNumber(match.group(2)!);
  final startDay = _parseChineseOrNumericDateNumber(match.group(3)!);
  final endMonth = _parseChineseOrNumericDateNumber(match.group(5)!);
  final endDay = _parseChineseOrNumericDateNumber(match.group(6)!);
  if (startMonth == null ||
      startDay == null ||
      endMonth == null ||
      endDay == null) {
    return null;
  }
  final startYearText = match.group(1);
  final endYearText = match.group(4);

  int startYear;
  if (startYearText != null) {
    startYear = int.parse(startYearText);
  } else if (endYearText != null) {
    final endYear = int.parse(endYearText);
    startYear = _monthDayIsAfter(startMonth, startDay, endMonth, endDay)
        ? endYear - 1
        : endYear;
  } else {
    startYear = startMonth > now.month ? now.year - 1 : now.year;
  }

  final start = _parseStrictCalendarDate(startYear, startMonth, startDay);
  if (start == null) return null;

  final endYear = endYearText == null
      ? startYear +
            (_monthDayIsAfter(startMonth, startDay, endMonth, endDay) ? 1 : 0)
      : int.parse(endYearText);
  final inclusiveEnd = _parseStrictCalendarDate(endYear, endMonth, endDay);
  if (inclusiveEnd == null || inclusiveEnd.isBefore(start)) return null;

  return _TimeLogPeriod(
    label: '自定义',
    start: start,
    end: AppTimeFormats.localDayStartOffset(inclusiveEnd, 1),
  );
}

bool _monthDayIsAfter(
  int leftMonth,
  int leftDay,
  int rightMonth,
  int rightDay,
) => leftMonth > rightMonth || (leftMonth == rightMonth && leftDay > rightDay);

DateTime? _parseStrictCalendarDate(int year, int month, int day) {
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

DateTime? _parseExplicitChineseDate(
  RegExpMatch match,
  String text,
  DateTime now,
) {
  final yearText = match.group(1);
  final month = _parseChineseOrNumericDateNumber(match.group(2)!);
  final day = _parseChineseOrNumericDateNumber(match.group(3)!);
  if (month == null || day == null) return null;
  final year = yearText == null
      ? _inferredChineseDateYear(text, match.start, month, now)
      : int.parse(yearText);
  return _parseStrictCalendarDate(year, month, day);
}

int _inferredChineseDateYear(
  String text,
  int dateStart,
  int month,
  DateTime now,
) {
  final prefix = text.substring(0, dateStart);
  if (RegExp(r'去年\s*$').hasMatch(prefix)) return now.year - 1;
  if (RegExp(r'今年\s*$').hasMatch(prefix)) return now.year;
  return month > now.month ? now.year - 1 : now.year;
}

bool _hasUnsupportedExplicitDate(String text, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final isoDateMatches = _explicitIsoDatePattern.allMatches(text).toList();
  final isoRanges = _explicitIsoDateRangePattern.allMatches(text).toList();
  final chineseDateMatches = _explicitChineseDatePattern
      .allMatches(text)
      .toList();
  final chineseRanges = _explicitChineseDateRangePattern
      .allMatches(text)
      .toList();
  final ranges = isoRanges.length + chineseRanges.length;

  bool isInsideRange(RegExpMatch date, Iterable<RegExpMatch> candidates) =>
      candidates.any(
        (range) => range.start <= date.start && range.end >= date.end,
      );

  final standaloneIsoDates = isoDateMatches
      .where((date) => !isInsideRange(date, isoRanges))
      .toList();
  final standaloneChineseDates = chineseDateMatches
      .where((date) => !isInsideRange(date, chineseRanges))
      .toList();

  // Focus context supports one explicit date/range. Reject comparisons
  // instead of silently injecting only the first period's data.
  if (ranges > 1 ||
      (ranges == 1 &&
          (standaloneIsoDates.isNotEmpty ||
              standaloneChineseDates.isNotEmpty)) ||
      (ranges == 0 &&
          standaloneIsoDates.length + standaloneChineseDates.length > 1)) {
    return true;
  }

  for (final range in isoRanges) {
    final start = _parseStrictIsoDate(range.group(1)!);
    final end = _parseStrictIsoDate(range.group(2)!);
    if (start == null || end == null || end.isBefore(start)) return true;
  }

  for (final range in chineseRanges) {
    if (_parseExplicitChineseDateRange(range, current) == null) return true;
  }

  if (standaloneChineseDates.any(
    (match) => _parseExplicitChineseDate(match, text, current) == null,
  )) {
    return true;
  }

  return standaloneIsoDates.any(
    (match) => _parseStrictIsoDate(match.group(1)!) == null,
  );
}

bool _hasAmbiguousMonthPeriods(String text) {
  final monthPeriods = _monthPeriodPattern.allMatches(text).length;
  final rollingMonthRanges = _rollingMonthRangePattern.allMatches(text);
  if (rollingMonthRanges.any((match) {
    final months = _parseRollingMonthCount(match.group(1) ?? '6');
    return months == null || months < 1;
  })) {
    return true;
  }
  final rollingMonthCount = rollingMonthRanges.length;
  if (_explicitIsoDateRangePattern.hasMatch(text) ||
      _explicitChineseDateRangePattern.hasMatch(text)) {
    return monthPeriods > 0 || rollingMonthCount > 0;
  }
  final explicitDays =
      _explicitIsoDatePattern.allMatches(text).length +
      _explicitChineseDatePattern.allMatches(text).length;
  return monthPeriods + rollingMonthCount + explicitDays > 1;
}

bool _hasMultipleRecognizedDatePeriods(String text) {
  final periodText = text.replaceAll(RegExp(r'(?:并)?扩大到未来30天范围'), '');
  final spans = <(int, int)>[];
  for (final pattern in [
    _explicitIsoDateRangePattern,
    _explicitChineseDateRangePattern,
    _explicitIsoDatePattern,
    _explicitChineseDatePattern,
    _monthPeriodPattern,
    _rollingMonthRangePattern,
    _relativeDayRangePattern,
    _relativeWeekPeriodPattern,
    _relativeQuarterPeriodPattern,
    _relativeYearPeriodPattern,
    _relativeYearQualifiedDatePattern,
    _relativeSingleDayPeriodPattern,
    _futureDaysRangePattern,
  ]) {
    spans.addAll(
      pattern.allMatches(periodText).map((match) => (match.start, match.end)),
    );
  }
  spans.sort((first, second) {
    final startOrder = first.$1.compareTo(second.$1);
    return startOrder != 0 ? startOrder : second.$2.compareTo(first.$2);
  });

  var distinctPeriods = 0;
  var currentEnd = -1;
  for (final span in spans) {
    if (span.$1 >= currentEnd) {
      distinctPeriods++;
      currentEnd = span.$2;
    } else if (span.$2 > currentEnd) {
      currentEnd = span.$2;
    }
  }
  return distinctPeriods > 1;
}

int? _parseRollingMonthCount(String value) =>
    int.tryParse(value) ?? _parseSimpleChineseNumber(value);

int? _parseChineseOrNumericDateNumber(String value) =>
    int.tryParse(value) ?? _parseSimpleChineseNumber(value);

DateTime? _parseStrictIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

List<Map<String, dynamic>> _scopeTodosByTime(
  List<Map<String, dynamic>> todos, {
  String? userMessage,
  DateTime? now,
}) {
  final base = todos.toList();
  final message = userMessage ?? '';
  final nowValue = now ?? DateTime.now();
  final period = _resolveCoursePeriod(message, nowValue);
  if (period == null) return base;
  return base.where((t) {
    // Todo maps expose startTime as the creation timestamp for legacy
    // action snapshots. Date-scoped queries describe scheduled work, so
    // only a due/end date can place a todo in the requested range.
    final dueDate = _parseFlexibleDateTime(
      t['dueDate'] ?? t['due_date'] ?? t['endTime'] ?? t['end_time'],
    );
    if (dueDate == null) return false;
    return !dueDate.isBefore(period.start) && dueDate.isBefore(period.end);
  }).toList();
}

List<CountdownItem> _scopeCountdownsByTime(
  List<CountdownItem> countdowns, {
  String? userMessage,
  DateTime? now,
}) {
  final active = countdowns.where((c) => !c.isDeleted).toList();
  final message = userMessage ?? '';
  final nowValue = now ?? DateTime.now();
  final period = _resolveCountdownPeriod(message, nowValue);
  if (period == null) return active;
  return active.where((c) {
    final target = CalendarDateMath.dateOnly(c.targetDate);
    return !target.isBefore(period.start) && target.isBefore(period.end);
  }).toList();
}

_DateRange? _resolveCountdownPeriod(String text, DateTime now) {
  final explicit = _resolveExplicitDateRange(text);
  if (explicit != null) return explicit;
  final rollingMonthRange = _resolveRollingMonthRange(text, now);
  if (rollingMonthRange != null) return rollingMonthRange;
  final recentDayRange = _resolveRecentDayRange(text, now);
  if (recentDayRange != null) return recentDayRange;

  final todayStart = CalendarDateMath.dateOnly(now);
  if (text.contains('今天') || text.contains('今日')) {
    return _DateRange(
      label: '今日',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, 1),
    );
  }
  if (text.contains('明天') || text.contains('明日')) {
    final start = AppTimeFormats.localDayStartOffset(todayStart, 1);
    return _DateRange(
      label: '明日',
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 1),
    );
  }
  if (text.contains('本周') || text.contains('这周')) {
    final start = AppTimeFormats.localDayStartOffset(
      todayStart,
      -(now.weekday - 1),
    );
    return _DateRange(
      label: '本周',
      start: start,
      end: AppTimeFormats.localDayStartOffset(start, 7),
    );
  }
  if (text.contains('最近') || text.contains('近期')) {
    return _DateRange(
      label: '最近14天',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, 14),
    );
  }
  final futureDays = _parseFutureDays(text);
  if (futureDays != null) {
    return _DateRange(
      label: '未来$futureDays天',
      start: todayStart,
      end: AppTimeFormats.localDayStartOffset(todayStart, futureDays),
    );
  }
  return null;
}

List<TodoPlanBlock> _scopePlanBlocksByTime(
  List<TodoPlanBlock> blocks, {
  String? userMessage,
  DateTime? now,
}) {
  final active = blocks.where((b) => !b.isDeleted).toList();
  final message = userMessage ?? '';
  final nowValue = now ?? DateTime.now();
  final period = _resolveCoursePeriod(message, nowValue);
  if (period == null) return active;
  return active.where((b) {
    final start = DateTime.fromMillisecondsSinceEpoch(b.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(b.endTime);
    return _dateRangeOverlaps(period.start, period.end, start, end);
  }).toList();
}

bool _dateRangeOverlaps(
  DateTime pStart,
  DateTime pEnd,
  DateTime itemStart,
  DateTime itemEnd,
) {
  return itemEnd.isAfter(pStart) && itemStart.isBefore(pEnd);
}

DateTime? _parseFlexibleDateTime(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) {
    if (numeric > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numeric);
    }
    if (numeric > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
    }
  }
  return DateTime.tryParse(text);
}

class _TimeLogPeriod {
  const _TimeLogPeriod({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}

class AiContextDateRange {
  const AiContextDateRange(this.start, this.endExclusive);

  final DateTime start;
  final DateTime endExclusive;
}

class _FocusRecord {
  const _FocusRecord({
    required this.id,
    required this.title,
    required this.source,
    required this.startMs,
    required this.endMs,
    required this.focusIntervals,
    this.status,
  });

  factory _FocusRecord.fromTimeLog(TimeLogItem log) {
    return _FocusRecord(
      id: log.id,
      title: log.title,
      source: '补录',
      startMs: log.startTime,
      endMs: log.endTime,
      focusIntervals: log.endTime > log.startTime
          ? [_FocusInterval(log.startTime, log.endTime)]
          : const [],
    );
  }

  factory _FocusRecord.fromPomodoro(PomodoroRecord record) {
    final totalPauseSeconds = record.totalPauseSeconds ?? 0;
    final pauseSeconds = totalPauseSeconds > 0 ? totalPauseSeconds : 0;
    final endMs =
        record.endTime ??
        record.startTime + (record.effectiveDuration + pauseSeconds) * 1000;
    final pauses = record.pauseIntervals;
    final focusIntervals = pauses != null && pauses.isNotEmpty
        ? _subtractPauseIntervals(record.startTime, endMs, pauses)
        : _fallbackPomodoroFocusInterval(
            record.startTime,
            endMs,
            record.effectiveDuration,
          );
    return _FocusRecord(
      id: record.uuid,
      title: record.todoTitle?.isNotEmpty == true ? record.todoTitle! : '番茄钟',
      source: '番茄钟',
      startMs: record.startTime,
      endMs: endMs,
      focusIntervals: focusIntervals,
      status: record.isCompleted ? '已完成' : '已中断',
    );
  }

  final String id;
  final String title;
  final String source;
  final int startMs;
  final int endMs;
  final List<_FocusInterval> focusIntervals;
  final String? status;

  int get minutes =>
      (focusIntervals.fold<int>(0, (sum, interval) => sum + interval.seconds) /
              60)
          .round();
}

class _FocusInterval {
  const _FocusInterval(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  int get seconds => (endMs - startMs) ~/ 1000;
}

List<_FocusInterval> _subtractPauseIntervals(
  int startMs,
  int endMs,
  List<PauseInterval> pauses,
) {
  if (endMs <= startMs) return const [];
  final orderedPauses = pauses.toList()
    ..sort((left, right) => left.startMs.compareTo(right.startMs));
  final focusIntervals = <_FocusInterval>[];
  var cursor = startMs;
  for (final pause in orderedPauses) {
    final pauseStart = pause.startMs < startMs ? startMs : pause.startMs;
    final rawPauseEnd = pause.endMs ?? endMs;
    final pauseEnd = rawPauseEnd > endMs ? endMs : rawPauseEnd;
    if (pauseEnd <= cursor || pauseStart >= endMs) continue;
    if (pauseStart > cursor) {
      focusIntervals.add(_FocusInterval(cursor, pauseStart));
    }
    if (pauseEnd > cursor) cursor = pauseEnd;
    if (cursor >= endMs) break;
  }
  if (cursor < endMs) focusIntervals.add(_FocusInterval(cursor, endMs));
  return focusIntervals;
}

List<_FocusInterval> _fallbackPomodoroFocusInterval(
  int startMs,
  int endMs,
  int effectiveDurationSeconds,
) {
  if (effectiveDurationSeconds <= 0 || endMs <= startMs) return const [];
  final effectiveEndMs = startMs + effectiveDurationSeconds * 1000;
  final focusEndMs = effectiveEndMs < endMs ? effectiveEndMs : endMs;
  return focusEndMs > startMs
      ? [_FocusInterval(startMs, focusEndMs)]
      : const [];
}

class _DateRange {
  const _DateRange({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}
