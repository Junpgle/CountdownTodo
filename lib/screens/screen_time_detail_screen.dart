import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../storage_service.dart';
import '../utils/page_transitions.dart';

// ─────────────────────────────────────────────
// 设备过滤枚举
// ─────────────────────────────────────────────
enum DeviceFilter { all, pc, mobile, phone, tablet }

extension DeviceFilterExtension on DeviceFilter {
  String get label {
    switch (this) {
      case DeviceFilter.all:
        return "聚合数据";
      case DeviceFilter.pc:
        return "电脑端";
      case DeviceFilter.mobile:
        return "移动端";
      case DeviceFilter.phone:
        return "手机";
      case DeviceFilter.tablet:
        return "平板";
    }
  }
}

// ─────────────────────────────────────────────
// 类别颜色映射
// ─────────────────────────────────────────────
Color _catColor(String cat) {
  switch (cat) {
    case '社交通讯':
      return const Color(0xFF5B6BE8);
    case '影音娱乐':
      return const Color(0xFFE84C88);
    case '学习办公':
      return const Color(0xFF0EB07A);
    case '实用工具':
      return const Color(0xFF9B6DE3);
    case '购物支付':
      return const Color(0xFFF09830);
    case '导航出行':
      return const Color(0xFF2FB5D6);
    case '游戏与辅助':
      return const Color(0xFFE85D30);
    case '健康运动':
      return const Color(0xFF28B463);
    case '系统应用':
      return const Color(0xFF7F8C8D);
    default:
      return const Color(0xFF95A5A6);
  }
}

// ─────────────────────────────────────────────
// 主界面
// ─────────────────────────────────────────────
class ScreenTimeDetailScreen extends StatefulWidget {
  final List<dynamic> todayStats;

  const ScreenTimeDetailScreen({super.key, required this.todayStats});

  @override
  State<ScreenTimeDetailScreen> createState() => _ScreenTimeDetailScreenState();

  static bool matchesFilter(String deviceName, DeviceFilter filter) {
    String lower = deviceName.toLowerCase();
    switch (filter) {
      case DeviceFilter.all:
        return true;
      case DeviceFilter.pc:
        return lower.contains("windows") ||
            lower.contains("pc") ||
            lower.contains("lapt") ||
            lower.contains("mac") ||
            lower.contains("电脑");
      case DeviceFilter.mobile:
        return lower.contains("phone") ||
            lower.contains("手机") ||
            lower.contains("tablet") ||
            lower.contains("平板") ||
            lower.contains("ipad") ||
            lower.contains("android") ||
            lower.contains("ios");
      case DeviceFilter.phone:
        return lower.contains("phone") ||
            lower.contains("手机") ||
            lower.contains("android") ||
            lower.contains("ios");
      case DeviceFilter.tablet:
        return lower.contains("tablet") ||
            lower.contains("平板") ||
            lower.contains("ipad");
    }
  }

  static List<dynamic> getFilteredStats(
      List<dynamic> rawStats, DeviceFilter filter) {
    return rawStats
        .where((item) => matchesFilter(item['device_name'] ?? "", filter))
        .toList();
  }

  static int getTotalDuration(List<dynamic> rawStats, DeviceFilter filter) {
    final filtered = getFilteredStats(rawStats, filter);
    return filtered.fold(0, (sum, item) => sum + (item['duration'] as int));
  }
}

class _ScreenTimeDetailScreenState extends State<ScreenTimeDetailScreen> {
  DeviceFilter _currentFilter = DeviceFilter.all;
  Map<String, List<dynamic>> _historyStats = {};
  Map<String, String> _cloudMappings = {};
  bool _isLoading = true;

