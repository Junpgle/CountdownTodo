part of '../finance_widgets.dart';

/// Result of hit-testing a tap on [FinanceCategoryDonutChart].
class FinanceDonutTapHit {
  final bool isHit;
  final bool isCenter;
  final String? categoryUuid;

  const FinanceDonutTapHit._({
    required this.isHit,
    required this.isCenter,
    this.categoryUuid,
  });

  const FinanceDonutTapHit.miss() : this._(isHit: false, isCenter: false);

  const FinanceDonutTapHit.center() : this._(isHit: true, isCenter: true);

  const FinanceDonutTapHit.slice(String? uuid)
    : this._(isHit: true, isCenter: false, categoryUuid: uuid);
}

/// Resolves whether a tap at [localPosition] hits the center hole, a slice, or
/// misses the ring entirely.
FinanceDonutTapHit hitTestFinanceDonutSlice({
  required Offset localPosition,
  required double chartSize,
  required List<FinanceDonutSlice> slices,
  required int total,
  double largeRadiusInset = 16.0,
}) {
  if (total <= 0 || slices.isEmpty) return const FinanceDonutTapHit.miss();
  final center = Offset(chartSize / 2, chartSize / 2);
  final distance = (localPosition - center).distance;
  final isLarge = chartSize >= 160.0;
  final baseRadius = chartSize / 2 - (isLarge ? largeRadiusInset : 14.0);

  if (distance < baseRadius - (isLarge ? 18.0 : 15.0)) {
    return const FinanceDonutTapHit.center();
  }

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
        return FinanceDonutTapHit.slice(slice.categoryUuid);
      }
      accumulated += sweep;
    }
  }

  return const FinanceDonutTapHit.miss();
}

/// Interactive category/subcategory donut chart with center summary switcher.
class FinanceCategoryDonutChart extends StatelessWidget {
  final List<FinanceDonutSlice> slices;
  final int total;
  final double donutSize;
  final Animation<double> sweepAnimation;
  final ColorScheme colorScheme;
  final String? selectedCategoryUuid;
  final ValueChanged<String?> onSelectCategory;
  final String totalTitle;
  final String countLabel;
  final String totalContentKey;
  final String selectedKeyPrefix;
  final double largeRadiusInset;
  final FontWeight totalTitleFontWeight;
  final Color? countLabelColor;

  const FinanceCategoryDonutChart({
    super.key,
    required this.slices,
    required this.total,
    required this.donutSize,
    required this.sweepAnimation,
    required this.colorScheme,
    required this.selectedCategoryUuid,
    required this.onSelectCategory,
    required this.totalTitle,
    required this.countLabel,
    required this.totalContentKey,
    this.selectedKeyPrefix = '',
    this.largeRadiusInset = 16.0,
    this.totalTitleFontWeight = FontWeight.w500,
    this.countLabelColor,
  });

  FinanceDonutSlice? _selectedSlice() {
    if (selectedCategoryUuid == null) return null;
    for (final slice in slices) {
      if (slice.categoryUuid == selectedCategoryUuid) {
        return slice;
      }
    }
    return null;
  }

  void _handleTapUp(Offset localPosition) {
    final hit = hitTestFinanceDonutSlice(
      localPosition: localPosition,
      chartSize: donutSize,
      slices: slices,
      total: total,
      largeRadiusInset: largeRadiusInset,
    );
    if (!hit.isHit) return;
    if (hit.isCenter) {
      if (selectedCategoryUuid != null) {
        onSelectCategory(null);
        HapticFeedback.selectionClick();
      }
      return;
    }
    final nextUuid = selectedCategoryUuid == hit.categoryUuid
        ? null
        : hit.categoryUuid;
    onSelectCategory(nextUuid);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final selectedSlice = _selectedSlice();
    final isLarge = donutSize >= 160.0;
    final titleFontSize = isLarge ? 13.5 : 11.5;
    final amountFontSize = isLarge ? 22.0 : 17.0;
    final badgeFontSize = isLarge ? 11.5 : 10.0;
    final badgePadding = isLarge
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5)
        : const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5);
    final contentKey = ValueKey(
      selectedSlice != null
          ? '$selectedKeyPrefix${selectedSlice.categoryUuid}'
          : totalContentKey,
    );

    return SizedBox(
      height: donutSize + 4,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapUp(details.localPosition),
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
                      selectedCategoryUuid: selectedCategoryUuid,
                      sweepProgress: sweepAnimation.value,
                      sweepAnimation: sweepAnimation,
                      emptyColor: colorScheme.surfaceContainerHighest,
                      isDark: isDark,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLarge ? 20.0 : 14.0,
                      ),
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
                                child: ScaleTransition(
                                  scale: scale,
                                  child: child,
                                ),
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
                                        style: TextStyle(
                                          fontSize: isLarge ? 14 : 12,
                                        ),
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
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
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
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  totalTitle,
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: totalTitleFontWeight,
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
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  countLabel,
                                  style: TextStyle(
                                    fontSize: badgeFontSize,
                                    color:
                                        countLabelColor ?? colorScheme.outline,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
