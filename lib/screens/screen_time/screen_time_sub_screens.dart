part of '../screen_time_detail_screen.dart';

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
  final ScreenTimeRange range;
  final DateTime anchorDate;
  final String periodLabel;

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    required this.stats,
    required this.isAllFilter,
    required this.historyStats,
    required this.currentFilter,
    required this.range,
    required this.anchorDate,
    required this.periodLabel,
  });

  BoxDecoration _cardDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.5),
        width: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topBarHeight = floatingGlassTopBarHeight(context);
    final apps = _stGetGroupedApps(stats);
    final int totalDur = apps.fold(
      0,
      (sum, app) => sum + (app.value['total'] as int),
    );
    final Color catColor = _catColor(categoryName);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      extendBodyBehindAppBar: true,
      appBar: FloatingGlassAppBar(
        title: Text(
          categoryName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const FloatingGlassTopBarBackground(),
      ),
      body: FloatingGlassTopBarContentFade(
        topBarHeight: topBarHeight,
        child: Padding(
          // Keep the category summary below the transparent app bar as well.
          padding: EdgeInsets.only(top: topBarHeight),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  // hero 分类卡
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: catColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _stGetCategoryIcon(categoryName),
                            size: 30,
                            color: catColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "该类别$periodLabel总计",
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _stFormatHM(totalDur),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: catColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: apps.isEmpty
                        ? const Center(child: Text("暂无数据"))
                        : OptionalLiquidGlassCard(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            borderRadius: 22,
                            highContrast: true,
                            fallbackDecoration: _cardDecoration(context),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                findItemIndexCallback: (Key key) {
                                  if (key is ValueKey<String>) {
                                    final keyVal = key.value;
                                    final idx = apps.indexWhere(
                                      (a) => a.key == keyVal,
                                    );
                                    return idx != -1 ? idx : null;
                                  }
                                  return null;
                                },
                                itemCount: apps.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  indent: 60,
                                  endIndent: 16,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                                itemBuilder: (ctx, i) {
                                  final app = apps[i];
                                  final devices =
                                      app.value['devices'] as Map<String, int>;
                                  return RepaintBoundary(
                                    key: ValueKey<String>(app.key),
                                    child: _ExpandableCard(
                                      pageBuilder: (_) => AppDetailScreen(
                                        appName: app.key,
                                        historyStats: historyStats,
                                        filter: currentFilter,
                                        range: range,
                                        anchorDate: anchorDate,
                                      ),
                                      sourceColor: cs.surface,
                                      borderRadius: BorderRadius.zero,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: catColor
                                                  .withValues(alpha: 0.1),
                                              child: Text(
                                                app.key.isNotEmpty
                                                    ? app.key[0].toUpperCase()
                                                    : "?",
                                                style: TextStyle(
                                                  color: catColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    app.key,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  _stBuildDeviceBreakdown(
                                                    devices,
                                                    isAllFilter,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              _stFormatHM(
                                                app.value['total'] as int,
                                              ),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: cs.outlineVariant,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
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
  final ScreenTimeRange range;
  final DateTime anchorDate;

  const AppDetailScreen({
    super.key,
    required this.appName,
    required this.historyStats,
    required this.filter,
    required this.range,
    required this.anchorDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    List<String> labels = [];
    DateTime now = DateTime.now();
    DateTime today = CalendarDateMath.dateOnly(now);
    final currentPeriodStart = _periodStart(anchorDate, range);
    final slotCount = range == ScreenTimeRange.month ? 6 : 7;
    int totalAcrossSlots = 0;
    Map<String, List<int>> deviceTrends = {};
    Map<String, int> deviceCurrent = {};
    Map<String, int> deviceTotals = {};
    final deviceMatchesByName = filter == DeviceFilter.all
        ? null
        : <String, bool>{};

    String chartLabel(DateTime periodStart, bool isCurrentSlot) {
      switch (range) {
        case ScreenTimeRange.day:
          return isCurrentSlot && periodStart == today
              ? "今日"
              : AppTimeFormats.dateFormatter('MM/dd').format(periodStart);
        case ScreenTimeRange.week:
          return isCurrentSlot
              ? _periodLabel(periodStart, range, today)
              : AppTimeFormats.dateFormatter('MM/dd').format(periodStart);
        case ScreenTimeRange.month:
          return isCurrentSlot
              ? _periodLabel(periodStart, range, today)
              : AppTimeFormats.dateFormatter('MM月').format(periodStart);
      }
    }

    for (int slot = 0; slot < slotCount; slot++) {
      final periodStart = _shiftPeriod(
        currentPeriodStart,
        range,
        slot - slotCount + 1,
      );
      labels.add(chartLabel(periodStart, slot == slotCount - 1));
      for (final d in _daysInPeriod(periodStart, range, today)) {
        for (var item in historyStats[_historyKey(d)] ?? []) {
          String name = item['app_name'] ?? "";
          String device = item['device_name'] ?? "";
          if (name != appName) continue;
          final matches =
              filter == DeviceFilter.all ||
              deviceMatchesByName!.putIfAbsent(
                device,
                () => ScreenTimeDetailScreen.matchesFilter(device, filter),
              );
          if (!matches) continue;

          final trend = deviceTrends.putIfAbsent(
            device,
            () => List.filled(slotCount, 0),
          );
          final durationValue = item['duration'];
          final duration = durationValue is num ? durationValue.toInt() : 0;
          trend[slot] += duration;
          deviceTotals[device] = (deviceTotals[device] ?? 0) + duration;
          totalAcrossSlots += duration;
          if (slot == slotCount - 1) {
            deviceCurrent[device] = (deviceCurrent[device] ?? 0) + duration;
          }
        }
      }
    }
    int avgPerPeriod = totalAcrossSlots ~/ slotCount;
    final String selectedLabel = _periodLabel(currentPeriodStart, range, today);
    final String totalLabel = switch (range) {
      ScreenTimeRange.day => "多端近七日总计",
      ScreenTimeRange.week => "多端近七周总计",
      ScreenTimeRange.month => "多端近六月总计",
    };
    final String avgLabel = switch (range) {
      ScreenTimeRange.day => "日均使用",
      ScreenTimeRange.week => "周均使用",
      ScreenTimeRange.month => "月均使用",
    };

    List<String> sortedDevices = deviceTrends.keys.toList();
    sortedDevices.sort((a, b) {
      int at = deviceCurrent[a] ?? 0, bt = deviceCurrent[b] ?? 0;
      if (at != bt) return bt.compareTo(at);
      return deviceTotals[b]!.compareTo(deviceTotals[a]!);
    });

    BoxDecoration cardDec = BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.5),
        width: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: FloatingGlassAppBar(
        title: const Text(
          "应用详情",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const FloatingGlassTopBarBackground(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final bool isDesktop = constraints.maxWidth >= 800;

              List<Widget> deviceTrendCards = [];
              for (String device in sortedDevices) {
                List<int> trend = deviceTrends[device]!;
                int currentUse = deviceCurrent[device] ?? 0;
                int totalUse = deviceTotals[device]!;
                if (totalUse == 0) continue;

                double cardWidth = isDesktop
                    ? ((constraints.maxWidth - 32 - 24) / 2).floorToDouble()
                    : double.infinity;

                deviceTrendCards.add(
                  SizedBox(
                    width: cardWidth,
                    child: OptionalLiquidGlassCard(
                      borderRadius: 22,
                      highContrast: true,
                      padding: const EdgeInsets.all(20),
                      fallbackDecoration: cardDec,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _stGetDeviceIcon(device),
                                  size: 18,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _stSimplifyDeviceName(device),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: currentUse > 0
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "$selectedLabel ",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      _stFormatShortHM(currentUse),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: currentUse > 0
                                            ? cs.onPrimaryContainer
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 180,
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: LineChartPainter(
                                  data: trend,
                                  labels: labels,
                                  primaryColor: cs.primary,
                                  textColor: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                              cs.primary.withValues(alpha: 0.08),
                              cs.primaryContainer.withValues(alpha: 0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: cs.primary.withValues(
                                alpha: 0.18,
                              ),
                              child: Text(
                                appName.isNotEmpty
                                    ? appName[0].toUpperCase()
                                    : "?",
                                style: TextStyle(
                                  color: cs.primary,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              appName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      totalLabel,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _stFormatShortHM(totalAcrossSlots),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  width: 1,
                                  height: 44,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                Column(
                                  children: [
                                    Text(
                                      avgLabel,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _stFormatShortHM(avgPerPeriod),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (deviceTrendCards.isNotEmpty) ...[
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.devices_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "各端使用趋势",
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 24,
                          runSpacing: 24,
                          children: deviceTrendCards,
                        ),
                      ] else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text("暂无数据"),
                          ),
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