  late DateTime _selectedDate;
  late DateTime _todayNormalized;

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    _todayNormalized = DateTime(now.year, now.month, now.day);
    _selectedDate = _todayNormalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadHistory();
      });
    });
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.getScreenTimeHistory();
    final mappings = await StorageService.getAppMappings();
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    history[todayStr] = widget.todayStats;
    if (mounted) {
      setState(() {
        _historyStats = history;
        _cloudMappings = mappings;
        _isLoading = false;
      });
    }
  }

  // ─── 静态工具 ───
  static String formatHM(int s) {
    if (s == 0) return "0分钟";
    int h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return "$h小时 $m分钟";
    if (m > 0) return "$m分钟";
    return "$sec秒";
  }

  static String formatShortHM(int s) {
    if (s == 0) return "0分";
    int h = s ~/ 3600, m = (s % 3600) ~/ 60;
    if (h > 0) return "$h时$m分";
    if (m > 0) return "$m分";
    return "$s秒";
  }

  static String simplifyDeviceName(String device) {
    if (device.isEmpty) return "未知设备";
    if (RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(device)) {
      return "未知设备(旧)";
    }
    return device
        .replaceAll("(Phone)", "(手机)")
        .replaceAll("(Tablet)", "(平板)")
        .replaceAll("(PC)", "(电脑)")
        .replaceAll("(Desktop)", "(电脑)");
  }

  static IconData getDeviceIcon(String device) {
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

  static IconData getCategoryIcon(String cat) {
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

  static String getCategoryForApp(
      String appName, String? backendCategory, Map<String, String> mappings) {
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

  static List<MapEntry<String, Map<String, dynamic>>> getGroupedApps(
      List<dynamic> filteredStats) {
    Map<String, Map<String, dynamic>> grouped = {};
    for (var item in filteredStats) {
      String appName = item['app_name'] ?? "未知应用";
      String deviceName = item['device_name'] ?? "未知设备";
      int duration = item['duration'] ?? 0;
      if (!grouped.containsKey(appName)) {
        grouped[appName] = {'total': 0, 'devices': <String, int>{}};
      }
      grouped[appName]!['total'] =
          (grouped[appName]!['total'] as int) + duration;
      (grouped[appName]!['devices'] as Map<String, int>)[deviceName] =
          ((grouped[appName]!['devices'] as Map<String, int>)[deviceName] ??
                  0) +
              duration;
    }
    var sorted = grouped.entries.toList();
    sorted.sort(
        (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));
    return sorted;
  }

  // ─── 设备分布小组件（复用） ───
  static Widget buildDeviceBreakdown(
      Map<String, int> devices, bool isAllFilter) {
    if (!isAllFilter && devices.length == 1) {
      return Text(simplifyDeviceName(devices.keys.first),
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: devices.entries
          .map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(getDeviceIcon(e.key),
                    size: 11, color: Colors.blueGrey.shade300),
                const SizedBox(width: 2),
                Flexible(
                    child: Text(
                        "${simplifyDeviceName(e.key)} ${formatShortHM(e.value)}",
                        style: const TextStyle(
                            fontSize: 10, color: Colors.blueGrey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]))
          .toList(),
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text("详细统计",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: _buildMainContent(),
              ),
            ),
    );
  }

  Widget _buildMainContent() {
    bool isToday = _selectedDate == _todayNormalized;
    String datePrefix =
        isToday ? "今日" : DateFormat('MM/dd').format(_selectedDate);

    String selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String prevDateStr = DateFormat('yyyy-MM-dd')
        .format(_selectedDate.subtract(const Duration(days: 1)));

    int selectedTotal = ScreenTimeDetailScreen.getTotalDuration(
        _historyStats[selectedDateStr] ?? [], _currentFilter);
    int prevTotal = ScreenTimeDetailScreen.getTotalDuration(
        _historyStats[prevDateStr] ?? [], _currentFilter);
    int diff = selectedTotal - prevTotal;

    final filteredStats = ScreenTimeDetailScreen.getFilteredStats(
        _historyStats[selectedDateStr] ?? [], _currentFilter);
    final topApps = getGroupedApps(filteredStats);

    // 分类
    Map<String, List<dynamic>> catGroups = {};
    for (var item in filteredStats) {
      String appName = item['app_name'] ?? '未知应用';
      String cat = getCategoryForApp(appName, item['category'], _cloudMappings);
      item['category'] = cat;
      catGroups.putIfAbsent(cat, () => []).add(item);
    }
    var catDurs = catGroups.entries.map((e) {
      int dur = e.value.fold(0, (sum, item) => sum + (item['duration'] as int));
      return MapEntry(e.key, dur);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    List<Map<String, dynamic>> finalCategories = [];
    if (catDurs.length <= 6) {
      for (var e in catDurs) {
        finalCategories.add(
            {'name': e.key, 'duration': e.value, 'items': catGroups[e.key]});
      }
    } else {
      for (int i = 0; i < 5; i++) {
        finalCategories.add({
          'name': catDurs[i].key,
          'duration': catDurs[i].value,
          'items': catGroups[catDurs[i].key]
        });
      }
      int otherDur = 0;
      List<dynamic> otherItems = [];
      for (int i = 5; i < catDurs.length; i++) {
        otherDur += catDurs[i].value;
        otherItems.addAll(catGroups[catDurs[i].key]!);
      }
      finalCategories
          .add({'name': '其他类别', 'duration': otherDur, 'items': otherItems});
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      final double w = constraints.maxWidth;
      final bool isDesktop = w >= 900;
      final bool isTablet = w >= 600 && w < 900;

      if (isDesktop) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 4,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFilters(
                            padding: const EdgeInsets.only(bottom: 12)),
                        Expanded(
                            child: SingleChildScrollView(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                              _buildHeroCard(selectedTotal, diff, datePrefix),
                              const SizedBox(height: 16),
                              _buildSectionHeader(
                                  "近七日趋势", Icons.bar_chart_rounded),
                              _buildChartCard(_todayNormalized, height: 280),
                            ]))),
                      ])),
              const SizedBox(width: 24),
              Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        if (finalCategories.isNotEmpty) ...[
                          _buildSectionHeader(
                              "$datePrefix类别分布", Icons.category_rounded),
                          _buildCategoryGrid(finalCategories,
                              crossAxisCount: 3, childAspectRatio: 1.1),
                          const SizedBox(height: 24),
                        ],
                        if (topApps.isNotEmpty) ...[
                          _buildSectionHeader(
                              "$datePrefix最常使用", Icons.dashboard_rounded),
                          _buildTopAppsGrid(topApps,
                              totalDur: selectedTotal,
                              crossAxisCount: 3,
                              childAspectRatio: 1.1,
                              maxItems: 6),
                          const SizedBox(height: 24),
                        ],
                        if (topApps.length > 6) ...[
                          _buildSectionHeader(
                              "其余应用明细", Icons.format_list_bulleted_rounded),
                          _buildRestList(topApps, skipCount: 6),
                        ],
                        const SizedBox(height: 40),
                      ]))),
            ]),
          ),
        );
      }

      int catCount = isTablet ? 6 : 3;
      int topCount = isTablet ? 4 : 2;
      int maxTop = 4;

      return SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildFilters(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
        _buildHeroCard(selectedTotal, diff, datePrefix),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildSectionHeader("近七日趋势", Icons.bar_chart_rounded),
              _buildChartCard(_todayNormalized, height: 200),
              const SizedBox(height: 20),
              if (finalCategories.isNotEmpty) ...[
                _buildSectionHeader("$datePrefix类别分布", Icons.category_rounded),
                _buildCategoryGrid(finalCategories,
                    crossAxisCount: catCount,
                    childAspectRatio: isTablet ? 0.9 : 1.0),
                const SizedBox(height: 20),
              ],
              if (topApps.isNotEmpty) ...[
                _buildSectionHeader("$datePrefix最常使用", Icons.dashboard_rounded),
                _buildTopAppsGrid(topApps,
                    totalDur: selectedTotal,
                    crossAxisCount: topCount,
                    childAspectRatio: isTablet ? 1.0 : 1.15,
                    maxItems: maxTop),
                const SizedBox(height: 20),
              ],
              if (topApps.length > maxTop) ...[
                _buildSectionHeader(
                    "其余应用明细", Icons.format_list_bulleted_rounded),
                _buildRestList(topApps, skipCount: maxTop),
              ],
              const SizedBox(height: 40),
            ])),
      ]));
    });
  }

  // ─────────────────────────────────────────────
  // 区块标题
  // ─────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 16, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // 过滤器
  // ─────────────────────────────────────────────
  Widget _buildFilters({EdgeInsetsGeometry padding = EdgeInsets.zero}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: DeviceFilter.values.length,
        itemBuilder: (ctx, i) {
          final filter = DeviceFilter.values[i];
          final selected = _currentFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              child: ChoiceChip(
                label: Text(filter.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: selected ? cs.onPrimary : cs.onSurfaceVariant)),
                selected: selected,
                onSelected: (v) {
                  if (v) setState(() => _currentFilter = filter);
                },
                shape: const StadiumBorder(),
                showCheckmark: false,
                selectedColor: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                side: BorderSide(
                    color: selected ? cs.primary : cs.outlineVariant, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Hero 总时长卡片
  // ─────────────────────────────────────────────
  Widget _buildHeroCard(int total, int diff, String datePrefix) {
    final cs = Theme.of(context).colorScheme;
    bool isIncrease = diff >= 0;
    Color diffColor =
        isIncrease ? const Color(0xFFB07820) : const Color(0xFF1A8C5E);
    IconData diffIcon =
        isIncrease ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withOpacity(0.08),
              cs.primary.withOpacity(0.02)
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.primary.withOpacity(0.15), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text("$datePrefix使用时长",
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(formatHM(total),
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                          height: 1.1)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(diffIcon, size: 15, color: diffColor),
                    const SizedBox(width: 4),
                    Text(
                        "较前一天${isIncrease ? '增加' : '减少'} ${formatHM(diff.abs())}",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: diffColor)),
                  ]),
                ])),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(Icons.access_time_filled_rounded,
                  size: 32, color: cs.primary),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 七日柱状图卡片
  // ─────────────────────────────────────────────
  Widget _buildChartCard(DateTime today, {double height = 200}) {
    List<int> dailyTotals = [];
    List<String> labels = [];
    for (int i = 6; i >= 0; i--) {
      DateTime d = today.subtract(Duration(days: i));
      dailyTotals.add(ScreenTimeDetailScreen.getTotalDuration(
          _historyStats[DateFormat('yyyy-MM-dd').format(d)] ?? [],
          _currentFilter));
      labels.add(i == 0 ? "今日" : DateFormat('MM/dd').format(d));
    }
    int selectedIndex = 6 - today.difference(_selectedDate).inDays;
    if (selectedIndex < 0 || selectedIndex > 6) selectedIndex = -1;

    return Container(
      decoration: _cardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: LayoutBuilder(builder: (ctx, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              double sectionWidth = constraints.maxWidth / 7;
              int tappedIndex =
                  (details.localPosition.dx / sectionWidth).floor();
              if (tappedIndex >= 0 && tappedIndex < 7) {
                setState(() {
                  _selectedDate =
                      today.subtract(Duration(days: 6 - tappedIndex));
                });
              }
            },
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: CustomPaint(
                  painter: BarChartPainter(
                data: dailyTotals,
                labels: labels,
                primaryColor: Theme.of(context).colorScheme.primary,
                textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                selectedIndex: selectedIndex,
              )),
            ),
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 类别网格 — 改进：色彩鲜明的图标容器
  // ─────────────────────────────────────────────
  Widget _buildCategoryGrid(List<Map<String, dynamic>> categories,
      {required int crossAxisCount, required double childAspectRatio}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: childAspectRatio),
      itemCount: categories.length,
      itemBuilder: (ctx, i) {
        final cat = categories[i];
        final String name = cat['name'];
        final int dur = cat['duration'];
        final Color color = _catColor(name);

        return _ExpandableCard(
          pageBuilder: (_) => CategoryDetailScreen(
            categoryName: name,
            stats: cat['items'],
            isAllFilter: _currentFilter == DeviceFilter.all,
            historyStats: _historyStats,
            currentFilter: _currentFilter,
          ),
          sourceColor: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.18), width: 1),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(getCategoryIcon(name), color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
              ),
              const SizedBox(height: 4),
              Text(formatShortHM(dur),
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // Top 应用网格 — 改进：底部相对进度条
  // ─────────────────────────────────────────────
  Widget _buildTopAppsGrid(
    List<MapEntry<String, Map<String, dynamic>>> apps, {
    required int totalDur,
    required int crossAxisCount,
    required double childAspectRatio,
    required int maxItems,
  }) {
    int maxAppDur = apps.isEmpty ? 1 : (apps.first.value['total'] as int);
    if (maxAppDur == 0) maxAppDur = 1;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: childAspectRatio),
      itemCount: math.min(maxItems, apps.length),
      itemBuilder: (ctx, i) {
        final app = apps[i];
        final devices = app.value['devices'] as Map<String, int>;
        final int appDur = app.value['total'] as int;
        final double ratio = appDur / maxAppDur;
        final cs = Theme.of(context).colorScheme;

        return _ExpandableCard(
          pageBuilder: (_) => AppDetailScreen(
            appName: app.key,
            historyStats: _historyStats,
            filter: _currentFilter,
          ),
          sourceColor: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: _cardDecoration(context),
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withOpacity(0.14),
                  child: Text(
                      app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(app.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13))),
              ]),
              const Spacer(),
              Text(formatHM(appDur),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      height: 1.2)),
              const SizedBox(height: 6),
              // 相对进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                  backgroundColor: cs.primary.withOpacity(0.1),
                  color: cs.primary.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 6),
              buildDeviceBreakdown(devices, _currentFilter == DeviceFilter.all),
            ]),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // 其余应用列表
  // ─────────────────────────────────────────────
  Widget _buildRestList(List<MapEntry<String, Map<String, dynamic>>> apps,
      {required int skipCount}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: _cardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: apps.length - skipCount,
          separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 60,
              endIndent: 16,
              color: cs.outlineVariant.withOpacity(0.4)),
          itemBuilder: (ctx, i) {
            final app = apps[i + skipCount];
            final devices = app.value['devices'] as Map<String, int>;
            return _ExpandableCard(
              pageBuilder: (_) => AppDetailScreen(
                appName: app.key,
                historyStats: _historyStats,
                filter: _currentFilter,
              ),
              sourceColor: cs.surface,
              borderRadius: BorderRadius.zero,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Text(
                        app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(app.key,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 4),
                        buildDeviceBreakdown(
                            devices, _currentFilter == DeviceFilter.all),
                      ])),
                  const SizedBox(width: 8),
                  Text(formatHM(app.value['total'] as int),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurfaceVariant)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: cs.outlineVariant),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── 通用卡片装饰 ───
  BoxDecoration _cardDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.8),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 可展开卡片（从点击位置展开到全屏的过渡动画）
