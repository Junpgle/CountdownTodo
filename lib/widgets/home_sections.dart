import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart' hide TextDirection;

/// 通用的板块标题
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onAdd;
  final VoidCallback? onAction; // 📁 新增操作回调
  final IconData? actionIcon; // 📁 新增操作图标
  final String? actionTooltip; // 📁 新增操作提示
  final bool isLight;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.onAdd,
    this.onAction,
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
              color: iconColor.withOpacity(0.15),
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
          if (onAction != null && actionIcon != null)
            IconButton(
              onPressed: onAction,
              icon: Icon(actionIcon, color: iconColor),
              tooltip: actionTooltip ?? "操作",
            ),
          if (onAdd != null)
            IconButton(
              onPressed: onAdd,
              icon: Icon(Icons.add_circle_outline, color: iconColor),
              tooltip: "添加",
            )
        ],
      ),
    );
  }
}

/// 骨架屏 Shimmer 占位符
class _ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerPlaceholder({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final baseColor =
        brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[200]!;
    final highlightColor =
        brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width == double.infinity ? null : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value, 0),
              end: Alignment(_animation.value + 0.5, 0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// 屏幕时间统计卡片
class ScreenTimeCard extends StatefulWidget {
  final List<dynamic> stats;
  final bool hasPermission;
  final bool isLoading;
  final DateTime? lastSyncTime;
  final VoidCallback onOpenSettings;
  final VoidCallback onViewDetail;

  const ScreenTimeCard({
    super.key,
    required this.stats,
    required this.hasPermission,
    this.isLoading = false,
    this.lastSyncTime,
    required this.onOpenSettings,
    required this.onViewDetail,
  });

  @override
  State<ScreenTimeCard> createState() => _ScreenTimeCardState();
}

class _ScreenTimeCardState extends State<ScreenTimeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pieCtrl;
  late Animation<double> _pieAnim;

  @override
  void initState() {
    super.initState();
    _pieCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pieAnim = CurvedAnimation(parent: _pieCtrl, curve: Curves.easeInOutCubic);
    _pieCtrl.forward();
  }

  @override
  void didUpdateWidget(ScreenTimeCard old) {
    super.didUpdateWidget(old);
    if (old.stats != widget.stats || old.isLoading != widget.isLoading) {
      _pieCtrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _pieCtrl.dispose();
    super.dispose();
  }

  String _formatSeconds(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m ${totalSeconds % 60}s";
  }

  Widget _buildShimmerLoading(bool isTablet) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
              width: 120,
              height: 18,
              borderRadius: 6,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ShimmerPlaceholder(
                    width: double.infinity,
                    height: 60,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShimmerPlaceholder(
                    width: double.infinity,
                    height: 60,
                    borderRadius: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ShimmerPlaceholder(
              width: double.infinity,
              height: 14,
              borderRadius: 6,
            ),
            const SizedBox(height: 10),
            _ShimmerPlaceholder(
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

      if (!widget.hasPermission) {
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
                horizontal: isTablet ? 24 : 16, vertical: isTablet ? 8 : 4),
            leading: const Icon(Icons.lock_clock, color: Colors.orange),
            title: const Text("未开启屏幕时间统计",
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text("点击前往开启权限以同步手机使用时长"),
            onTap: widget.onOpenSettings,
          ),
        );
      }

      if (widget.isLoading) {
        return _buildShimmerLoading(isTablet);
      }

      if (widget.stats.isEmpty) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isTablet ? 50 : 30),
            child: const Center(
                child:
                    Text("今日暂无屏幕使用数据", style: TextStyle(color: Colors.grey))),
          ),
        );
      }

      int totalTime =
          widget.stats.fold(0, (sum, item) => sum + (item['duration'] as int));

      Map<String, int> deviceMap = {};
      for (var item in widget.stats) {
        String d = item['device_name'] ?? "未知设备";
        if (d.contains("Phone")) {
          d = "手机";
        } else if (d.contains("Tablet"))
          d = "平板";
        else if (d.contains("Windows") ||
            d.contains("PC") ||
            d.contains("LAPT")) d = "电脑";
        deviceMap[d] = (deviceMap[d] ?? 0) + (item['duration'] as int);
      }

      Map<String, int> aggregatedApps = {};
      for (var item in widget.stats) {
        String appName = item['app_name'] ?? "未知应用";
        aggregatedApps[appName] =
            (aggregatedApps[appName] ?? 0) + (item['duration'] as int);
      }

      List<MapEntry<String, int>> sortedApps = aggregatedApps.entries.toList();
      sortedApps.sort((a, b) => b.value.compareTo(a.value));

      Map<String, int> appMap = {};
      int topSum = 0;
      for (var i = 0; i < math.min(3, sortedApps.length); i++) {
        appMap[sortedApps[i].key] = sortedApps[i].value;
        topSum += sortedApps[i].value;
      }
      if (totalTime > topSum) {
        appMap["其他"] = totalTime - topSum;
      }

      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onViewDetail,
            borderRadius: BorderRadius.circular(20),
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
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                      fontSize: isTablet ? 15 : 13,
                                      fontWeight: FontWeight.w600)),
                              if (widget.lastSyncTime != null)
                                Text(
                                    "更新: ${DateFormat('HH:mm').format(widget.lastSyncTime!)}",
                                    style: TextStyle(
                                        fontSize: isTablet ? 11 : 10,
                                        color: Colors.blueGrey.withOpacity(0.7))),
                            ],
                          ),
                          Text(_formatSeconds(totalTime),
                              style: TextStyle(
                                  fontSize: isTablet ? 28 : 22,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: isTablet ? 160 : 100,
                                  child: AnimatedBuilder(
                                    animation: _pieAnim,
                                    builder: (context, child) {
                                      return CustomPaint(
                                        painter: PieChartPainter(
                                          data: deviceMap,
                                          total: totalTime,
                                          sweepProgress: _pieAnim.value,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text("设备分布",
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: isTablet ? 160 : 100,
                                  child: AnimatedBuilder(
                                    animation: _pieAnim,
                                    builder: (context, child) {
                                      return CustomPaint(
                                        painter: PieChartPainter(
                                          data: appMap,
                                          total: totalTime,
                                          isAppChart: true,
                                          sweepProgress: _pieAnim.value,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text("Top 应用",
                                    style: TextStyle(
                                        fontSize: isTablet ? 13 : 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface)),
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

  PieChartPainter({
    required this.data,
    required this.total,
    this.isAppChart = false,
    this.sweepProgress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    final double minDimension = math.min(size.width, size.height);
    final double dynamicStrokeWidth = minDimension * 0.28;
    double radius = (minDimension - dynamicStrokeWidth) / 2 - 25;

    if (radius <= 0) radius = 10;

    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;

    final List<Color> colors = isAppChart
        ? [
            Colors.blue.shade400,
            Colors.green.shade400,
            Colors.orange.shade400,
            Colors.purple.shade300,
            Colors.cyan.shade300
          ]
        : [
            Colors.indigo.shade400,
            Colors.teal.shade400,
            Colors.amber.shade600,
            Colors.redAccent.shade200
          ];

    int i = 0;
    data.forEach((label, value) {
      final fullSweepAngle = (value / total) * 2 * math.pi;
      final sweepAngle = fullSweepAngle * sweepProgress;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dynamicStrokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colors[i % colors.length];

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

      if (sweepProgress > 0.5) {
        final middleAngle = startAngle + sweepAngle / 2;

        if (sweepAngle > (math.pi * 3 * 0.02)) {
          final textRadius = radius + (dynamicStrokeWidth / 2) + 12;
          final x = center.dx + textRadius * math.cos(middleAngle);
          final y = center.dy + textRadius * math.sin(middleAngle);

          String displayLabel = label;
          if (displayLabel.length > 6) {
            displayLabel = "${displayLabel.substring(0, 5)}..";
          }

          double fontSize = minDimension > 200 ? 12 : 10;

          final textPainter = TextPainter(
            text: TextSpan(
              text: displayLabel,
              style: TextStyle(
                  color: colors[i % colors.length].withOpacity(1.0),
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(
                        offset: Offset(0, 1),
                        blurRadius: 2,
                        color: Colors.black26)
                  ]),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final textOffset =
              Offset(x - textPainter.width / 2, y - textPainter.height / 2);
          textPainter.paint(canvas, textOffset);
        }
      }

      startAngle += fullSweepAngle;
      i++;
    });
  }

  @override
  bool shouldRepaint(covariant PieChartPainter old) =>
      old.data != data ||
      old.total != total ||
      old.sweepProgress != sweepProgress;
}

/// 通用的空状态显示（美化版）
class EmptyState extends StatelessWidget {
  final String text;
  final bool isLight;
  const EmptyState({super.key, required this.text, this.isLight = false});
  @override
  Widget build(BuildContext context) {
    Color bgColor = isLight
        ? Colors.white.withOpacity(0.1)
        : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3);
    Color textColor = isLight ? Colors.white70 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLight
              ? Colors.white30
              : Theme.of(context).dividerColor.withOpacity(0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded,
              size: 36, color: textColor.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }
}

/// 数学统计卡片
class MathStatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback onTap;
  const MathStatsCard({super.key, required this.stats, required this.onTap});

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

      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                                ? Colors.green.withOpacity(0.12)
                                : Colors.orangeAccent.withOpacity(0.12),
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
                                style: TextStyle(
                                    fontSize: isTablet ? 16 : 14,
                                    fontWeight: FontWeight.bold));
                          },
                        )),
                        Icon(Icons.arrow_forward_ios,
                            size: isTablet ? 14 : 12, color: Colors.grey)
                      ]),
                      Divider(
                          height: isTablet ? 32 : 24,
                          color:
                              Theme.of(context).dividerColor.withOpacity(0.4)),
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text("最佳战绩",
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                      fontSize: isTablet ? 13 : 12)),
                              const SizedBox(height: 4),
                              TweenAnimationBuilder<int>(
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOutCubic,
                                tween: IntTween(begin: 0, end: bestTimeVal),
                                builder: (context, value, child) {
                                  return Text(
                                      bestTimeVal > 0 ? "$value秒" : "--",
                                      style: TextStyle(
                                          fontSize: isTablet ? 26 : 20,
                                          fontWeight: FontWeight.w900,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary));
                                },
                              )
                            ])),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text("总正确率",
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                      fontSize: isTablet ? 13 : 12)),
                              const SizedBox(height: 4),
                              TweenAnimationBuilder<int>(
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.easeOutCubic,
                                tween: IntTween(begin: 0, end: accuracyInt),
                                builder: (context, value, child) {
                                  return Text("$value.0%",
                                      style: TextStyle(
                                          fontSize: isTablet ? 26 : 20,
                                          fontWeight: FontWeight.w900));
                                },
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: accuracy,
                                  minHeight: 4,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.1),
                                  color: Theme.of(context).colorScheme.primary,
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
