import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// ── 时间格式化工具函数 ──────────────────────────────────────

/// 中文时长格式（输入秒）：1小时30分 / 5分20秒 / 30秒
String formatDurationChinese(int totalSeconds) {
  if (totalSeconds <= 0) return '0秒';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '$h小时${m > 0 ? "$m分" : ""}';
  if (m > 0) return '$m分${s > 0 ? "$s秒" : ""}';
  return '$s秒';
}

/// 中文时长格式（输入分钟）：1小时30分钟 / 45分钟
String formatMinutesChinese(int minutes) {
  if (minutes <= 0) return '0分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '$h小时$m分钟';
  if (h > 0) return '$h小时';
  return '$m分钟';
}

/// 时钟格式 MM:SS（输入秒）
String formatTimerMMSS(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0;
  final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final ss = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// 紧凑中文格式（输入秒）：2时30分 / 1时 / 45分 / 30秒
String formatDurationCompact(int totalSeconds) {
  if (totalSeconds <= 0) return '0分';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0 && m > 0) return '$h时$m分';
  if (h > 0) return '$h时';
  if (m > 0) return '$m分';
  return '$s秒';
}

/// 英文缩写格式（输入秒）：2h 30m / 5m 20s
String formatDurationEnglish(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${totalSeconds % 60}s';
}

/// 倒计时显示格式（输入秒）：>60s 显示 25'，<=60s 显示 MM:SS
String formatCountdown(int totalSeconds) {
  if (totalSeconds > 60) {
    return "${((totalSeconds / 60).ceil())}'";
  }
  return formatTimerMMSS(totalSeconds);
}

// ── 日期时间格式化 ──────────────────────────────────────────

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

// ── 时区工具 ────────────────────────────────────────────────

class TimezoneUtils {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// 将服务器 UTC 时间戳转换为设备本地显示时间
  static String formatToLocal(int? timestamp,
      {String pattern = 'MM-dd HH:mm'}) {
    return AppTimeFormats.formatServerTimestamp(timestamp, pattern: pattern);
  }

  /// 计算物理时差提示
  static String getTimeZoneLabel() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inHours;
    final sign = offset >= 0 ? '+' : '';
    return 'GMT$sign$offset';
  }

  /// 将本地 DateTime 转换为准 UTC 时间戳供上传
  static int toServerTimestamp(DateTime local) {
    return AppTimeFormats.toServerTimestamp(local);
  }

  /// 获取更易读的相对时间（今天/明天/昨天）并进行时区对齐
  static String getRelativeTime(int timestamp) {
    init();
    return AppTimeFormats.relativeFromServerTimestamp(timestamp);
  }
}