// ─────────────────────────────────────────────
class _ExpandableCard extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext) pageBuilder;
  final Color? sourceColor;
  final BorderRadius borderRadius;

  const _ExpandableCard({
    required this.child,
    required this.pageBuilder,
    this.sourceColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  State<_ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<_ExpandableCard> {
  final GlobalKey _key = GlobalKey();

  void _handleTap() {
    PageTransitions.pushFromRect(
      context: context,
      page: widget.pageBuilder(context),
      sourceKey: _key,
      sourceColor: widget.sourceColor,
      sourceBorderRadius: widget.borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────
// 分类详情界面
// ─────────────────────────────────────────────
class CategoryDetailScreen extends StatelessWidget {
  final String categoryName;
  final List<dynamic> stats;
  final bool isAllFilter;
  final Map<String, List<dynamic>> historyStats;
  final DeviceFilter currentFilter;

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    required this.stats,
    required this.isAllFilter,
    required this.historyStats,
    required this.currentFilter,
  });

  BoxDecoration _cardDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.8),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final apps = _ScreenTimeDetailScreenState.getGroupedApps(stats);
    final int totalDur =
        apps.fold(0, (sum, app) => sum + (app.value['total'] as int));
    final Color catColor = _catColor(categoryName);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(categoryName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(children: [
            // hero 分类卡
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.07),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: catColor.withOpacity(0.2)),
              ),
              child: Column(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: catColor.withOpacity(0.15),
                      shape: BoxShape.circle),
                  child: Icon(
                      _ScreenTimeDetailScreenState.getCategoryIcon(
                          categoryName),
                      size: 30,
                      color: catColor),
                ),
                const SizedBox(height: 12),
                Text("该类别今日总计",
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 6),
                Text(_ScreenTimeDetailScreenState.formatHM(totalDur),
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: catColor)),
              ]),
            ),
            Expanded(
              child: apps.isEmpty
                  ? const Center(child: Text("暂无数据"))
                  : Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: _cardDecoration(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: apps.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 60,
                              endIndent: 16,
                              color: cs.outlineVariant.withOpacity(0.4)),
                          itemBuilder: (ctx, i) {
                            final app = apps[i];
                            final devices =
                                app.value['devices'] as Map<String, int>;
                            return _ExpandableCard(
                              pageBuilder: (_) => AppDetailScreen(
                                appName: app.key,
                                historyStats: historyStats,
                                filter: currentFilter,
                              ),
                              sourceColor: cs.surface,
                              borderRadius: BorderRadius.zero,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: catColor.withOpacity(0.1),
                                    child: Text(
                                        app.key.isNotEmpty
                                            ? app.key[0].toUpperCase()
                                            : "?",
                                        style: TextStyle(
                                            color: catColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(app.key,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15)),
                                        const SizedBox(height: 5),
                                        _ScreenTimeDetailScreenState
                                            .buildDeviceBreakdown(
                                                devices, isAllFilter),
                                      ])),
                                  Text(
                                      _ScreenTimeDetailScreenState.formatHM(
                                          app.value['total'] as int),
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: cs.onSurfaceVariant)),
                                  const SizedBox(width: 4),
                                  Icon(Icons.chevron_right_rounded,
                                      size: 18, color: cs.outlineVariant),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 应用详情界面
