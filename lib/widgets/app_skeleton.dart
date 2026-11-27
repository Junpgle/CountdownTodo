import 'package:flutter/material.dart';

import '../services/animation_config_service.dart';
import '../services/power_save_mode_service.dart';
import '../utils/android_energy_policy.dart';
import 'app_state_views.dart';

class _AppSkeletonScopeData extends InheritedWidget {
  final Animation<double>? animation;
  final bool isAnimating;
  final bool isLightSurface;

  const _AppSkeletonScopeData({
    required this.animation,
    required this.isAnimating,
    required this.isLightSurface,
    required super.child,
  });

  static _AppSkeletonScopeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_AppSkeletonScopeData>();
  }

  @override
  bool updateShouldNotify(covariant _AppSkeletonScopeData oldWidget) {
    return oldWidget.animation != animation ||
        oldWidget.isAnimating != isAnimating ||
        oldWidget.isLightSurface != isLightSurface;
  }
}

/// Coordinates a single shimmer ticker for an entire skeleton subtree.
///
/// Motion automatically degrades to static tonal blocks on Windows, in system
/// Battery Saver / Low Power Mode, or when platform animations are disabled.
class AppSkeletonScope extends StatefulWidget {
  final Widget child;
  final bool animate;
  final bool isLightSurface;
  final Duration duration;

  const AppSkeletonScope({
    super.key,
    required this.child,
    this.animate = true,
    this.isLightSurface = false,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<AppSkeletonScope> createState() => _AppSkeletonScopeState();
}

class _AppSkeletonScopeState extends State<AppSkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _isAnimating = false;
  bool _disableAnimations = false;
  bool _skeletonEnabled = AnimationConfigService.skeletonScreenEnabled;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
    PowerSaveModeService.enabledListenable.addListener(_syncMotionState);
    AnimationConfigService.skeletonScreenEnabledListenable.addListener(
      _handleSkeletonSettingChanged,
    );
  }

  void _handleSkeletonSettingChanged() {
    final next = AnimationConfigService.skeletonScreenEnabled;
    if (next == _skeletonEnabled) return;
    _skeletonEnabled = next;
    _syncMotionState();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    _syncMotionState();
  }

  @override
  void didUpdateWidget(covariant AppSkeletonScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.animate != widget.animate ||
        oldWidget.duration != widget.duration) {
      _syncMotionState();
    }
  }

  void _syncMotionState() {
    final shouldAnimate =
        _skeletonEnabled &&
        widget.animate &&
        AndroidEnergyPolicy.shouldRunDecorativeMotion &&
        !_disableAnimations;
    if (shouldAnimate == _isAnimating) return;
    _isAnimating = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    AnimationConfigService.skeletonScreenEnabledListenable.removeListener(
      _handleSkeletonSettingChanged,
    );
    PowerSaveModeService.enabledListenable.removeListener(_syncMotionState);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_skeletonEnabled) {
      return const AppLoadingView();
    }
    return _AppSkeletonScopeData(
      animation: _isAnimating ? _animation : null,
      isAnimating: _isAnimating,
      isLightSurface: widget.isLightSurface,
      child: widget.child,
    );
  }
}

class _AppSkeletonShimmerPainter extends CustomPainter {
  _AppSkeletonShimmerPainter({
    required this.animation,
    required this.baseColor,
    required this.highlightColor,
    required this.borderRadius,
    required this.shape,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color baseColor;
  final Color highlightColor;
  final BorderRadius borderRadius;
  final BoxShape shape;

  late final List<Color> _colors = [baseColor, highlightColor, baseColor];
  final Paint _paint = Paint()..isAntiAlias = true;
  Size? _cachedSize;
  Rect? _cachedRect;
  RRect? _cachedRRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (_cachedSize != size) {
      final rect = Offset.zero & size;
      _cachedSize = size;
      _cachedRect = rect;
      _cachedRRect = shape == BoxShape.circle
          ? null
          : borderRadius.toRRect(rect);
    }

    final t = animation.value;
    _paint.shader = LinearGradient(
      begin: Alignment(t - 0.55, -0.25),
      end: Alignment(t + 0.55, 0.25),
      colors: _colors,
      stops: const [0.0, 0.5, 1.0],
    ).createShader(_cachedRect!);

    if (shape == BoxShape.circle) {
      final radius = size.shortestSide * 0.5;
      canvas.drawCircle(size.center(Offset.zero), radius, _paint);
    } else {
      canvas.drawRRect(_cachedRRect!, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AppSkeletonShimmerPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.shape != shape;
  }
}

/// A tonal placeholder rectangle or circle that shimmers when inside an active
/// [AppSkeletonScope].
class AppSkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final bool? isLightSurface;
  final BoxShape shape;

  const AppSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 10,
    this.margin,
    this.isLightSurface,
    this.shape = BoxShape.rectangle,
  });

