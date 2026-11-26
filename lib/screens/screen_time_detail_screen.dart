import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storage_service.dart';
import '../utils/calendar_date_math.dart';
import '../utils/page_transitions.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/floating_bottom_bar.dart';
import '../widgets/optional_liquid_glass_surface.dart';
import '../utils/time_utils.dart';

part 'screen_time/screen_time_helpers.dart';
part 'screen_time/screen_time_sections.dart';
part 'screen_time/screen_time_sub_screens.dart';
part 'screen_time/screen_time_chart_painters.dart';

// ─────────────────────────────────────────────
// 设备过滤枚举
// ─────────────────────────────────────────────
enum DeviceFilter { all, pc, mobile, phone, tablet }

enum ScreenTimeRange { day, week, month }

extension ScreenTimeRangeExtension on ScreenTimeRange {
  String get label {
    switch (this) {
      case ScreenTimeRange.day:
        return "日";
      case ScreenTimeRange.week:
        return "周";
      case ScreenTimeRange.month:
        return "月";
    }
  }
}

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
    if (filter == DeviceFilter.all) return true;
    final lower = deviceName.toLowerCase();
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
    List<dynamic> rawStats,
    DeviceFilter filter,
  ) {
    if (filter == DeviceFilter.all) return List<dynamic>.of(rawStats);

    final matchesByDevice = <String, bool>{};
    final filtered = <dynamic>[];
    for (final item in rawStats) {
      final deviceName = item['device_name'] ?? "";
      final matches = matchesByDevice.putIfAbsent(
        deviceName,
        () => matchesFilter(deviceName, filter),
      );
      if (matches) filtered.add(item);
    }
    return filtered;
  }

  static int getTotalDuration(List<dynamic> rawStats, DeviceFilter filter) {
    var total = 0;
    if (filter == DeviceFilter.all) {
      for (final item in rawStats) {
        total += item['duration'] as int;
      }
      return total;
    }

    final matchesByDevice = <String, bool>{};
    for (final item in rawStats) {
      final deviceName = item['device_name'] ?? "";
      final matches = matchesByDevice.putIfAbsent(
        deviceName,
        () => matchesFilter(deviceName, filter),
      );
      if (!matches) continue;
      total += item['duration'] as int;
    }
    return total;
  }
}

class _ScreenTimePeriodSummary {
  const _ScreenTimePeriodSummary({
    required this.total,
    required this.topApps,
    required this.categories,
  });

  final int total;
  final List<MapEntry<String, Map<String, dynamic>>> topApps;
  final List<Map<String, dynamic>> categories;
}

class _ScreenTimeDetailScreenState extends State<ScreenTimeDetailScreen> {
  DeviceFilter _currentFilter = DeviceFilter.all;
  ScreenTimeRange _currentRange = ScreenTimeRange.day;
  Map<String, List<dynamic>> _historyStats = {};
  final Map<(ScreenTimeRange, int, int), List<Map<String, dynamic>>>
  _periodStatsCache = {};
  final Map<(ScreenTimeRange, int, int, DeviceFilter), _ScreenTimePeriodSummary>
  _periodSummaryCache = {};
  final Map<(ScreenTimeRange, int, int, DeviceFilter), int> _periodTotalCache =
      {};
  Map<String, String> _cloudMappings = {};
  bool _isLoading = true;
  Timer? _historyLoadTimer;

  late DateTime _selectedDate;
  late DateTime _todayNormalized;

