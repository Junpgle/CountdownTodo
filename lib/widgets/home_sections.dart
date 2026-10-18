import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:intl/intl.dart' hide TextDirection;
import '../services/liquid_glass_effect_service.dart';
import '../utils/time_utils.dart';
import '../utils/app_platform.dart';
import 'floating_glass_control.dart';
import 'optional_liquid_glass_surface.dart';

/// 通用的板块标题
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onAdd;
  final Key? addKey; // 🚀 新增 addKey 用于高亮引导
  final VoidCallback? onAction; // 📁 新增操作回调
  final Key? actionKey; // 🚀 新增 actionKey 用于高亮引导
  final IconData? actionIcon; // 📁 新增操作图标
  final String? actionTooltip; // 📁 新增操作提示
  final bool isLight;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.onAdd,
    this.addKey,
    this.onAction,
    this.actionKey,
    this.actionIcon,
    this.actionTooltip,
    this.isLight = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color? textColor = isLight ? Colors.white : null;
    final Color iconColor =
        isLight ? Colors.white70 : Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: textColor,
                ),
          ),
          const Spacer(),
          if (onAction != null && actionIcon != null) ...[
            SizedBox(
              key: actionKey,
              child: IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: floatingGlassStandardControlSize,
                  height: floatingGlassStandardControlSize,
                ),
                visualDensity: VisualDensity.standard,
                style: floatingGlassPlainIconButtonStyle(),
                icon: Icon(actionIcon!, color: iconColor, size: 20),
                onPressed: onAction,
                tooltip: actionTooltip ?? "操作",
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (onAdd != null)
            KeyedSubtree(
              key: addKey,
              child: IconButton(
                constraints: const BoxConstraints.tightFor(
                  width: floatingGlassStandardControlSize,
                  height: floatingGlassStandardControlSize,
                ),
                visualDensity: VisualDensity.standard,
                style: floatingGlassPlainIconButtonStyle(),
                onPressed: onAdd,
                icon: Icon(Icons.add_circle_outline, color: iconColor),
                tooltip: "添加",
              ),
            )
        ],
      ),
    );
  }
}

