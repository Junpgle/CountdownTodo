import 'package:timezone/data/latest.dart' as tz_data;

import 'app_time_formats.dart';

class TimezoneUtils {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// 🚀 Uni-Sync 核心：将服务器 UTC 时间戳转换为设备本地显示时间
  static String formatToLocal(int? timestamp,
      {String pattern = 'MM-dd HH:mm'}) {
    return AppTimeFormats.formatServerTimestamp(timestamp, pattern: pattern);
  }

  /// 🚀 Uni-Sync 核心：计算物理时差提示
  /// 如果当前时区与 UTC 偏离较大，返回时区名或偏移量标识
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