  static ({Color base, Color highlight}) _colorsFor(
    BuildContext context,
    bool lightSurface,
  ) {
    if (lightSurface) {
      return (
        base: Colors.white.withValues(alpha: 0.18),
        highlight: Colors.white.withValues(alpha: 0.34),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return (
      base: scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.065),
      highlight: scheme.onSurface.withValues(alpha: isDark ? 0.165 : 0.135),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _AppSkeletonScopeData.maybeOf(context);
    final effectiveLight = isLightSurface ?? scope?.isLightSurface ?? false;
    final colors = _colorsFor(context, effectiveLight);
    final effectiveRadius = shape == BoxShape.circle
        ? BorderRadius.zero
        : BorderRadius.circular(borderRadius);
    final resolvedWidth = width == double.infinity ? null : width;

    Widget box;
    if (scope != null && scope.isAnimating && scope.animation != null) {
      box = RepaintBoundary(
        child: CustomPaint(
          painter: _AppSkeletonShimmerPainter(
            animation: scope.animation!,
            baseColor: colors.base,
            highlightColor: colors.highlight,
            borderRadius: effectiveRadius,
            shape: shape,
          ),
          child: SizedBox(
            width: resolvedWidth ?? double.infinity,
            height: height,
          ),
        ),
      );
    } else {
      box = DecoratedBox(
        decoration: BoxDecoration(
          color: colors.base,
          shape: shape,
          borderRadius: shape == BoxShape.circle ? null : effectiveRadius,
        ),
        child: SizedBox(
          width: resolvedWidth ?? double.infinity,
          height: height,
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: box);
    }
    return box;
  }
}

/// Circular skeleton placeholder for avatars, icons, and ring charts.
class AppSkeletonCircle extends StatelessWidget {
  final double size;
  final bool? isLightSurface;

  const AppSkeletonCircle({super.key, this.size = 40, this.isLightSurface});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonBox(
      width: size,
      height: size,
      shape: BoxShape.circle,
      isLightSurface: isLightSurface,
    );
  }
}

/// Single-line text skeleton placeholder.
class AppSkeletonLine extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final bool? isLightSurface;

  const AppSkeletonLine({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 6,
    this.isLightSurface,
  });

  @override
  Widget build(BuildContext context) {
    return AppSkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
      isLightSurface: isLightSurface,
    );
  }
}

/// Material 3 themed container card for grouping skeleton placeholders.
class AppSkeletonCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool? isLightSurface;

  const AppSkeletonCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.isLightSurface,
  });

  @override
  Widget build(BuildContext context) {
    final scope = _AppSkeletonScopeData.maybeOf(context);
    final effectiveLight = isLightSurface ?? scope?.isLightSurface ?? false;
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = effectiveLight
        ? Colors.white.withValues(alpha: 0.08)
        : scheme.surfaceContainerLow;
    final borderColor = effectiveLight
        ? Colors.white.withValues(alpha: 0.14)
        : scheme.outlineVariant.withValues(alpha: 0.35);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    return card;
  }
}

class _AppSkeletonViewportShell extends StatelessWidget {
  final Widget child;
  final double topPadding;
  final double bottomPadding;
  final double horizontalPadding;
  final double? maxWidth;
  final bool shrinkWrap;
  final bool isLightSurface;

