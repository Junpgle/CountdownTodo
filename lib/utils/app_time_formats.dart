import 'package:intl/intl.dart';

class AppTimeFormats {
  const AppTimeFormats._();

  static String format(
    DateTime time,
    String pattern, {
    String? locale,
  }) {
    return DateFormat(pattern, locale).format(time);
  }

  static String safeFormat(
    DateTime time,
    String pattern, {
    String? locale,
    String fallbackPattern = 'yyyy-MM-dd',
  }) {
    try {
      return format(time, pattern, locale: locale);
    } catch (_) {
      return format(time, fallbackPattern, locale: locale);
    }
  }

  static DateTime dayStart(DateTime time) {
    return DateTime(time.year, time.month, time.day);
  }

  static bool isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static String dayKey(DateTime time) => format(time, 'yyyyMMdd');

  static String date(DateTime time) => format(time, 'yyyy-MM-dd');

  static String dateCn(DateTime time) => format(time, 'yyyy年MM月dd日');

  static String monthDayCn(DateTime time) => format(time, 'MM月dd日');

  static String monthDaySlash(DateTime time) => format(time, 'MM/dd');

  static String compactDateTime(DateTime time) => format(time, 'MM-dd HH:mm');

  static String fullDateTime(DateTime time) => format(time, 'yyyy-MM-dd HH:mm');

  static String clock(DateTime time) => format(time, 'HH:mm');

  static String range(
    DateTime start,
    DateTime end, {
    String pattern = 'HH:mm',
    String separator = ' - ',
  }) {
    return '${format(start, pattern)}$separator${format(end, pattern)}';
  }

  static DateTime localFromTimestamp(int timestamp, {bool isUtc = false}) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: isUtc)
        .toLocal();
  }

  static DateTime localFromServerTimestamp(int timestamp) {
    return localFromTimestamp(timestamp, isUtc: true);
  }

  static int toServerTimestamp(DateTime local) {
    return local.toUtc().millisecondsSinceEpoch;
  }

  static String formatServerTimestamp(
    int? timestamp, {
    String pattern = 'MM-dd HH:mm',
  }) {
    if (timestamp == null) return '';
    return format(localFromServerTimestamp(timestamp), pattern);
  }

  static String relativeFromServerTimestamp(int timestamp) {
    final now = DateTime.now();
    final date = localFromServerTimestamp(timestamp);
    final days = dayStart(date).difference(dayStart(now)).inDays;

    if (days == 0) return '今天 ${clock(date)}';
    if (days == 1) return '明天 ${clock(date)}';
    if (days == -1) return '昨天 ${clock(date)}';

    return formatServerTimestamp(timestamp);
  }
}