/// 骨架屏 Shimmer 占位符
class _ShimmerGradientPainter extends CustomPainter {
  _ShimmerGradientPainter({
    required this.animation,
    required this.baseColor,
    required this.highlightColor,
    required this.borderRadius,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color baseColor;
  final Color highlightColor;
  final BorderRadius borderRadius;
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
      _cachedRRect = borderRadius.toRRect(rect);
    }

    _paint.shader = LinearGradient(
      begin: Alignment(animation.value, 0),
      end: Alignment(animation.value + 0.5, 0),
      colors: _colors,
      stops: const [0.0, 0.5, 1.0],
    ).createShader(_cachedRect!);
    canvas.drawRRect(_cachedRRect!, _paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerGradientPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.borderRadius != borderRadius;
}

class _ShimmerPlaceholder extends StatelessWidget {
  final Animation<double> animation;
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerPlaceholder({
    required this.animation,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final baseColor =
        brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[200]!;
    final highlightColor =
        brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[100]!;
    final resolvedBorderRadius = BorderRadius.circular(borderRadius);
    final resolvedWidth = width == double.infinity ? null : width;

    return RepaintBoundary(
      child: CustomPaint(
        painter: _ShimmerGradientPainter(
          animation: animation,
          baseColor: baseColor,
          highlightColor: highlightColor,
          borderRadius: resolvedBorderRadius,
        ),
        // Preserve Container's null-width expansion under bounded parents.
        // ignore: sized_box_for_whitespace
        child: Container(width: resolvedWidth, height: height),
      ),
    );
  }
}

/// 屏幕时间统计卡片
class ScreenTimeCard extends StatefulWidget {
  final List<dynamic> stats;
  final bool isLight;
  final bool hasPermission;
  final bool isLoading;
  final DateTime? lastSyncTime;
  final VoidCallback onOpenSettings;
  final VoidCallback onViewDetail;

  const ScreenTimeCard({
    super.key,
    required this.stats,
    this.isLight = false,
    required this.hasPermission,
    this.isLoading = false,
    this.lastSyncTime,
    required this.onOpenSettings,
    required this.onViewDetail,
  });

  @override
  State<ScreenTimeCard> createState() => _ScreenTimeCardState();
}

class _ScreenTimeChartData {
  final List<dynamic> stats;
  final int totalTime;
  final PieChartPainter devicePainter;
  final PieChartPainter appPainter;

  const _ScreenTimeChartData({
    required this.stats,
    required this.totalTime,
    required this.devicePainter,
    required this.appPainter,
  });
}

class _ScreenTimeCardState extends State<ScreenTimeCard>
    with SingleTickerProviderStateMixin {
  static const _chartAnimationDuration = Duration(milliseconds: 1200);
  static const _shimmerAnimationDuration = Duration(milliseconds: 1500);

  late AnimationController _pieCtrl;
  late Animation<double> _pieAnim;
  late Animation<double> _shimmerAnim;
  _ScreenTimeChartData? _chartData;

  bool get _showsShimmer => widget.hasPermission && widget.isLoading;

  @override
  void initState() {
    super.initState();
    _pieCtrl = AnimationController(
      vsync: this,
      duration: _showsShimmer
          ? _shimmerAnimationDuration
          : _chartAnimationDuration,
    );
    _pieAnim = _pieCtrl.drive(CurveTween(curve: Curves.easeInOutCubic));
    _shimmerAnim = Tween<double>(begin: -2.0, end: 2.0).animate(_pieCtrl);
    if (_showsShimmer) {
      _pieCtrl.repeat();
    } else {
      _pieCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(ScreenTimeCard old) {
    super.didUpdateWidget(old);
    final wasShowingShimmer = old.hasPermission && old.isLoading;
    if (wasShowingShimmer != _showsShimmer ||
        (old.stats != widget.stats && !_showsShimmer)) {
      _pieCtrl
        ..stop()
        ..duration = _showsShimmer
            ? _shimmerAnimationDuration
            : _chartAnimationDuration
        ..reset();
      if (_showsShimmer) {
        _pieCtrl.repeat();
      } else {
        _pieCtrl.forward();
      }
    }
  }

  @override
  void dispose() {
    _pieCtrl.dispose();
    super.dispose();
  }

  String _formatSeconds(int totalSeconds) =>
      formatDurationEnglish(totalSeconds);

  _ScreenTimeChartData _chartDataForCurrentStats() {
    final cached = _chartData;
    if (cached != null && identical(cached.stats, widget.stats)) return cached;

    var totalTime = 0;
    final deviceMap = <String, int>{};
    final aggregatedApps = <String, int>{};
    for (final item in widget.stats) {
      final int duration = item['duration'] as int;
      totalTime += duration;

      String deviceName = item['device_name'] ?? '未知设备';
      if (deviceName.contains('Phone')) {
        deviceName = '手机';
      } else if (deviceName.contains('Tablet')) {
        deviceName = '平板';
      } else if (deviceName.contains('Windows') ||
          deviceName.contains('PC') ||
          deviceName.contains('LAPT')) {
        deviceName = '电脑';
      }
      deviceMap[deviceName] = (deviceMap[deviceName] ?? 0) + duration;

      final String appName = item['app_name'] ?? '未知应用';
      aggregatedApps[appName] = (aggregatedApps[appName] ?? 0) + duration;
    }

    final topApps = <MapEntry<String, int>>[];
    for (final entry in aggregatedApps.entries) {
      var insertAt = 0;
      while (insertAt < topApps.length &&
          topApps[insertAt].value >= entry.value) {
        insertAt++;
      }
      if (insertAt >= 3) continue;

      topApps.insert(insertAt, entry);
      if (topApps.length > 3) topApps.removeLast();
    }
    final appMap = <String, int>{};
    var topSum = 0;
    for (final entry in topApps) {
      appMap[entry.key] = entry.value;
      topSum += entry.value;
    }
    if (totalTime > topSum) {
      appMap['其他'] = totalTime - topSum;
    }

    return _chartData = _ScreenTimeChartData(
      stats: widget.stats,
      totalTime: totalTime,
      devicePainter: PieChartPainter(
        data: deviceMap,
        total: totalTime,
        sweepAnimation: _pieAnim,
      ),
      appPainter: PieChartPainter(
        data: appMap,
        total: totalTime,
        isAppChart: true,
        sweepAnimation: _pieAnim,
      ),
    );
  }

  Widget _buildShimmerLoading(bool isTablet) {
    final colorScheme = Theme.of(context).colorScheme;
    final useDarkGlass =
        widget.isLight || colorScheme.brightness == Brightness.dark;
    return OptionalLiquidGlassCard(
      borderRadius: 24,
      tint: (widget.isLight ? colorScheme.scrim : colorScheme.primary)
          .withValues(alpha: 0.16),
      isDark: useDarkGlass,
      fallbackDecoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 40 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShimmerPlaceholder(
              animation: _shimmerAnim,
              width: 120,
              height: 18,
              borderRadius: 6,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ShimmerPlaceholder(
                    animation: _shimmerAnim,
                    width: double.infinity,
                    height: 60,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShimmerPlaceholder(
                    animation: _shimmerAnim,
                    width: double.infinity,
                    height: 60,
                    borderRadius: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ShimmerPlaceholder(
              animation: _shimmerAnim,
              width: double.infinity,
              height: 14,
              borderRadius: 6,
            ),
            const SizedBox(height: 10),
            _ShimmerPlaceholder(
              animation: _shimmerAnim,
              width: double.infinity,
              height: 14,
              borderRadius: 6,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isTablet = constraints.maxWidth >= 600;
      final colorScheme = Theme.of(context).colorScheme;
      final useDarkGlass =
          widget.isLight || colorScheme.brightness == Brightness.dark;
      final useWallpaperGlass =
          widget.isLight && LiquidGlassEffectService.configuration.enabled;
      final foregroundColor =
          useWallpaperGlass ? colorScheme.onPrimary : colorScheme.onSurface;
      final secondaryColor = useWallpaperGlass
          ? colorScheme.onPrimary.withValues(alpha: 0.7)
          : colorScheme.onSurfaceVariant;
      final permissionForegroundColor =
          widget.isLight ? colorScheme.onPrimary : foregroundColor;
      final permissionSecondaryColor = widget.isLight
          ? colorScheme.onPrimary.withValues(alpha: 0.7)
          : secondaryColor;

      if (!widget.hasPermission) {
        return OptionalLiquidGlassCard(
          margin: const EdgeInsets.only(bottom: 24),
          borderRadius: 24,
          tint: (widget.isLight ? colorScheme.scrim : colorScheme.tertiary)
              .withValues(alpha: 0.16),
          isDark: useDarkGlass,
          fallbackDecoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 24 : 16, vertical: isTablet ? 8 : 4),
              leading: const Icon(Icons.lock_clock, color: Colors.orange),
              title: Text(
                "未开启屏幕时间统计",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: permissionForegroundColor,
                ),
              ),
              subtitle: Text(
                "点击前往开启权限以同步手机使用时长",
                style: TextStyle(color: permissionSecondaryColor),
              ),
              onTap: widget.onOpenSettings,
            ),
          ),
        );
      }

      if (widget.isLoading) {
        return _buildShimmerLoading(isTablet);
      }

      if (widget.stats.isEmpty) {
        return OptionalLiquidGlassCard(
          borderRadius: 24,
          tint: (widget.isLight ? colorScheme.scrim : colorScheme.primary)
              .withValues(alpha: 0.16),
          isDark: useDarkGlass,
          fallbackDecoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isTablet ? 50 : 30),
            child: Center(
              child: Text(
                "今日暂无屏幕使用数据",
                style: TextStyle(color: secondaryColor),
              ),
            ),
          ),
        );
      }

      final chartData = _chartDataForCurrentStats();
      final totalTime = chartData.totalTime;

      return OptionalLiquidGlassCard(
        borderRadius: 24,
        tint: (widget.isLight ? colorScheme.scrim : colorScheme.primary)
            .withValues(alpha: 0.16),
        isDark: useDarkGlass,
        fallbackDecoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onViewDetail,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 28 : 16,
                      vertical: isTablet ? 24 : 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("今日总计",
                                  style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: isTablet ? 15 : 13,
                                      fontWeight: FontWeight.w600)),
                              if (widget.lastSyncTime != null)
                                Text(
                                    "更新: ${DateFormat('HH:mm').format(widget.lastSyncTime!)}",
                                    style: TextStyle(
                                        fontSize: isTablet ? 11 : 10,
                                        color: secondaryColor.withValues(
                                            alpha: 0.7))),
                            ],
                          ),
                          Text(_formatSeconds(totalTime),
                              style: TextStyle(
                                  fontSize: isTablet ? 28 : 22,
                                  fontWeight: FontWeight.bold,
                                  color: useWallpaperGlass
                                      ? foregroundColor
                                      : colorScheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: secondaryColor.withValues(alpha: 0.28),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: isTablet ? 160 : 100,
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: chartData.devicePainter,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text("设备分布",
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        fontWeight: FontWeight.w600,
                                        color: foregroundColor)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: isTablet ? 160 : 100,
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: chartData.appPainter,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text("Top 应用",
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        fontWeight: FontWeight.w600,
                                        color: foregroundColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 增强版饼状图绘图器 (支持响应式缩放 + 绘制动画)
class PieChartPainter extends CustomPainter {
  final Map<String, int> data;
  final int total;
  final bool isAppChart;
  final double sweepProgress;
  final Animation<double>? sweepAnimation;

  double get currentSweepProgress => sweepAnimation?.value ?? sweepProgress;

  late final List<Color> _colors;
  late final List<MapEntry<String, int>> _chartEntries;
  late final List<double> _fullSweepAngles = _chartEntries
      .map((entry) => (entry.value / total) * 2 * math.pi)
      .toList(growable: false);

  // 缓存 TextPainter，避免每帧重复创建
  late final List<TextPainter> _labelPainters;
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  PieChartPainter({
    required this.data,
    required this.total,
    this.isAppChart = false,
    this.sweepProgress = 1.0,
    this.sweepAnimation,
  }) : super(repaint: sweepAnimation) {
    _colors = isAppChart
        ? [
            Colors.blue.shade400,
            Colors.green.shade400,
            Colors.orange.shade400,
            Colors.purple.shade300,
            Colors.cyan.shade300,
          ]
        : [
            Colors.indigo.shade400,
            Colors.teal.shade400,
            Colors.amber.shade600,
            Colors.redAccent.shade200,
          ];
    _chartEntries = data.entries.toList(growable: false);
    _labelPainters = List.generate(_chartEntries.length, (i) {
      String displayLabel = _chartEntries[i].key;
      if (displayLabel.length > 6) {
        displayLabel = "${displayLabel.substring(0, 5)}..";
      }
      return TextPainter(
        text: TextSpan(
          text: displayLabel,
          style: TextStyle(
            color: _colors[i % _colors.length].withValues(alpha: 1.0),
            fontSize: 12, // 默认字号，paint() 中按需缩放
            fontWeight: FontWeight.bold,
            shadows: const [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Colors.black26,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || size.width <= 0 || size.height <= 0) return;

    final currentSweepProgress = this.currentSweepProgress;
    final center = Offset(size.width / 2, size.height / 2);

    final double minDimension = math.min(size.width, size.height);
    final double dynamicStrokeWidth = minDimension * 0.28;
    double radius = (minDimension - dynamicStrokeWidth) / 2 - 25;

    if (radius <= 0) radius = 10;

    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;
    _paint.strokeWidth = dynamicStrokeWidth;

    for (var i = 0; i < _chartEntries.length; i++) {
      final fullSweepAngle = _fullSweepAngles[i];
      final sweepAngle = fullSweepAngle * currentSweepProgress;
      _paint.color = _colors[i % _colors.length];

      canvas.drawArc(rect, startAngle, sweepAngle, false, _paint);

      if (currentSweepProgress > 0.5 && sweepAngle > (math.pi * 3 * 0.02)) {
        final middleAngle = startAngle + sweepAngle / 2;
        final textRadius = radius + (dynamicStrokeWidth / 2) + 12;
        final x = center.dx + textRadius * math.cos(middleAngle);
        final y = center.dy + textRadius * math.sin(middleAngle);

        final textPainter = _labelPainters[i];
        final textOffset =
            Offset(x - textPainter.width / 2, y - textPainter.height / 2);
        textPainter.paint(canvas, textOffset);
      }

      startAngle += fullSweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant PieChartPainter old) =>
      old.data != data ||
      old.total != total ||
      old.isAppChart != isAppChart ||
      old.sweepProgress != sweepProgress ||
      old.sweepAnimation != sweepAnimation;
}

/// 通用的空状态显示（美化版）
class EmptyState extends StatelessWidget {
  final String text;
  final bool isLight;
  const EmptyState({super.key, required this.text, this.isLight = false});
  @override
  Widget build(BuildContext context) {
    Color bgColor = isLight
        ? Colors.white.withValues(alpha: 0.1)
        : Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3);
    Color textColor = isLight ? Colors.white70 : Colors.grey.shade600;

    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: isLight ? 0.15 : 0.3),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.1 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
          color: isLight
              ? Colors.white.withValues(alpha: 0.2)
              : Theme.of(context).dividerColor.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded,
              size: 36, color: textColor.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AppPlatform.isAndroid
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: content,
            ),
    );
  }
}

/// 数学统计卡片
class MathStatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final bool isLight;
  final VoidCallback onTap;
  const MathStatsCard({
    super.key,
    required this.stats,
    this.isLight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final todayCount = stats['todayCount'] ?? 0;
    final accuracy = stats['accuracy'] ?? 0.0;
    final bestTimeVal = stats['bestTime'] != null
        ? (stats['bestTime'] is num
            ? (stats['bestTime'] as num).toInt()
            : int.tryParse(stats['bestTime'].toString()) ?? 0)
        : 0;
    final accuracyInt = (accuracy * 100).toInt();

    return LayoutBuilder(builder: (context, constraints) {
      final bool isTablet = constraints.maxWidth >= 600;
      final colorScheme = Theme.of(context).colorScheme;
      final useDarkGlass = isLight || colorScheme.brightness == Brightness.dark;
      final useWallpaperGlass =
          isLight && LiquidGlassEffectService.configuration.enabled;
      final foregroundColor =
          useWallpaperGlass ? colorScheme.onPrimary : colorScheme.onSurface;
      final secondaryColor = useWallpaperGlass
          ? colorScheme.onPrimary.withValues(alpha: 0.7)
          : colorScheme.onSurfaceVariant;
      final todayCountStyle = TextStyle(
        fontSize: isTablet ? 16 : 14,
        fontWeight: FontWeight.bold,
        color: foregroundColor,
      );
      final bestTimeStyle = TextStyle(
        fontSize: isTablet ? 26 : 20,
        fontWeight: FontWeight.w900,
        color: useWallpaperGlass ? foregroundColor : colorScheme.primary,
      );
      final accuracyStyle = TextStyle(
        fontSize: isTablet ? 26 : 20,
        fontWeight: FontWeight.w900,
        color: foregroundColor,
      );

      return OptionalLiquidGlassCard(
        borderRadius: 24,
        tint: (isLight ? colorScheme.scrim : colorScheme.tertiary)
            .withValues(alpha: 0.16),
        isDark: useDarkGlass,
        fallbackDecoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isLight
                ? Colors.white.withValues(alpha: 0.2)
                : Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: EdgeInsets.all(isTablet ? 24 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: todayCount > 0
                                ? Colors.green.withValues(alpha: 0.12)
                                : Colors.orangeAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                              todayCount > 0
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color: todayCount > 0
                                  ? Colors.green
                                  : Colors.orangeAccent,
                              size: isTablet ? 26 : 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TweenAnimationBuilder<int>(
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          tween: IntTween(begin: 0, end: todayCount),
                          builder: (context, value, child) {
                            return Text(
                                todayCount > 0
                                    ? "今日已完成 $value 次测验"
                                    : "今日还未完成测验",
                                style: todayCountStyle);
                          },
                        )),
                        Icon(Icons.arrow_forward_ios,
                            size: isTablet ? 14 : 12, color: secondaryColor)
                      ]),
                      Divider(
                          height: isTablet ? 32 : 24,
                          color: secondaryColor.withValues(alpha: 0.28)),
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text("最佳战绩",
                                  style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: isTablet ? 13 : 12)),
                              const SizedBox(height: 4),
                              TweenAnimationBuilder<int>(
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOutCubic,
                                tween: IntTween(begin: 0, end: bestTimeVal),
                                builder: (context, value, child) {
                                  return Text(
                                      bestTimeVal > 0 ? "$value秒" : "--",
                                      style: bestTimeStyle);
                                },
                              )
                            ])),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text("总正确率",
                                  style: TextStyle(
                                      color: secondaryColor,
                                      fontSize: isTablet ? 13 : 12)),
                              const SizedBox(height: 4),
                              TweenAnimationBuilder<int>(
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOutCubic,
                                tween: IntTween(begin: 0, end: accuracyInt),
                                builder: (context, value, child) {
                                  return Text(
                                    "$value.0%",
                                    style: accuracyStyle,
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: accuracy,
                                  minHeight: 4,
                                  backgroundColor: secondaryColor.withValues(
                                    alpha: 0.18,
                                  ),
                                  color: useWallpaperGlass
                                      ? foregroundColor
                                      : colorScheme.primary,
                                ),
                              )
                            ]))
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