  const _AppSkeletonViewportShell({
    required this.child,
    this.topPadding = 0,
    this.bottomPadding = 24,
    this.horizontalPadding = 16,
    this.maxWidth,
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedPadding = EdgeInsets.fromLTRB(
      horizontalPadding,
      topPadding,
      horizontalPadding,
      bottomPadding,
    );
    Widget content = Padding(padding: resolvedPadding, child: child);
    if (maxWidth != null) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: content,
        ),
      );
    }
    if (!shrinkWrap) {
      content = SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: content,
      );
    }
    return Semantics(
      label: '加载中',
      child: ExcludeSemantics(
        child: AppSkeletonScope(isLightSurface: isLightSurface, child: content),
      ),
    );
  }
}

class _SkeletonResponsiveGrid extends StatelessWidget {
  final int columns;
  final List<Widget> items;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  const _SkeletonResponsiveGrid({
    super.key,
    required this.columns,
    required this.items,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(1, 6);
    if (cols == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1) SizedBox(height: mainAxisSpacing),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i += cols) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < cols; c++) ...[
                Expanded(
                  child: i + c < items.length
                      ? items[i + c]
                      : const SizedBox.shrink(),
                ),
                if (c < cols - 1) SizedBox(width: crossAxisSpacing),
              ],
            ],
          ),
          if (i + cols < items.length) SizedBox(height: mainAxisSpacing),
        ],
      ],
    );
  }
}

class _SkeletonGridTileCard extends StatelessWidget {
  final double visualHeight;

  const _SkeletonGridTileCard({this.visualHeight = 68});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeletonBox(height: visualHeight, borderRadius: 10),
          const SizedBox(height: 10),
          const FractionallySizedBox(
            widthFactor: 0.72,
            child: AppSkeletonLine(height: 12),
          ),
          const SizedBox(height: 6),
          const FractionallySizedBox(
            widthFactor: 0.48,
            child: AppSkeletonLine(height: 10),
          ),
        ],
      ),
    );
  }
}

class _SkeletonListItemCard extends StatelessWidget {
  final double height;

  const _SkeletonListItemCard({required this.height});

  @override
  Widget build(BuildContext context) {
    final compact = height < 68;
    return AppSkeletonCard(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 10 : 14,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (height - 28).clamp(28.0, 200.0),
        ),
        child: Row(
          children: [
            AppSkeletonCircle(size: compact ? 32 : 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FractionallySizedBox(
                    widthFactor: 0.58,
                    child: AppSkeletonLine(height: 14),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: compact ? 0.36 : 0.42,
                    child: const AppSkeletonLine(height: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppSkeletonBox(
              width: compact ? 48 : 56,
              height: compact ? 22 : 26,
              borderRadius: 13,
            ),
          ],
        ),
      ),
    );
  }
}

/// Responsive wide layout strategies for [AppSkeletonDashboardPage].
enum AppSkeletonDashboardWideLayout {
  /// Always stacks metrics, chart, and list vertically.
  singleColumn,

  /// Two-pane layout: metrics/chart in the left column, cards/list in the right.
  splitColumns,

