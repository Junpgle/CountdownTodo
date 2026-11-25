part of '../screen_time_detail_screen.dart';

// ─── 静态工具 ───
String _stFormatHM(int s) {
  if (s == 0) return "0分钟";
  int h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  if (h > 0) return "$h小时 $m分钟";
  if (m > 0) return "$m分钟";
  return "$sec秒";
}

String _stFormatShortHM(int s) {
  if (s == 0) return "0分";
  int h = s ~/ 3600, m = (s % 3600) ~/ 60;
  if (h > 0) return "$h时$m分";
  if (m > 0) return "$m分";
  return "$s秒";
}

final RegExp _legacyDeviceIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _stSimplifyDeviceName(String device) {
  if (device.isEmpty) return "未知设备";
  if (_legacyDeviceIdPattern.hasMatch(device)) {
    return "未知设备(旧)";
  }
  return device
      .replaceAll("(Phone)", "(手机)")
      .replaceAll("(Tablet)", "(平板)")
      .replaceAll("(PC)", "(电脑)")
      .replaceAll("(Desktop)", "(电脑)");
}

IconData _stGetDeviceIcon(String device) {
  String l = device.toLowerCase();
  if (l.contains("phone") ||
      l.contains("手机") ||
      l.contains("ios") ||
      l.contains("android")) {
    return Icons.smartphone_rounded;
  }
  if (l.contains("tablet") || l.contains("平板") || l.contains("ipad")) {
    return Icons.tablet_android_rounded;
  }
  if (l.contains("windows") ||
      l.contains("pc") ||
      l.contains("lapt") ||
      l.contains("mac") ||
      l.contains("电脑")) {
    return Icons.laptop_windows_rounded;
  }
  return Icons.devices_rounded;
}

IconData _stGetCategoryIcon(String cat) {
  switch (cat) {
    case '社交通讯':
      return Icons.chat_bubble_rounded;
    case '影音娱乐':
      return Icons.play_circle_filled_rounded;
    case '学习办公':
      return Icons.menu_book_rounded;
    case '实用工具':
      return Icons.build_rounded;
    case '购物支付':
      return Icons.shopping_bag_rounded;
    case '导航出行':
      return Icons.map_rounded;
    case '游戏与辅助':
      return Icons.sports_esports_rounded;
    case '健康运动':
      return Icons.directions_run_rounded;
    case '系统应用':
      return Icons.settings_rounded;
    case '其他类别':
      return Icons.more_horiz_rounded;
    default:
      return Icons.apps_rounded;
  }
}

String _stGetCategoryForApp(
  String appName,
  String? backendCategory,
  Map<String, String> mappings,
) {
  if (mappings.containsKey(appName) && mappings[appName] != '未分类') {
    return mappings[appName]!;
  }
  if (backendCategory != null && backendCategory != '未分类') {
    return backendCategory;
  }
  String l = appName.toLowerCase();
  if (l.contains('微信') ||
      l.contains('qq') ||
      l.contains('小红书') ||
      l.contains('短信') ||
      l.contains('微博')) {
    return '社交通讯';
  }
  if (l.contains('抖音') ||
      l.contains('哔哩') ||
      l.contains('bilibili') ||
      l.contains('音乐') ||
      l.contains('视频') ||
      l.contains('直播')) {
    return '影音娱乐';
  }
  if (l.contains('豆包') ||
      l.contains('千问') ||
      l.contains('word') ||
      l.contains('excel') ||
      l.contains('studio') ||
      l.contains('笔记') ||
      l.contains('工大')) {
    return '学习办公';
  }
  if (l.contains('计算器') ||
      l.contains('天气') ||
      l.contains('浏览') ||
      l.contains('edge') ||
      l.contains('chrome') ||
      l.contains('管家') ||
      l.contains('设置')) {
    return '实用工具';
  }
  if (l.contains('淘宝') ||
      l.contains('拼多多') ||
      l.contains('京东') ||
      l.contains('支付宝') ||
      l.contains('闲鱼') ||
      l.contains('美团')) {
    return '购物支付';
  }
  if (l.contains('地图') ||
      l.contains('12306') ||
      l.contains('出行') ||
      l.contains('导航') ||
      l.contains('公交')) {
    return '导航出行';
  }
  if (l.contains('游戏') ||
      l.contains('原神') ||
      l.contains('王者') ||
      l.contains('米游') ||
      l.contains('启动器')) {
    return '游戏与辅助';
  }
  if (l.contains('健康') || l.contains('运动') || l.contains('手环')) return '健康运动';
  if (l.contains('桌面') ||
      l.contains('系统') ||
      l.contains('小爱') ||
      l.contains('账号')) {
    return '系统应用';
  }
  return '未分类';
}

