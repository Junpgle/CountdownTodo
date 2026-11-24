part of '../finance_widgets.dart';

class _FinanceUnifiedCategoryCard extends StatefulWidget {
  final ColorScheme colorScheme;
  final List<_FinanceCategoryTotal> topCategories;
  final List<_FinanceCategoryTotal> shareTotals;
  final _FinanceOverviewPeriod period;
  final Map<String, FinanceCategory> categories;
  final String Function(String?) categoryDisplayName;
  final Future<void> Function(
    _FinanceCategoryTotal entry,
    _FinanceOverviewPeriod period,
    GlobalKey sourceKey,
  )
  onOpenCategoryDetail;
  final Map<String, GlobalKey> categorySourceKeys;
  final _FinanceOverviewView view;

  const _FinanceUnifiedCategoryCard({
    required this.colorScheme,
    required this.topCategories,
    required this.shareTotals,
    required this.period,
    required this.categories,
    required this.categoryDisplayName,
    required this.onOpenCategoryDetail,
    required this.categorySourceKeys,
    required this.view,
  });

  @override
  State<_FinanceUnifiedCategoryCard> createState() =>
      _FinanceUnifiedCategoryCardState();
}

class _FinanceUnifiedCategoryCardState
    extends State<_FinanceUnifiedCategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _animation;
  String? _selectedCategoryUuid;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _animation = _animationController.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void didUpdateWidget(covariant _FinanceUnifiedCategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period.from != widget.period.from ||
        oldWidget.period.to != widget.period.to ||
        oldWidget.view != widget.view) {
      _selectedCategoryUuid = null;
      _animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _categoryShareColor(
    _FinanceCategoryTotal entry,
    int index,
    ColorScheme colorScheme,
  ) {
    final category = entry.categoryUuid == null
        ? null
        : widget.categories[entry.categoryUuid];
    return financeCategoryColor(
      colorScheme: colorScheme,
      customColorValue: category?.colorValue,
      index: index,
    );
  }

  void _handleChartTap(
    Offset localPosition,
    double chartSize,
    List<FinanceDonutSlice> slices,
    int total,
  ) {
    if (total <= 0 || slices.isEmpty) return;
    final center = Offset(chartSize / 2, chartSize / 2);
    final distance = (localPosition - center).distance;
    final isLarge = chartSize >= 160.0;
    final baseRadius = chartSize / 2 - (isLarge ? 16.0 : 14.0);

    // 点击环心：若当前已选中某分类，则切回总额
    if (distance < baseRadius - (isLarge ? 18.0 : 15.0)) {
      if (_selectedCategoryUuid != null) {
        setState(() => _selectedCategoryUuid = null);
        HapticFeedback.selectionClick();
      }
      return;
    }

    // 点击圆环附近区域
    if (distance >= baseRadius - 22.0 && distance <= baseRadius + 26.0) {
      final angle = math.atan2(
        localPosition.dy - center.dy,
        localPosition.dx - center.dx,
      );
      var normalized = (angle + math.pi / 2) % (2 * math.pi);
      if (normalized < 0) normalized += 2 * math.pi;

      var accumulated = 0.0;
      for (final slice in slices) {
        final sweep = 2 * math.pi * (slice.value / total);
        if (normalized >= accumulated && normalized < accumulated + sweep) {
          setState(() {
            if (_selectedCategoryUuid == slice.categoryUuid) {
              _selectedCategoryUuid = null;
            } else {
              _selectedCategoryUuid = slice.categoryUuid;
            }
          });
          HapticFeedback.selectionClick();
          return;
        }
        accumulated += sweep;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final totalsForSlices = widget.shareTotals.isNotEmpty
        ? widget.shareTotals
        : widget.topCategories;
    final total = totalsForSlices.fold<int>(
      0,
      (sum, entry) => sum + entry.value,
    );

    final slices = <FinanceDonutSlice>[
      for (var index = 0; index < totalsForSlices.length; index++)
        () {
          final entry = totalsForSlices[index];
          final category = entry.categoryUuid == null
              ? null
              : widget.categories[entry.categoryUuid];
          return FinanceDonutSlice(
            categoryUuid: entry.categoryUuid,
            value: entry.value,
            color: _categoryShareColor(entry, index, colorScheme),
            label: widget.categoryDisplayName(entry.categoryUuid),
            icon: category?.icon,
          );
        }(),
    ];

    final semanticSummary = [
      for (var index = 0; index < totalsForSlices.length; index++)
        '${widget.categoryDisplayName(totalsForSlices[index].categoryUuid)} '
            '${total > 0 ? (totalsForSlices[index].value / total * 100).toStringAsFixed(1) : '0.0'}%',
    ].join('、');

    final shareTotalsMap = <String?, _FinanceCategoryTotal>{
      for (final entry in totalsForSlices) entry.categoryUuid: entry,
    };

    final isTest = AppPlatform.isFlutterTest;
    final donutSize = switch (widget.view) {
      _FinanceOverviewView.month => isTest ? 100.0 : 190.0,
      _FinanceOverviewView.week => isTest ? 90.0 : 166.0,
      _FinanceOverviewView.day => isTest ? 80.0 : 142.0,
    };

    final isDark = colorScheme.brightness == Brightness.dark;
    FinanceDonutSlice? selectedSlice;
    if (_selectedCategoryUuid != null) {
      for (final slice in slices) {
        if (slice.categoryUuid == _selectedCategoryUuid) {
          selectedSlice = slice;
          break;
        }
      }
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600 && total > 0;
            final donutWidget = total > 0
                ? Semantics(
                    label: widget.period.isPlanned
                        ? '计划支出占比：$semanticSummary'
                        : '各类别支出占比：$semanticSummary',
                    child: SizedBox(
                      height: donutSize + 4,
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) => _handleChartTap(
                            details.localPosition,
                            donutSize,
                            slices,
                            total,
                          ),
                          child: SizedBox.square(
                            dimension: donutSize,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                RepaintBoundary(
                                  child: CustomPaint(
                                    size: Size.square(donutSize),
                                    painter: FinanceDonutPainter(
                                      slices: slices,
                                      total: total,
                                      selectedCategoryUuid:
                                          _selectedCategoryUuid,
                                      sweepProgress: _animation.value,
                                      sweepAnimation: _animation,
                                      emptyColor:
                                          colorScheme.surfaceContainerHighest,
                                      isDark: isDark,
                                    ),
                                  ),
                                ),
                                _buildDonutCenterInfo(
                                  context,
                                  colorScheme,
                                  total,
                                  widget.period,
                                  selectedSlice,
                                  slices.length,
                                  donutSize,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink();

            final categoryRows = [
              for (
                var index = 0;
                index < widget.topCategories.length;
                index++
              ) ...[
                () {
                  final entry = widget.topCategories[index];
                  final shareEntry =
                      shareTotalsMap[entry.categoryUuid] ?? entry;
                  final sliceIndex = totalsForSlices.indexWhere(
                    (s) => s.categoryUuid == entry.categoryUuid,
                  );
                  final sliceColor =
                      sliceIndex >= 0 && sliceIndex < slices.length
                      ? slices[sliceIndex].color
                      : _categoryShareColor(entry, index, colorScheme);
                  final isSelected =
                      _selectedCategoryUuid != null &&
                      _selectedCategoryUuid == entry.categoryUuid;
                  return _buildUnifiedCategoryRow(
                    context,
                    entry,
                    shareValue: shareEntry.value,
                    color: sliceColor,
                    total: total,
                    period: widget.period,
                    colorScheme: colorScheme,
                    isSelected: isSelected,
                  );
                }(),
              ],
            ];

            if (isWide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: math.max(
                        donutSize + 32.0,
                        constraints.maxWidth * 0.38,
                      ),
                      child: Center(child: donutWidget),
                    ),
                    VerticalDivider(
                      width: 24,
                      thickness: 0.8,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: categoryRows,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                if (total > 0) ...[donutWidget, const Divider(height: 14)],
                ...categoryRows,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDonutCenterInfo(
    BuildContext context,
    ColorScheme colorScheme,
    int total,
    _FinanceOverviewPeriod period,
    FinanceDonutSlice? selectedSlice,
    int categoryCount,
    double donutSize,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final contentKey = ValueKey(
      selectedSlice?.categoryUuid ?? 'total-overview',
    );
    final isLarge = donutSize >= 160.0;
    final titleFontSize = isLarge ? 13.5 : 11.5;
    final amountFontSize = isLarge ? 22.0 : 17.0;
    final badgeFontSize = isLarge ? 11.5 : 10.0;
    final badgePadding = isLarge
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5)
        : const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5);

    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isLarge ? 20.0 : 14.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final scale = Tween<double>(
                begin: 0.92,
                end: 1.0,
              ).animate(animation);
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) {
                  if (animation.value <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  if (animation.value >= 0.999) {
                    return child!;
                  }
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: scale, child: child),
                  );
                },
              );
            },
            child: KeyedSubtree(
              key: contentKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selectedSlice != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (selectedSlice.icon != null &&
                            selectedSlice.icon!.isNotEmpty) ...[
                          Text(
                            selectedSlice.icon!,
                            style: TextStyle(fontSize: isLarge ? 14 : 12),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            selectedSlice.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatFinanceAmount(selectedSlice.value),
                        style: TextStyle(
                          fontSize: amountFontSize,
                          fontWeight: FontWeight.w800,
                          color: selectedSlice.color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: badgePadding,
                      decoration: BoxDecoration(
                        color: selectedSlice.color.withValues(
                          alpha: isDark ? 0.22 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '占比 ${total > 0 ? (selectedSlice.value / total * 100).toStringAsFixed(1) : '0.0'}%',
                        style: TextStyle(
                          fontSize: badgeFontSize,
                          fontWeight: FontWeight.w700,
                          color: selectedSlice.color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      period.isPlanned ? '计划总额' : '总净支出',
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatFinanceAmount(total),
                        style: TextStyle(
                          fontSize: amountFontSize,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 $categoryCount 项分类',
                      style: TextStyle(
                        fontSize: badgeFontSize,
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedCategoryRow(
    BuildContext context,
    _FinanceCategoryTotal entry, {
    required int shareValue,
    required Color color,
    required int total,
    required _FinanceOverviewPeriod period,
    required ColorScheme colorScheme,
    required bool isSelected,
  }) {
    final category = entry.categoryUuid == null
        ? null
        : widget.categories[entry.categoryUuid];
    final categoryName = widget.categoryDisplayName(entry.categoryUuid);
    final categoryLabel = category == null
        ? categoryName
        : '${category.isArchived ? '已归档 ' : ''}$categoryName';
    final percentage = total > 0
        ? (shareValue / total * 100).toStringAsFixed(1)
        : '0.0';
    final categoryKey = ValueKey(
      'finance-overview-category-${entry.categoryUuid ?? 'uncategorized'}',
    );
    final sourceKey = widget.categorySourceKeys.putIfAbsent(
      entry.categoryUuid ?? 'uncategorized',
      GlobalKey.new,
    );
    final isDark = colorScheme.brightness == Brightness.dark;

    return Semantics(
      key: categoryKey,
      button: true,
      label: '查看$categoryLabel支出详情',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.16 : 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: isDark ? 0.45 : 0.35)
                : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: InkWell(
          key: sourceKey,
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onOpenCategoryDetail(entry, period, sourceKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _selectedCategoryUuid = isSelected
                          ? null
                          : entry.categoryUuid;
                    });
                    HapticFeedback.selectionClick();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: color.withValues(alpha: isSelected ? 0.6 : 0.25),
                        width: isSelected ? 1.5 : 0.8,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      category?.icon ?? '🏷️',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    categoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      fontSize: 13.5,
                      color: isSelected
                          ? (isDark ? colorScheme.primary : color)
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$percentage%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isSelected ? color : colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 76,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        formatFinanceAmount(entry.value),
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: isSelected
                      ? color
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