  /// Top row places metrics beside the chart, followed by a multi-column grid.
  metricsAndGrid,
}

/// Skeleton preset for list-based screens and tabs.
class AppSkeletonListPage extends StatelessWidget {
  final double topPadding;
  final double bottomPadding;
  final double horizontalPadding;
  final double? wideHorizontalPadding;
  final double? maxWidth;
  final int itemCount;
  final double itemHeight;
  final bool showHeroCard;
  final double heroHeight;
  final bool showSearchBar;
  final bool showFilterChips;
  final bool useTwoColumnsOnWide;
  final double wideBreakpoint;
  final int narrowColumns;
  final int? wideColumns;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonListPage({
    super.key,
    this.topPadding = 12,
    this.bottomPadding = 24,
    this.horizontalPadding = 16,
    this.wideHorizontalPadding,
    this.maxWidth,
    this.itemCount = 5,
    this.itemHeight = 84,
    this.showHeroCard = false,
    this.heroHeight = 112,
    this.showSearchBar = false,
    this.showFilterChips = false,
    this.useTwoColumnsOnWide = false,
    this.wideBreakpoint = 640,
    this.narrowColumns = 1,
    this.wideColumns,
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= wideBreakpoint;
        final resolvedWideColumns =
            wideColumns ?? (useTwoColumnsOnWide ? 2 : narrowColumns);
        final columns = (isWide ? resolvedWideColumns : narrowColumns).clamp(
          1,
          4,
        );
        final resolvedHorizontalPadding = isWide
            ? (wideHorizontalPadding ?? horizontalPadding)
            : horizontalPadding;
        final gridItems = List<Widget>.generate(
          itemCount,
          (_) => columns >= 3
              ? const _SkeletonGridTileCard()
              : _SkeletonListItemCard(height: itemHeight),
          growable: false,
        );

        return _AppSkeletonViewportShell(
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          horizontalPadding: resolvedHorizontalPadding,
          maxWidth: maxWidth,
          shrinkWrap: shrinkWrap,
          isLightSurface: isLightSurface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSearchBar) ...[
                const AppSkeletonBox(height: 44, borderRadius: 22),
                const SizedBox(height: 12),
              ],
              if (showFilterChips) ...[
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      AppSkeletonBox(width: 68, height: 30, borderRadius: 15),
                      SizedBox(width: 8),
                      AppSkeletonBox(width: 82, height: 30, borderRadius: 15),
                      SizedBox(width: 8),
                      AppSkeletonBox(width: 74, height: 30, borderRadius: 15),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (showHeroCard) ...[
                AppSkeletonCard(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: (heroHeight - 32).clamp(48.0, 220.0),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AppSkeletonLine(width: 110, height: 14),
                            AppSkeletonBox(
                              width: 64,
                              height: 22,
                              borderRadius: 11,
                            ),
                          ],
                        ),
                        AppSkeletonLine(width: 160, height: 22),
                        AppSkeletonBox(height: 10, borderRadius: 5),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _SkeletonResponsiveGrid(
                key: columns > 1
                    ? ValueKey<String>('app-skeleton-list-grid-$columns')
                    : null,
                columns: columns,
                items: gridItems,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Skeleton preset for analytics/overview dashboards with metrics, charts, and lists.
class AppSkeletonDashboardPage extends StatelessWidget {
  final double topPadding;
  final double bottomPadding;
  final double horizontalPadding;
  final double? wideHorizontalPadding;
  final double? maxWidth;
  final bool showPeriodHeader;
  final bool showFilterChips;
  final bool showTopHeaderSpan;
  final bool showMetricGrid;
  final int metricCount;
  final bool showChart;
  final double chartHeight;
  final int listCount;
  final AppSkeletonDashboardWideLayout wideLayout;
  final double wideBreakpoint;
  final int leftFlex;
  final int rightFlex;
  final int wideListColumns;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonDashboardPage({
    super.key,
    this.topPadding = 12,
    this.bottomPadding = 24,
    this.horizontalPadding = 16,
    this.wideHorizontalPadding,
    this.maxWidth,
    this.showPeriodHeader = false,
    this.showFilterChips = false,
    this.showTopHeaderSpan = false,
    this.showMetricGrid = true,
    this.metricCount = 3,
    this.showChart = true,
    this.chartHeight = 190,
    this.listCount = 4,
    this.wideLayout = AppSkeletonDashboardWideLayout.singleColumn,
    this.wideBreakpoint = 768,
    this.leftFlex = 4,
    this.rightFlex = 5,
    this.wideListColumns = 1,
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  Widget _buildMetricCard(int effectiveMetricCount) {
    return AppSkeletonCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          for (var i = 0; i < effectiveMetricCount; i++) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FractionallySizedBox(
                    widthFactor: 0.65,
                    child: AppSkeletonLine(height: 11),
                  ),
                  const SizedBox(height: 10),
                  FractionallySizedBox(
                    widthFactor: i.isEven ? 0.85 : 0.72,
                    child: const AppSkeletonLine(height: 20),
                  ),
                ],
              ),
            ),
            if (i < effectiveMetricCount - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    final barAreaHeight = (chartHeight - 70).clamp(72.0, 220.0);
    const barFactors = [0.52, 0.84, 0.68, 1.0, 0.76, 0.60];
    return AppSkeletonCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppSkeletonLine(width: 112, height: 15),
              AppSkeletonBox(width: 60, height: 22, borderRadius: 11),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: barAreaHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < barFactors.length; i++) ...[
                  Expanded(
                    child: AppSkeletonBox(
                      height: barAreaHeight * barFactors[i],
                    ),
                  ),
                  if (i < barFactors.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSection(int columns) {
    final effectiveColumns = columns.clamp(1, 3);
    final items = List<Widget>.generate(
      listCount,
      (_) => effectiveColumns >= 2 && wideListColumns >= 2
          ? const _SkeletonGridTileCard(visualHeight: 56)
          : const _SkeletonListItemCard(height: 74),
      growable: false,
    );
    return _SkeletonResponsiveGrid(columns: effectiveColumns, items: items);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveMetricCount = metricCount.clamp(1, 4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final isWide =
            wideLayout != AppSkeletonDashboardWideLayout.singleColumn &&
            maxW >= wideBreakpoint;
        final useMediumGrid =
            !isWide && wideListColumns > 1 && maxW >= 600 && listCount > 1;
        final resolvedHorizontalPadding = isWide
            ? (wideHorizontalPadding ?? horizontalPadding)
            : horizontalPadding;

        Widget body;
        if (isWide &&
            wideLayout == AppSkeletonDashboardWideLayout.splitColumns) {
          body = KeyedSubtree(
            key: const ValueKey<String>('app-skeleton-dashboard-split'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: leftFlex,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showMetricGrid)
                        _buildMetricCard(effectiveMetricCount),
                      if (showMetricGrid && showChart)
                        const SizedBox(height: 14),
                      if (showChart) _buildChartCard(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: rightFlex,
                  child: _buildListSection(wideListColumns),
                ),
              ],
            ),
          );
        } else if (isWide &&
            wideLayout == AppSkeletonDashboardWideLayout.metricsAndGrid) {
          final gridColumns = (wideListColumns > 1 ? wideListColumns : 2).clamp(
            2,
            3,
          );
          body = KeyedSubtree(
            key: const ValueKey<String>('app-skeleton-dashboard-grid'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showMetricGrid && showChart) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: _buildMetricCard(effectiveMetricCount),
                      ),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: _buildChartCard()),
                    ],
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  if (showMetricGrid) ...[
                    _buildMetricCard(effectiveMetricCount),
                    const SizedBox(height: 14),
                  ],
                  if (showChart) ...[
                    _buildChartCard(),
                    const SizedBox(height: 14),
                  ],
                ],
                if (listCount > 0) _buildListSection(gridColumns),
              ],
            ),
          );
        } else {
          body = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showMetricGrid) ...[
                _buildMetricCard(effectiveMetricCount),
                const SizedBox(height: 14),
              ],
              if (showChart) ...[_buildChartCard(), const SizedBox(height: 14)],
              if (listCount > 0) _buildListSection(useMediumGrid ? 2 : 1),
            ],
          );
        }

        return _AppSkeletonViewportShell(
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          horizontalPadding: resolvedHorizontalPadding,
          maxWidth: maxWidth,
          shrinkWrap: shrinkWrap,
          isLightSurface: isLightSurface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showPeriodHeader) ...[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppSkeletonBox(width: 140, height: 34, borderRadius: 17),
                    AppSkeletonBox(width: 96, height: 34, borderRadius: 17),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (showFilterChips) ...[
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      AppSkeletonBox(width: 64, height: 30, borderRadius: 15),
                      SizedBox(width: 8),
                      AppSkeletonBox(width: 78, height: 30, borderRadius: 15),
                      SizedBox(width: 8),
                      AppSkeletonBox(width: 72, height: 30, borderRadius: 15),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (showTopHeaderSpan) ...[
                const _SkeletonListItemCard(height: 88),
                const SizedBox(height: 14),
              ],
              body,
            ],
          ),
        );
      },
    );
  }
}