List<MapEntry<String, Map<String, dynamic>>> _stGetGroupedApps(
  List<dynamic> filteredStats,
) {
  Map<String, Map<String, dynamic>> grouped = {};
  for (var item in filteredStats) {
    String appName = item['app_name'] ?? "未知应用";
    String deviceName = item['device_name'] ?? "未知设备";
    int duration = item['duration'] ?? 0;
    final appGroup = grouped.putIfAbsent(
      appName,
      () => {'total': 0, 'devices': <String, int>{}},
    );
    appGroup['total'] = (appGroup['total'] as int) + duration;
    final devices = appGroup['devices'] as Map<String, int>;
    devices[deviceName] = (devices[deviceName] ?? 0) + duration;
  }
  var sorted = grouped.entries.toList();
  sorted.sort(
    (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
  );
  return sorted;
}

DateTime _dateOnly(DateTime date) => CalendarDateMath.dateOnly(date);

DateTime _startOfWeek(DateTime date) {
  return CalendarDateMath.weekRange(date).start;
}

DateTime _periodStart(DateTime date, ScreenTimeRange range) {
  final normalized = _dateOnly(date);
  switch (range) {
    case ScreenTimeRange.day:
      return normalized;
    case ScreenTimeRange.week:
      return _startOfWeek(normalized);
    case ScreenTimeRange.month:
      return DateTime(normalized.year, normalized.month);
  }
}

DateTime _periodEnd(DateTime periodStart, ScreenTimeRange range) {
  switch (range) {
    case ScreenTimeRange.day:
      return periodStart;
    case ScreenTimeRange.week:
      return CalendarDateMath.addDays(periodStart, 6);
    case ScreenTimeRange.month:
      return DateTime(periodStart.year, periodStart.month + 1, 0);
  }
}

DateTime _previousPeriodStart(DateTime periodStart, ScreenTimeRange range) {
  switch (range) {
    case ScreenTimeRange.day:
      return CalendarDateMath.addDays(periodStart, -1);
    case ScreenTimeRange.week:
      return CalendarDateMath.addDays(periodStart, -7);
    case ScreenTimeRange.month:
      return DateTime(periodStart.year, periodStart.month - 1);
  }
}

DateTime _shiftPeriod(DateTime periodStart, ScreenTimeRange range, int offset) {
  switch (range) {
    case ScreenTimeRange.day:
      return CalendarDateMath.addDays(periodStart, offset);
    case ScreenTimeRange.week:
      return CalendarDateMath.addDays(periodStart, offset * 7);
    case ScreenTimeRange.month:
      return DateTime(periodStart.year, periodStart.month + offset);
  }
}

String _historyKey(DateTime date) =>
    AppTimeFormats.dateFormatter('yyyy-MM-dd').format(date);

Iterable<DateTime> _daysInPeriod(
  DateTime periodStart,
  ScreenTimeRange range,
  DateTime today,
) sync* {
  final end = _periodEnd(periodStart, range);
  final cappedEnd = end.isAfter(today) ? today : end;
  yield* CalendarDateMath.datesBetweenInclusive(periodStart, cappedEnd);
}

String _periodLabel(
  DateTime periodStart,
  ScreenTimeRange range,
  DateTime today,
) {
  switch (range) {
    case ScreenTimeRange.day:
      return periodStart == today
          ? "今日"
          : AppTimeFormats.dateFormatter('MM/dd').format(periodStart);
    case ScreenTimeRange.week:
      final thisWeek = _startOfWeek(today);
      final end = _periodEnd(periodStart, range);
      if (periodStart == thisWeek) return "本周";
      final dateFormat = AppTimeFormats.dateFormatter('MM/dd');
      return "${dateFormat.format(periodStart)}-${dateFormat.format(end)}";
    case ScreenTimeRange.month:
      if (periodStart.year == today.year && periodStart.month == today.month) {
        return "本月";
      }
      return AppTimeFormats.dateFormatter('yyyy/MM').format(periodStart);
  }
}

String _compareText(ScreenTimeRange range) {
  switch (range) {
    case ScreenTimeRange.day:
      return "较前一天";
    case ScreenTimeRange.week:
      return "较前一周";
    case ScreenTimeRange.month:
      return "较前一月";
  }
}

String _trendTitle(ScreenTimeRange range) {
  switch (range) {
    case ScreenTimeRange.day:
      return "近七日趋势";
    case ScreenTimeRange.week:
      return "近七周趋势";
    case ScreenTimeRange.month:
      return "近六月趋势";
  }
}

// ─── 设备分布小组件（复用） ───
Widget _stBuildDeviceBreakdown(Map<String, int> devices, bool isAllFilter) {
  if (!isAllFilter && devices.length == 1) {
    return Text(
      _stSimplifyDeviceName(devices.keys.first),
      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
  return Wrap(
    spacing: 8,
    runSpacing: 4,
    children: devices.entries
        .map(
          (e) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _stGetDeviceIcon(e.key),
                size: 11,
                color: Colors.blueGrey.shade300,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  "${_stSimplifyDeviceName(e.key)} ${_stFormatShortHM(e.value)}",
                  style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        )
        .toList(),
  );
}