// ─────────────────────────────────────────────
class AppDetailScreen extends StatelessWidget {
  final String appName;
  final Map<String, List<dynamic>> historyStats;
  final DeviceFilter filter;

  const AppDetailScreen(
      {super.key,
      required this.appName,
      required this.historyStats,
      required this.filter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    List<String> labels = [];
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    int total7Days = 0;
    Map<String, List<int>> deviceTrends = {};
    Map<String, int> deviceToday = {};

    for (int i = 6; i >= 0; i--) {
      DateTime d = today.subtract(Duration(days: i));
      labels.add(i == 0 ? "今日" : DateFormat('MM/dd').format(d));
      for (var item in historyStats[DateFormat('yyyy-MM-dd').format(d)] ?? []) {
        String name = item['app_name'] ?? "";
        String device = item['device_name'] ?? "";
        if (name == appName &&
            ScreenTimeDetailScreen.matchesFilter(device, filter)) {
          deviceTrends.putIfAbsent(device, () => List.filled(7, 0));
        }
      }
    }
    for (int i = 6; i >= 0; i--) {
      DateTime d = today.subtract(Duration(days: i));
      for (var item in historyStats[DateFormat('yyyy-MM-dd').format(d)] ?? []) {
        String name = item['app_name'] ?? "";
        String device = item['device_name'] ?? "";
        if (name == appName && deviceTrends.containsKey(device)) {
          int duration = item['duration'] as int;
          int dayIndex = 6 - i;
          deviceTrends[device]![dayIndex] += duration;
          total7Days += duration;
          if (i == 0) {
            deviceToday[device] = (deviceToday[device] ?? 0) + duration;
          }
        }
      }
    }
    int avgDaily = total7Days ~/ 7;

    List<String> sortedDevices = deviceTrends.keys.toList();
    sortedDevices.sort((a, b) {
      int at = deviceToday[a] ?? 0, bt = deviceToday[b] ?? 0;
      if (at != bt) return bt.compareTo(at);
      return deviceTrends[b]!
          .fold(0, (s, v) => s + v)
          .compareTo(deviceTrends[a]!.fold(0, (s, v) => s + v));
    });

    BoxDecoration cardDec = BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.5), width: 0.8),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2))
      ],
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text("应用详情",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(builder: (ctx, constraints) {
            final bool isDesktop = constraints.maxWidth >= 800;

            List<Widget> deviceTrendCards = [];
            for (String device in sortedDevices) {
              List<int> trend = deviceTrends[device]!;
              int todayUse = deviceToday[device] ?? 0;
              int totalUse = trend.fold(0, (sum, val) => sum + val);
              if (totalUse == 0) continue;

              double cardWidth = isDesktop
                  ? ((constraints.maxWidth - 32 - 24) / 2).floorToDouble()
                  : double.infinity;

              deviceTrendCards.add(SizedBox(
                width: cardWidth,
                child: Container(
                  decoration: cardDec,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(
                                _ScreenTimeDetailScreenState.getDeviceIcon(
                                    device),
                                size: 18,
                                color: cs.primary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                            _ScreenTimeDetailScreenState.simplifyDeviceName(
                                device),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: todayUse > 0
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Text("今日 ",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                              Text(
                                  _ScreenTimeDetailScreenState.formatShortHM(
                                      todayUse),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: todayUse > 0
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 180,
                          child: CustomPaint(
                              painter: LineChartPainter(
                            data: trend,
                            labels: labels,
                            primaryColor: cs.primary,
                            textColor: cs.onSurfaceVariant,
                          )),
                        ),
                      ]),
                ),
              ));
            }

            return SingleChildScrollView(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 应用 hero 卡
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.primary.withOpacity(0.08),
                              cs.primaryContainer.withOpacity(0.3)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border:
                              Border.all(color: cs.primary.withOpacity(0.15)),
                        ),
                        child: Column(children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: cs.primary.withOpacity(0.18),
                            child: Text(
                                appName.isNotEmpty
                                    ? appName[0].toUpperCase()
                                    : "?",
                                style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(height: 14),
                          Text(appName,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 20),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Column(children: [
                                  Text("多端近七日总计",
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Text(
                                      _ScreenTimeDetailScreenState
                                          .formatShortHM(total7Days),
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: cs.primary)),
                                ]),
                                Container(
                                    width: 1,
                                    height: 44,
                                    color: cs.outlineVariant.withOpacity(0.5)),
                                Column(children: [
                                  Text("日均使用",
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontSize: 13)),
                                  const SizedBox(height: 6),
                                  Text(
                                      _ScreenTimeDetailScreenState
                                          .formatShortHM(avgDaily),
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: cs.primary)),
                                ]),
                              ]),
                        ]),
                      ),
                      const SizedBox(height: 28),
                      if (deviceTrendCards.isNotEmpty) ...[
                        Row(children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.devices_rounded,
                                size: 16, color: cs.primary),
                          ),
                          const SizedBox(width: 10),
                          Text("各端使用趋势",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 16),
                        Wrap(
                            spacing: 24,
                            runSpacing: 24,
                            children: deviceTrendCards),
                      ] else
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Text("暂无数据"))),
                      const SizedBox(height: 40),
                    ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LineChartPainter（不变，优化细节）
