import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart' hide TextDirection;
import '../../models.dart';

/// 通用的板块标题
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onAdd;
  final bool isLight;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.onAdd,
    this.isLight = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color? textColor = isLight ? Colors.white : null;
    final Color iconColor = isLight ? Colors.white70 : Theme.of(context).colorScheme.primary;

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
          if (onAdd != null) ...[
            const Spacer(),
            IconButton(
              onPressed: onAdd,
              icon: Icon(Icons.add_circle_outline, color: iconColor),
              tooltip: "添加",
            )
          ]
        ],
      ),
    );
  }
}

/// 屏幕时间统计卡片
class ScreenTimeCard extends StatelessWidget {
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

  String _formatSeconds(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m ${totalSeconds % 60}s";
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          // 响应式断点判断
          final bool isTablet = constraints.maxWidth >= 600;

          if (!hasPermission) {
            return Container(
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 24 : 16,
                    vertical: isTablet ? 8 : 4
                ),
                leading: const Icon(Icons.lock_clock, color: Colors.orange),
                title: const Text("未开启屏幕时间统计", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("点击前往开启权限以同步手机使用时长"),
                onTap: onOpenSettings,
              ),
            );
          }

          if (isLoading) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(isTablet ? 60 : 40),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      SizedBox(height: 16),
                      Text("数据同步中...", style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            );
          }

          if (stats.isEmpty) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(isTablet ? 50 : 30),
                child: const Center(child: Text("今日暂无屏幕使用数据", style: TextStyle(color: Colors.grey))),
              ),
            );
          }

          int totalTime = stats.fold(0, (sum, item) => sum + (item['duration'] as int));

          Map<String, int> deviceMap = {};
          for (var item in stats) {
            String d = item['device_name'] ?? "未知设备";
            if (d.contains("Phone")) d = "手机";
            else if (d.contains("Tablet")) d = "平板";
            else if (d.contains("Windows") || d.contains("PC") || d.contains("LAPT")) d = "电脑";
            deviceMap[d] = (deviceMap[d] ?? 0) + (item['duration'] as int);
          }

          Map<String, int> aggregatedApps = {};
          for (var item in stats) {
            String appName = item['app_name'] ?? "未知应用";
            aggregatedApps[appName] = (aggregatedApps[appName] ?? 0) + (item['duration'] as int);
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
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onViewDetail,
                borderRadius: BorderRadius.circular(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000), // 防止超大屏幕极度拉伸
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 20,
                          vertical: isTablet ? 32 : 24
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("今日总计", style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: isTablet ? 16 : 14, fontWeight: FontWeight.w600)),
                                  if (lastSyncTime != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                          "更新: ${DateFormat('HH:mm').format(lastSyncTime!)}",
                                          style: TextStyle(fontSize: isTablet ? 12 : 11, color: Colors.blueGrey)
                                      ),
                                    ),
                                ],
                              ),
                              Text(_formatSeconds(totalTime),
                                  style: TextStyle(fontSize: isTablet ? 34 : 26, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                            ],
                          ),
                          SizedBox(height: isTablet ? 24 : 16),
                          Divider(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                          SizedBox(height: isTablet ? 24 : 16),

                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity, // <--- 修复点：强制撑满横向空间
                                      height: isTablet ? 240 : 140, // 平板上分配更大的高度给图表
                                      child: CustomPaint(
                                        painter: PieChartPainter(data: deviceMap, total: totalTime),
                                      ),
                                    ),
                                    SizedBox(height: isTablet ? 20 : 12),
                                    Text("设备分布", style: TextStyle(fontSize: isTablet ? 15 : 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity, // <--- 修复点：强制撑满横向空间
                                      height: isTablet ? 240 : 140,
                                      child: CustomPaint(
                                        painter: PieChartPainter(
                                          data: appMap,
                                          total: totalTime,
                                          isAppChart: true,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: isTablet ? 20 : 12),
                                    Text("Top 应用", style: TextStyle(fontSize: isTablet ? 15 : 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isTablet ? 32 : 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app, size: isTablet ? 18 : 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 6),
                                Text("点击查看详细列表", style: TextStyle(fontSize: isTablet ? 14 : 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
    );
  }
}

/// 增强版饼状图绘图器 (支持响应式缩放)
class PieChartPainter extends CustomPainter {
  final Map<String, int> data;
  final int total;
  final bool isAppChart;

  PieChartPainter({required this.data, required this.total, this.isAppChart = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    // 动态计算厚度与半径：确保在大屏/小屏下都能保持协调的粗细比例，且不会溢出 Canvas
    final double minDimension = math.min(size.width, size.height);
    final double dynamicStrokeWidth = minDimension * 0.28; // 动态厚度
    // 预留约 25 的边距给文字，防止文字被裁切
    double radius = (minDimension - dynamicStrokeWidth) / 2 - 25;

    // 保底机制：防止极度异常尺寸下负数崩溃
    if (radius <= 0) radius = 10;

    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;

    final List<Color> colors = isAppChart
        ? [Colors.blue.shade400, Colors.green.shade400, Colors.orange.shade400, Colors.purple.shade300, Colors.cyan.shade300]
        : [Colors.indigo.shade400, Colors.teal.shade400, Colors.amber.shade600, Colors.redAccent.shade200];

    int i = 0;
    data.forEach((label, value) {
      final sweepAngle = (value / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dynamicStrokeWidth
        ..strokeCap = StrokeCap.round
        ..color = colors[i % colors.length];

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

      final middleAngle = startAngle + sweepAngle / 2;

      // 占比超过 2% 就尝试显示文字
      if (sweepAngle > (math.pi * 3 * 0.02)) {
        // 根据动态半径计算文字位置，贴在圆环外侧
        final textRadius = radius + (dynamicStrokeWidth / 2) + 12;
        final x = center.dx + textRadius * math.cos(middleAngle);
        final y = center.dy + textRadius * math.sin(middleAngle);

        String displayLabel = label;
        if (displayLabel.length > 6) displayLabel = "${displayLabel.substring(0, 5)}..";

        // 大尺寸图表使用稍微大一点的字体
        double fontSize = minDimension > 200 ? 12 : 10;

        final textPainter = TextPainter(
          text: TextSpan(
            text: displayLabel,
            style: TextStyle(
                color: colors[i % colors.length].withOpacity(1.0),
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                shadows: const [
                  Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black26) // 增强了阴影可读性
                ]
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final textOffset = Offset(x - textPainter.width / 2, y - textPainter.height / 2);
        textPainter.paint(canvas, textOffset);
      }

      startAngle += sweepAngle;
      i++;
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 通用的空状态显示（美化版）
class EmptyState extends StatelessWidget {
  final String text;
  final bool isLight;
  const EmptyState({super.key, required this.text, this.isLight = false});
  @override
  Widget build(BuildContext context) {
    Color bgColor = isLight ? Colors.white.withOpacity(0.1) : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3);
    Color textColor = isLight ? Colors.white70 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLight ? Colors.white30 : Theme.of(context).dividerColor.withOpacity(0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 36, color: textColor.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: 14)),
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

    return LayoutBuilder(
        builder: (context, constraints) {
          final bool isTablet = constraints.maxWidth >= 600;

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000), // 大屏防过度拉伸
                    child: Padding(
                      padding: EdgeInsets.all(isTablet ? 32 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: todayCount > 0 ? Colors.green.withOpacity(0.15) : Colors.orangeAccent.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(todayCount > 0 ? Icons.check_circle : Icons.error_outline,
                                      color: todayCount > 0 ? Colors.green : Colors.orangeAccent,
                                      size: isTablet ? 32 : 26),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Text(todayCount > 0 ? "今日已完成 $todayCount 次测验" : "今日还未完成测验",
                                        style: TextStyle(fontSize: isTablet ? 20 : 16, fontWeight: FontWeight.bold))
                                ),
                                Icon(Icons.arrow_forward_ios, size: isTablet ? 18 : 14, color: Colors.grey)
                              ]
                          ),
                          Divider(height: isTablet ? 40 : 32, color: Theme.of(context).dividerColor.withOpacity(0.5)),
                          Row(
                              children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("最佳战绩", style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: isTablet ? 14 : 13)),
                                          const SizedBox(height: 8),
                                          Text(stats['bestTime'] != null ? "${stats['bestTime']}秒" : "--",
                                              style: TextStyle(fontSize: isTablet ? 32 : 26, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary))
                                        ]
                                    )
                                ),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text("总正确率", style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: isTablet ? 14 : 13)),
                                          const SizedBox(height: 8),
                                          Text("${(accuracy * 100).toStringAsFixed(1)}%",
                                              style: TextStyle(fontSize: isTablet ? 32 : 26, fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: LinearProgressIndicator(
                                              value: accuracy,
                                              minHeight: 6,
                                              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          )
                                        ]
                                    )
                                )
                              ]
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
    );
  }
}