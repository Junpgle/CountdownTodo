part of '../screen_time_detail_screen.dart';

extension _ScreenTimeDetailSections on _ScreenTimeDetailScreenState {
  // ─────────────────────────────────────────────
  // 区块标题
  // ─────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 过滤器
  // ─────────────────────────────────────────────
  Widget _buildRangeFilterRow({bool floating = false}) {
    final cs = Theme.of(context).colorScheme;
    Widget buildRangeChip(ScreenTimeRange range) {
      final selected = _currentRange == range;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(
            range.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
          selected: selected,
          onSelected: (v) {
            if (!v) return;
            _mutateState(() {
              _currentRange = range;
              _selectedDate = _periodStart(_selectedDate, range);
            });
          },
          shape: const StadiumBorder(),
          showCheckmark: false,
          selectedColor: cs.primary,
          backgroundColor: floating
              ? cs.surface.withValues(alpha: 0)
              : cs.surfaceContainerHighest,
          side: BorderSide(
            color: selected
                ? cs.primary
                : (floating
                      ? cs.onSurfaceVariant.withValues(alpha: 0.35)
                      : cs.outlineVariant),
            width: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: ScreenTimeRange.values.map(buildRangeChip).toList(),
      ),
    );
  }

  Widget _buildDeviceFilterRow() {
    final cs = Theme.of(context).colorScheme;

    Widget buildDeviceChip(DeviceFilter filter) {
      final selected = _currentFilter == filter;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(
            filter.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
          selected: selected,
          onSelected: (v) {
            if (v) _mutateState(() => _currentFilter = filter);
          },
          shape: const StadiumBorder(),
          showCheckmark: false,
          selectedColor: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: 1,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: DeviceFilter.values.map(buildDeviceChip).toList(),
      ),
    );
  }

  Widget _buildFilters({
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    bool includeRange = true,
  }) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (includeRange) ...[
            _buildRangeFilterRow(),
            const SizedBox(height: 6),
          ],
          _buildDeviceFilterRow(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Hero 总时长卡片
  // ─────────────────────────────────────────────
  Widget _buildHeroCard(int total, int diff, String datePrefix) {
    final cs = Theme.of(context).colorScheme;
    bool isIncrease = diff >= 0;
    Color diffColor = isIncrease
        ? const Color(0xFFB07820)
        : const Color(0xFF1A8C5E);
    IconData diffIcon = isIncrease
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.08),
              cs.primary.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$datePrefix使用时长",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stFormatHM(total),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(diffIcon, size: 15, color: diffColor),
                        const SizedBox(width: 4),
                        Text(
                          "${_compareText(_currentRange)}${isIncrease ? '增加' : '减少'} ${_stFormatHM(diff.abs())}",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: diffColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.access_time_filled_rounded,
                  size: 32,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // 趋势柱状图卡片
  // ─────────────────────────────────────────────
  Widget _buildChartCard({double height = 200}) {
    final currentPeriodStart = _periodStart(_todayNormalized, _currentRange);
    final selectedPeriodStart = _periodStart(_selectedDate, _currentRange);
    final slotCount = _currentRange == ScreenTimeRange.month ? 6 : 7;
    List<int> totals = [];
    List<String> labels = [];

    for (int i = slotCount - 1; i >= 0; i--) {
      final slotStart = _shiftPeriod(currentPeriodStart, _currentRange, -i);
      totals.add(_totalForPeriod(slotStart, _currentRange, _currentFilter));
      labels.add(_chartLabel(slotStart, i == 0));
    }

    int selectedIndex = -1;
    for (int i = 0; i < slotCount; i++) {
      final slotStart = _shiftPeriod(
        currentPeriodStart,
        _currentRange,
        i - slotCount + 1,
      );
      if (slotStart == selectedPeriodStart) {
        selectedIndex = i;
        break;
      }
    }

    return OptionalLiquidGlassCard(
      borderRadius: 22,
      highContrast: true,
      fallbackDecoration: _cardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                double sectionWidth = constraints.maxWidth / slotCount;
                int tappedIndex = (details.localPosition.dx / sectionWidth)
                    .floor();
                if (tappedIndex >= 0 && tappedIndex < slotCount) {
                  _mutateState(() {
                    _selectedDate = _shiftPeriod(
                      currentPeriodStart,
                      _currentRange,
                      tappedIndex - slotCount + 1,
                    );
                  });
                }
              },
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: BarChartPainter(
                      data: totals,
                      labels: labels,
                      primaryColor: Theme.of(context).colorScheme.primary,
                      textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      selectedIndex: selectedIndex,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _chartLabel(DateTime periodStart, bool isCurrent) {
    switch (_currentRange) {
      case ScreenTimeRange.day:
        return isCurrent
            ? "今日"
            : AppTimeFormats.dateFormatter('MM/dd').format(periodStart);
      case ScreenTimeRange.week:
        return isCurrent
            ? "本周"
            : AppTimeFormats.dateFormatter('MM/dd').format(periodStart);
      case ScreenTimeRange.month:
        return isCurrent
            ? "本月"
            : AppTimeFormats.dateFormatter('MM月').format(periodStart);
    }
  }

  // ─────────────────────────────────────────────
  // 类别网格 — 改进：色彩鲜明的图标容器
  // ─────────────────────────────────────────────
  Widget _buildCategoryGrid(
    List<Map<String, dynamic>> categories, {
    required int crossAxisCount,
    required double childAspectRatio,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final name = key.value;
          final idx = categories.indexWhere((c) => c['name'] == name);
          return idx != -1 ? idx : null;
        }
        return null;
      },
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: categories.length,
      itemBuilder: (ctx, i) {
        final cat = categories[i];
        final String name = cat['name'];
        final int dur = cat['duration'];
        final Color color = _catColor(name);
        final cs = Theme.of(context).colorScheme;
        final opaqueCardColor = Color.alphaBlend(
          color.withValues(alpha: 0.08),
          cs.surfaceContainerLowest,
        );

        return RepaintBoundary(
          key: ValueKey<String>(name),
          child: _ExpandableCard(
            pageBuilder: (_) => CategoryDetailScreen(
              categoryName: name,
              stats: cat['items'],
              isAllFilter: _currentFilter == DeviceFilter.all,
              historyStats: _historyStats,
              currentFilter: _currentFilter,
              range: _currentRange,
              anchorDate: _selectedDate,
              periodLabel: _periodLabel(
                _periodStart(_selectedDate, _currentRange),
                _currentRange,
                _todayNormalized,
              ),
            ),
            sourceColor: opaqueCardColor,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: color.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _stGetCategoryIcon(name),
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stFormatShortHM(dur),
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
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
      padding: EdgeInsets.zero,
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final keyVal = key.value;
          final limit = math.min(maxItems, apps.length);
          for (int idx = 0; idx < limit; idx++) {
            if (apps[idx].key == keyVal) return idx;
          }
        }
        return null;
      },
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: math.min(maxItems, apps.length),
      itemBuilder: (ctx, i) {
        final app = apps[i];
        final devices = app.value['devices'] as Map<String, int>;
        final int appDur = app.value['total'] as int;
        final double ratio = appDur / maxAppDur;
        final cs = Theme.of(context).colorScheme;

        return RepaintBoundary(
          key: ValueKey<String>(app.key),
          child: _ExpandableCard(
            pageBuilder: (_) => AppDetailScreen(
              appName: app.key,
              historyStats: _historyStats,
              filter: _currentFilter,
              range: _currentRange,
              anchorDate: _selectedDate,
            ),
            sourceColor: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            child: OptionalLiquidGlassCard(
              borderRadius: 22,
              highContrast: true,
              padding: const EdgeInsets.all(14),
              fallbackDecoration: _cardDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: cs.primary.withValues(alpha: 0.14),
                        child: Text(
                          app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          app.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _stFormatHM(appDur),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 相对进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      backgroundColor: cs.primary.withValues(alpha: 0.1),
                      color: cs.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _stBuildDeviceBreakdown(
                    devices,
                    _currentFilter == DeviceFilter.all,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // 其余应用列表
  // ─────────────────────────────────────────────
  Widget _buildRestList(
    List<MapEntry<String, Map<String, dynamic>>> apps, {
    required int skipCount,
  }) {
    final cs = Theme.of(context).colorScheme;
    return OptionalLiquidGlassCard(
      borderRadius: 22,
      highContrast: true,
      fallbackDecoration: _cardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          findItemIndexCallback: (Key key) {
            if (key is ValueKey<String>) {
              final keyVal = key.value;
              for (int idx = skipCount; idx < apps.length; idx++) {
                if (apps[idx].key == keyVal) return idx - skipCount;
              }
            }
            return null;
          },
          itemCount: apps.length - skipCount,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 60,
            endIndent: 16,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
          itemBuilder: (ctx, i) {
            final app = apps[i + skipCount];
            final devices = app.value['devices'] as Map<String, int>;
            return RepaintBoundary(
              key: ValueKey<String>(app.key),
              child: _ExpandableCard(
                pageBuilder: (_) => AppDetailScreen(
                  appName: app.key,
                  historyStats: _historyStats,
                  filter: _currentFilter,
                  range: _currentRange,
                  anchorDate: _selectedDate,
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
                        radius: 18,
                        backgroundColor: cs.surfaceContainerHighest,
                        child: Text(
                          app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _stBuildDeviceBreakdown(
                              devices,
                              _currentFilter == DeviceFilter.all,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _stFormatHM(app.value['total'] as int),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
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
    );
  }

  // ─── 通用卡片装饰 ───
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
}