/// Skeleton preset for calendar, week grid, and day-grid views.
class AppSkeletonCalendarPage extends StatelessWidget {
  final double topPadding;
  final double bottomPadding;
  final double? maxWidth;
  final bool showHeaderStrip;
  final int gridColumns;
  final int gridRows;
  final bool showDetailCards;
  final bool splitOnWide;
  final double wideBreakpoint;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonCalendarPage({
    super.key,
    this.topPadding = 12,
    this.bottomPadding = 24,
    this.maxWidth,
    this.showHeaderStrip = true,
    this.gridColumns = 7,
    this.gridRows = 5,
    this.showDetailCards = true,
    this.splitOnWide = false,
    this.wideBreakpoint = 600,
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final cols = gridColumns.clamp(3, 7);
    final rows = gridRows.clamp(3, 6);

    final calendarCard = AppSkeletonCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var c = 0; c < cols; c++) ...[
                const Expanded(child: AppSkeletonLine(height: 12)),
                if (c < cols - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (var r = 0; r < rows; r++) ...[
            Row(
              children: [
                for (var c = 0; c < cols; c++) ...[
                  const Expanded(
                    child: AppSkeletonBox(height: 36, borderRadius: 10),
                  ),
                  if (c < cols - 1) const SizedBox(width: 8),
                ],
              ],
            ),
            if (r < rows - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );

    const headerStrip = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AppSkeletonCircle(size: 36),
        AppSkeletonBox(width: 132, height: 26, borderRadius: 13),
        AppSkeletonCircle(size: 36),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final split =
            splitOnWide &&
            showDetailCards &&
            constraints.maxWidth >= wideBreakpoint;

        return _AppSkeletonViewportShell(
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          maxWidth: maxWidth,
          shrinkWrap: shrinkWrap,
          isLightSurface: isLightSurface,
          child: split
              ? Row(
                  key: const ValueKey<String>('app-skeleton-calendar-split'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeaderStrip) ...[
                            headerStrip,
                            const SizedBox(height: 14),
                          ],
                          calendarCard,
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: FractionallySizedBox(
                              widthFactor: 0.45,
                              alignment: Alignment.centerLeft,
                              child: AppSkeletonLine(height: 16),
                            ),
                          ),
                          _SkeletonListItemCard(height: 78),
                          SizedBox(height: 12),
                          _SkeletonListItemCard(height: 78),
                          SizedBox(height: 12),
                          _SkeletonListItemCard(height: 78),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showHeaderStrip) ...[
                      headerStrip,
                      const SizedBox(height: 14),
                    ],
                    calendarCard,
                    if (showDetailCards) ...[
                      const SizedBox(height: 14),
                      const _SkeletonListItemCard(height: 78),
                      const SizedBox(height: 12),
                      const _SkeletonListItemCard(height: 78),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// Skeleton preset for editor and form pages.
class AppSkeletonFormPage extends StatelessWidget {
  final double topPadding;
  final double bottomPadding;
  final double? maxWidth;
  final bool showAmountHeader;
  final int fieldCount;
  final bool twoColumnOnWide;
  final double wideBreakpoint;
  final bool showPreviewHeaderOnWide;
  final bool showStepperHeaderOnWide;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonFormPage({
    super.key,
    this.topPadding = 12,
    this.bottomPadding = 24,
    this.maxWidth = 720,
    this.showAmountHeader = false,
    this.fieldCount = 5,
    this.twoColumnOnWide = false,
    this.wideBreakpoint = 620,
    this.showPreviewHeaderOnWide = false,
    this.showStepperHeaderOnWide = false,
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final fields = List<Widget>.generate(
      fieldCount,
      (_) => const AppSkeletonCard(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeletonLine(width: 82, height: 11),
            SizedBox(height: 10),
            AppSkeletonLine(height: 16),
          ],
        ),
      ),
      growable: false,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            (twoColumnOnWide ||
                showPreviewHeaderOnWide ||
                showStepperHeaderOnWide) &&
            constraints.maxWidth >= wideBreakpoint;

        return _AppSkeletonViewportShell(
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          maxWidth: maxWidth,
          shrinkWrap: shrinkWrap,
          isLightSurface: isLightSurface,
          child: Column(
            key: isWide
                ? const ValueKey<String>('app-skeleton-form-wide')
                : null,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide && showStepperHeaderOnWide) ...[
                const AppSkeletonCard(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      AppSkeletonCircle(size: 26),
                      SizedBox(width: 8),
                      AppSkeletonLine(width: 64, height: 13),
                      SizedBox(width: 12),
                      Expanded(child: Divider()),
                      SizedBox(width: 12),
                      AppSkeletonCircle(size: 26),
                      SizedBox(width: 8),
                      AppSkeletonLine(width: 64, height: 13),
                      SizedBox(width: 12),
                      Expanded(child: Divider()),
                      SizedBox(width: 12),
                      AppSkeletonCircle(size: 26),
                      SizedBox(width: 8),
                      AppSkeletonLine(width: 64, height: 13),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isWide && showPreviewHeaderOnWide) ...[
                const AppSkeletonCard(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonLine(width: 140, height: 18),
                      SizedBox(height: 10),
                      AppSkeletonLine(width: 240, height: 13),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (showAmountHeader) ...[
                const AppSkeletonCard(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonLine(width: 88, height: 12),
                      SizedBox(height: 12),
                      AppSkeletonLine(width: 180, height: 32, borderRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _SkeletonResponsiveGrid(
                columns: isWide && twoColumnOnWide ? 2 : 1,
                crossAxisSpacing: 14,
                mainAxisSpacing: 12,
                items: fields,
              ),
              const SizedBox(height: 18),
              if (isWide)
                const Align(
                  alignment: Alignment.centerRight,
                  child: AppSkeletonBox(
                    width: 180,
                    height: 48,
                    borderRadius: 24,
                  ),
                )
              else
                const AppSkeletonBox(height: 48, borderRadius: 24),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonSettingsSectionBody extends StatelessWidget {
  final int rows;
  final bool showHeader;

  const _SkeletonSettingsSectionBody({
    required this.rows,
    required this.showHeader,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: AppSkeletonLine(width: 96, height: 13),
          ),
        ],
        AppSkeletonCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const AppSkeletonCircle(size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: i.isEven ? 0.52 : 0.64,
                              child: const AppSkeletonLine(height: 13),
                            ),
                            const SizedBox(height: 6),
                            const FractionallySizedBox(
                              widthFactor: 0.38,
                              child: AppSkeletonLine(height: 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const AppSkeletonBox(
                        width: 42,
                        height: 22,
                        borderRadius: 11,
                      ),
                    ],
                  ),
                ),
                if (i < rows - 1) const Divider(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact non-scrolling settings card block for embedded settings sections.
class AppSkeletonSettingsSection extends StatelessWidget {
  final int rows;
  final bool showHeader;
  final bool isLightSurface;

  const AppSkeletonSettingsSection({
    super.key,
    this.rows = 3,
    this.showHeader = true,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = _SkeletonSettingsSectionBody(
      rows: rows,
      showHeader: showHeader,
    );
    if (_AppSkeletonScopeData.maybeOf(context) != null) {
      return body;
    }
    return Semantics(
      label: '加载中',
      child: ExcludeSemantics(
        child: AppSkeletonScope(isLightSurface: isLightSurface, child: body),
      ),
    );
  }
}

/// Skeleton preset for settings screens (supports responsive two-column and
/// master-detail layouts).
class AppSkeletonSettingsPage extends StatelessWidget {
  final double topPadding;
  final double bottomPadding;
  final double? maxWidth;
  final int sectionCount;
  final int rowsPerSection;
  final bool twoColumnOnWide;
  final double wideBreakpoint;
  final bool masterDetailOnWide;
  final double masterDetailBreakpoint;
  final double sidebarWidth;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonSettingsPage({
    super.key,
    this.topPadding = 16,
    this.bottomPadding = 32,
    this.maxWidth,
    this.sectionCount = 3,
    this.rowsPerSection = 3,
    this.twoColumnOnWide = false,
    this.wideBreakpoint = 600,
    this.masterDetailOnWide = false,
    this.masterDetailBreakpoint = 800,
    this.sidebarWidth = 280,
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final primaryCount = (sectionCount / 2).ceil().clamp(1, sectionCount);
    final secondaryCount = (sectionCount - primaryCount).clamp(1, sectionCount);

    Widget buildColumn(int count) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          _SkeletonSettingsSectionBody(rows: rowsPerSection, showHeader: true),
          if (i < count - 1) const SizedBox(height: 18),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (masterDetailOnWide &&
            constraints.maxWidth >= masterDetailBreakpoint) {
          final scheme = Theme.of(context).colorScheme;
          final isDark = scheme.brightness == Brightness.dark;
          final sidebarContent = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSkeletonBox(height: 40, borderRadius: 20),
              const SizedBox(height: 16),
              const Row(
                children: [
                  AppSkeletonCircle(size: 40),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 0.6,
                          child: AppSkeletonLine(height: 14),
                        ),
                        SizedBox(height: 6),
                        FractionallySizedBox(
                          widthFactor: 0.42,
                          child: AppSkeletonLine(height: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < 6; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const AppSkeletonCircle(size: 24),
                      const SizedBox(width: 12),
                      FractionallySizedBox(
                        widthFactor: null,
                        child: AppSkeletonLine(
                          width: i.isEven ? 116 : 96,
                          height: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );

          final rightContent = buildColumn(sectionCount);
          return Semantics(
            label: '加载中',
            child: ExcludeSemantics(
              child: AppSkeletonScope(
                isLightSurface: isLightSurface,
                child: Row(
                  key: const ValueKey<String>(
                    'app-skeleton-settings-master-detail',
                  ),
                  crossAxisAlignment: shrinkWrap
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: sidebarWidth,
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: isDark ? 0.3 : 0.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 20,
                      ),
                      child: shrinkWrap
                          ? sidebarContent
                          : SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: sidebarContent,
                            ),
                    ),
                    if (!shrinkWrap)
                      const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: shrinkWrap
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                20,
                                24,
                                32,
                              ),
                              child: rightContent,
                            )
                          : SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                20,
                                24,
                                32,
                              ),
                              child: rightContent,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final useTwoColumns =
            twoColumnOnWide && constraints.maxWidth > wideBreakpoint;

        return _AppSkeletonViewportShell(
          topPadding: topPadding,
          bottomPadding: bottomPadding,
          maxWidth: maxWidth,
          shrinkWrap: shrinkWrap,
          isLightSurface: isLightSurface,
          child: useTwoColumns
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: buildColumn(primaryCount)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: buildColumn(secondaryCount)),
                  ],
                )
              : buildColumn(sectionCount),
        );
      },
    );
  }
}

/// Compact skeleton preset for bottom sheets, dialogs, and embedded sub-lists.
class AppSkeletonSheetList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonSheetList({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 56,
    this.padding = const EdgeInsets.all(16),
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            _SkeletonListItemCard(height: itemHeight),
            if (i < itemCount - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );

    if (!shrinkWrap) {
      body = SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: body,
      );
    }

    return Semantics(
      label: '加载中',
      child: ExcludeSemantics(
        child: AppSkeletonScope(isLightSurface: isLightSurface, child: body),
      ),
    );
  }
}

/// Prose/markdown skeleton preset for privacy policy, changelog, and release notes.
class AppSkeletonDocument extends StatelessWidget {
  final int paragraphs;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final bool isLightSurface;

  const AppSkeletonDocument({
    super.key,
    this.paragraphs = 4,
    this.padding = const EdgeInsets.all(16),
    this.shrinkWrap = false,
    this.isLightSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    const lineWidths = [0.92, 1.0, 0.78, 0.6];

    Widget body = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var p = 0; p < paragraphs; p++) ...[
            FractionallySizedBox(
              widthFactor: p == 0 ? 0.48 : 0.36,
              child: const AppSkeletonLine(height: 18, borderRadius: 7),
            ),
            const SizedBox(height: 12),
            for (var l = 0; l < lineWidths.length; l++) ...[
              FractionallySizedBox(
                widthFactor: lineWidths[l],
                child: const AppSkeletonLine(height: 13),
              ),
              if (l < lineWidths.length - 1) const SizedBox(height: 8),
            ],
            if (p < paragraphs - 1) const SizedBox(height: 20),
          ],
        ],
      ),
    );

    if (!shrinkWrap) {
      body = SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: body,
      );
    }

    return Semantics(
      label: '加载中',
      child: ExcludeSemantics(
        child: AppSkeletonScope(isLightSurface: isLightSurface, child: body),
      ),
    );
  }
}