  @override
  void initState() {
    super.initState();
    DateTime now = DateTime.now();
    _todayNormalized = CalendarDateMath.dateOnly(now);
    _selectedDate = _todayNormalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyLoadTimer = Timer(const Duration(milliseconds: 300), () {
        _historyLoadTimer = null;
        if (mounted) _loadHistory();
      });
    });
  }

  @override
  void dispose() {
    _historyLoadTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.getScreenTimeHistory();
    final mappings = await StorageService.getAppMappings();
    final todayStr = AppTimeFormats.dateFormatter('yyyy-MM-dd')
        .format(DateTime.now());
    history[todayStr] = widget.todayStats;
    if (mounted) {
      setState(() {
        _historyStats = history;
        _periodStatsCache.clear();
        _periodSummaryCache.clear();
        _periodTotalCache.clear();
        _cloudMappings = mappings;
        _isLoading = false;
      });
    }
  }

  void _mutateState(VoidCallback fn) => setState(fn);

  List<dynamic> _statsForPeriod(DateTime periodStart, ScreenTimeRange range) {
    final cacheKey = (
      range,
      periodStart.millisecondsSinceEpoch,
      _todayNormalized.millisecondsSinceEpoch,
    );
    final cached = _periodStatsCache.remove(cacheKey);
    if (cached != null) {
      _periodStatsCache[cacheKey] = cached;
      return cached;
    }

    final Map<String, Map<String, dynamic>> grouped = {};
    for (final date in _daysInPeriod(periodStart, range, _todayNormalized)) {
      for (final raw in _historyStats[_historyKey(date)] ?? []) {
        final item = raw as Map;
        final appName = item['app_name']?.toString() ?? '未知应用';
        final packageName = item['package_name']?.toString() ?? '';
        final deviceName = item['device_name']?.toString() ?? '未知设备';
        final category = item['category']?.toString() ?? '未分类';
        final key = '$packageName::$appName::$deviceName::$category';
        final duration = (item['duration'] is num)
            ? (item['duration'] as num).toInt()
            : 0;

        grouped.putIfAbsent(
          key,
          () => {
            'package_name': packageName,
            'app_name': appName,
            'device_name': deviceName,
            'category': category,
            'duration': 0,
          },
        );
        grouped[key]!['duration'] =
            (grouped[key]!['duration'] as int) + duration;
      }
    }
    final stats = grouped.values.toList(growable: false);
    if (_periodStatsCache.length >= 6) {
      _periodStatsCache.remove(_periodStatsCache.keys.first);
    }
    _periodStatsCache[cacheKey] = stats;
    return stats;
  }

  void _cachePeriodTotal(
    (ScreenTimeRange, int, int, DeviceFilter) key,
    int total,
  ) {
    _periodTotalCache.remove(key);
    if (_periodTotalCache.length >= 14) {
      _periodTotalCache.remove(_periodTotalCache.keys.first);
    }
    _periodTotalCache[key] = total;
  }

  int _totalForPeriod(
    DateTime periodStart,
    ScreenTimeRange range,
    DeviceFilter filter,
  ) {
    final cacheKey = (
      range,
      periodStart.millisecondsSinceEpoch,
      _todayNormalized.millisecondsSinceEpoch,
      filter,
    );
    final cached = _periodTotalCache.remove(cacheKey);
    if (cached != null) {
      _periodTotalCache[cacheKey] = cached;
      return cached;
    }

    final total = ScreenTimeDetailScreen.getTotalDuration(
      _statsForPeriod(periodStart, range),
      filter,
    );
    _cachePeriodTotal(cacheKey, total);
    return total;
  }

  _ScreenTimePeriodSummary _summaryForPeriod(
    List<dynamic> periodStats,
    DateTime periodStart,
    ScreenTimeRange range,
    DeviceFilter filter,
  ) {
    final cacheKey = (
      range,
      periodStart.millisecondsSinceEpoch,
      _todayNormalized.millisecondsSinceEpoch,
      filter,
    );
    final cached = _periodSummaryCache.remove(cacheKey);
    if (cached != null) {
      _periodSummaryCache[cacheKey] = cached;
      return cached;
    }

    final appGroups = <String, Map<String, dynamic>>{};
    final catGroups = <String, List<dynamic>>{};
    final catTotals = <String, int>{};
    final matchesByDevice = filter == DeviceFilter.all
        ? null
        : <String, bool>{};
    var selectedTotal = 0;
    for (final item in periodStats) {
      if (filter != DeviceFilter.all) {
        final filterDeviceName = item['device_name'] ?? '';
        final matches = matchesByDevice!.putIfAbsent(
          filterDeviceName,
          () => ScreenTimeDetailScreen.matchesFilter(filterDeviceName, filter),
        );
        if (!matches) continue;
      }

      final appName = item['app_name'] ?? '未知应用';
      final deviceName = item['device_name'] ?? '未知设备';
      final duration = item['duration'] as int;
      selectedTotal += duration;
      final appGroup = appGroups.putIfAbsent(
        appName,
        () => {'total': 0, 'devices': <String, int>{}},
      );
      appGroup['total'] = (appGroup['total'] as int) + duration;
      final devices = appGroup['devices'] as Map<String, int>;
      devices[deviceName] = (devices[deviceName] ?? 0) + duration;

      final category = _stGetCategoryForApp(
        appName,
        item['category'],
        _cloudMappings,
      );
      catGroups.putIfAbsent(category, () => []).add(item);
      catTotals[category] = (catTotals[category] ?? 0) + duration;
    }
    _cachePeriodTotal(cacheKey, selectedTotal);
    final topApps = appGroups.entries.toList()
      ..sort(
        (a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int),
      );
    final catDurs = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final categories = <Map<String, dynamic>>[];
    if (catDurs.length <= 6) {
      for (final entry in catDurs) {
        categories.add({
          'name': entry.key,
          'duration': entry.value,
          'items': catGroups[entry.key],
        });
      }
    } else {
      for (var i = 0; i < 5; i++) {
        categories.add({
          'name': catDurs[i].key,
          'duration': catDurs[i].value,
          'items': catGroups[catDurs[i].key],
        });
      }
      var otherDuration = 0;
      final otherItems = <dynamic>[];
      for (var i = 5; i < catDurs.length; i++) {
        otherDuration += catDurs[i].value;
        otherItems.addAll(catGroups[catDurs[i].key]!);
      }
      categories.add({
        'name': '其他类别',
        'duration': otherDuration,
        'items': otherItems,
      });
    }

    final summary = _ScreenTimePeriodSummary(
      total: selectedTotal,
      topApps: topApps,
      categories: categories,
    );
    if (_periodSummaryCache.length >= 6) {
      _periodSummaryCache.remove(_periodSummaryCache.keys.first);
    }
    _periodSummaryCache[cacheKey] = summary;
    return summary;
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: cs.surfaceContainerLowest,
      appBar: FloatingGlassAppBar(
        title: const Text(
          "详细统计",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const FloatingGlassTopBarBackground(),
      ),
      bottomNavigationBar: FloatingBottomNavigationBar(
        mobilePortraitOnly: false,
        items: const [
          FloatingBottomNavigationItem(icon: Icons.today_outlined, label: '日'),
          FloatingBottomNavigationItem(
            icon: Icons.date_range_outlined,
            label: '周',
          ),
          FloatingBottomNavigationItem(
            icon: Icons.calendar_month_outlined,
            label: '月',
          ),
        ],
        selectedIndex: _currentRange.index,
        onTabSelected: (index) {
          final range = ScreenTimeRange.values[index];
          setState(() {
            _currentRange = range;
            _selectedDate = _periodStart(_selectedDate, range);
          });
        },
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: Padding(
          // The app bar is transparent and paints above the body. Reserve its
          // full height so the first filter and summary cards stay visible.
          padding: EdgeInsets.only(top: topBarHeight),
          child: _isLoading
              ? const AppSkeletonDashboardPage(
                  maxWidth: 1080,
                  showFilterChips: true,
                  showMetricGrid: true,
                  showChart: true,
                  listCount: 5,
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: _buildMainContent(),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final periodStart = _periodStart(_selectedDate, _currentRange);
    final prevPeriodStart = _previousPeriodStart(periodStart, _currentRange);
    final datePrefix = _periodLabel(
      periodStart,
      _currentRange,
      _todayNormalized,
    );

    final periodStats = _statsForPeriod(periodStart, _currentRange);

    final summary = _summaryForPeriod(
      periodStats,
      periodStart,
      _currentRange,
      _currentFilter,
    );
    final selectedTotal = summary.total;
    int prevTotal = _totalForPeriod(
      prevPeriodStart,
      _currentRange,
      _currentFilter,
    );
    int diff = selectedTotal - prevTotal;

    final bottomContentPadding = floatingBottomNavigationContentPaddingFor(
      context,
    );
    final topApps = summary.topApps;
    final finalCategories = summary.categories;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w = constraints.maxWidth;
        final bool isDesktop = w >= 900;
        final bool isTablet = w >= 600 && w < 900;

        if (isDesktop) {
          return SizedBox(
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFilters(
                          padding: const EdgeInsets.only(bottom: 12),
                          includeRange: false,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeroCard(selectedTotal, diff, datePrefix),
                                const SizedBox(height: 16),
                                _buildSectionHeader(
                                  _trendTitle(_currentRange),
                                  Icons.bar_chart_rounded,
                                ),
                                _buildChartCard(height: 280),
                                SizedBox(height: bottomContentPadding),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: CustomScrollView(
                      slivers: [
                        if (finalCategories.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(
                              "$datePrefix类别分布",
                              Icons.category_rounded,
                            ),
                          ),
                          _buildCategorySliverGrid(
                            finalCategories,
                            crossAxisCount: 3,
                            childAspectRatio: 1.1,
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                        if (topApps.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(
                              "$datePrefix最常使用",
                              Icons.dashboard_rounded,
                            ),
                          ),
                          _buildTopAppsSliverGrid(
                            topApps,
                            totalDur: selectedTotal,
                            crossAxisCount: 3,
                            childAspectRatio: 1.1,
                            maxItems: 6,
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                        if (topApps.length > 6) ...[
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(
                              "其余应用明细",
                              Icons.format_list_bulleted_rounded,
                            ),
                          ),
                          _buildRestSliverList(topApps, skipCount: 6),
                        ],
                        SliverToBoxAdapter(
                          child: SizedBox(height: bottomContentPadding),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        int catCount = isTablet ? 6 : 3;
        int topCount = isTablet ? 4 : 2;
        int maxTop = 4;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _buildFilters(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                includeRange: false,
              ),
            ),
            SliverToBoxAdapter(
              child: _buildHeroCard(selectedTotal, diff, datePrefix),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      _trendTitle(_currentRange),
                      Icons.bar_chart_rounded,
                    ),
                    _buildChartCard(height: 200),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            if (finalCategories.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    "$datePrefix类别分布",
                    Icons.category_rounded,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: _buildCategorySliverGrid(
                  finalCategories,
                  crossAxisCount: catCount,
                  childAspectRatio: isTablet ? 0.9 : 1.0,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
            if (topApps.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    "$datePrefix最常使用",
                    Icons.dashboard_rounded,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: _buildTopAppsSliverGrid(
                  topApps,
                  totalDur: selectedTotal,
                  crossAxisCount: topCount,
                  childAspectRatio: isTablet ? 1.0 : 1.15,
                  maxItems: maxTop,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
            if (topApps.length > maxTop) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    "其余应用明细",
                    Icons.format_list_bulleted_rounded,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: _buildRestSliverList(topApps, skipCount: maxTop),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: bottomContentPadding + 4),
            ),
          ],
        );
      },
    );
  }
}