// ─────────────────────────────────────────────
class LineChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color primaryColor;
  final Color textColor;

  LineChartPainter(
      {required this.data,
      required this.labels,
      required this.primaryColor,
      required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width == 0) return;
    const double bottomPadding = 30.0,
        topPadding = 25.0,
        horizontalPadding = 20.0;
    final double chartHeight = size.height - bottomPadding - topPadding;
    final double drawWidth = size.width - horizontalPadding * 2;
    int maxVal = data.reduce(math.max);
    if (maxVal == 0) maxVal = 1;

    double yAvg = size.height -
        bottomPadding -
        ((data.reduce((a, b) => a + b) / data.length) / maxVal) * chartHeight;
    if (maxVal > 1) {
      _drawDashedLine(
          canvas,
          Offset(horizontalPadding, yAvg),
          Offset(size.width - horizontalPadding, yAvg),
          Paint()
            ..color = textColor.withOpacity(0.15)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke);
    }

    final double stepX = drawWidth / (data.length - 1);
    List<Offset> points = List.generate(
        data.length,
        (i) => Offset(
              horizontalPadding + i * stepX,
              size.height - bottomPadding - (data[i] / maxVal) * chartHeight,
            ));

    Path linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    Path areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height - bottomPadding)
      ..lineTo(points.first.dx, size.height - bottomPadding)
      ..close();

    canvas.drawPath(
        areaPath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, topPadding),
            Offset(0, size.height - bottomPadding),
            [primaryColor.withOpacity(0.3), primaryColor.withOpacity(0.0)],
          ));
    canvas.drawPath(
        linePath,
        Paint()
          ..color = primaryColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);

    final dotOuter = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final dotInner = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4.5, dotOuter);
      canvas.drawCircle(points[i], 3.0, dotInner);
      if (data[i] == maxVal && maxVal > 1) {
        _drawText(canvas, _ScreenTimeDetailScreenState.formatShortHM(data[i]),
            Offset(points[i].dx, points[i].dy - 16),
            fontSize: 10, color: primaryColor, bold: true);
      }
      _drawText(canvas, labels[i], Offset(points[i].dx, size.height - 12),
          fontSize: 11, color: textColor, bold: i == data.length - 1);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center,
      {double fontSize = 12, Color color = Colors.black, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dw = 5, ds = 5;
    double dist = (p2 - p1).distance,
        dx = (p2.dx - p1.dx) / dist,
        dy = (p2.dy - p1.dy) / dist;
    double sx = p1.dx, sy = p1.dy;
    while (dist >= 0) {
      double dl = math.min(dw, dist);
      canvas.drawLine(
          Offset(sx, sy), Offset(sx + dx * dl, sy + dy * dl), paint);
      sx += dx * (dw + ds);
      sy += dy * (dw + ds);
      dist -= (dw + ds);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─────────────────────────────────────────────
// BarChartPainter（不变，字体权重统一）
// ─────────────────────────────────────────────
class BarChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color primaryColor;
  final Color textColor;
  final int selectedIndex;

  BarChartPainter(
      {required this.data,
      required this.labels,
      required this.primaryColor,
      required this.textColor,
      required this.selectedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width == 0) return;
    const double bottomPadding = 30.0, topPadding = 25.0;
    final double chartHeight = size.height - bottomPadding - topPadding;
    int maxVal = data.reduce(math.max);
    if (maxVal == 0) maxVal = 1;
    double avgVal = data.reduce((a, b) => a + b) / data.length;
    final double barWidth = (size.width / data.length) * 0.35;
    final double spacing = size.width / data.length;
    final barPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      double xc = i * spacing + spacing / 2;
      double barH = (data[i] / maxVal) * chartHeight;
      barPaint.color =
          (i == selectedIndex) ? primaryColor : primaryColor.withOpacity(0.22);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(xc - barWidth / 2,
                  size.height - bottomPadding - barH, barWidth, barH),
              const Radius.circular(6)),
          barPaint);
      if (data[i] == maxVal && maxVal > 1) {
        _drawText(canvas, _ScreenTimeDetailScreenState.formatShortHM(data[i]),
            Offset(xc, size.height - bottomPadding - barH - 12),
            fontSize: 10, color: primaryColor, bold: true);
      }
      _drawText(canvas, labels[i], Offset(xc, size.height - 12),
          fontSize: 11, color: textColor, bold: i == selectedIndex);
    }
    if (avgVal > 0) {
      double avgY =
          size.height - bottomPadding - (avgVal / maxVal) * chartHeight;
      _drawDashedLine(
          canvas,
          Offset(0, avgY),
          Offset(size.width, avgY),
          Paint()
            ..color = Colors.orangeAccent.shade400
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke);
      _drawText(
          canvas,
          "平均 ${_ScreenTimeDetailScreenState.formatShortHM(avgVal.toInt())}",
          Offset(size.width - 25, avgY - 10),
          fontSize: 10,
          color: Colors.orange.shade800,
          bold: true);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center,
      {double fontSize = 12, Color color = Colors.black, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dw = 5, ds = 5;
    double dist = (p2 - p1).distance,
        dx = (p2.dx - p1.dx) / dist,
        dy = (p2.dy - p1.dy) / dist;
    double sx = p1.dx, sy = p1.dy;
    while (dist >= 0) {
      double dl = math.min(dw, dist);
      canvas.drawLine(
          Offset(sx, sy), Offset(sx + dx * dl, sy + dy * dl), paint);
      sx += dx * (dw + ds);
      sy += dy * (dw + ds);
      dist -= (dw + ds);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
