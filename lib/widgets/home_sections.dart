import 'package:flutter/material.dart';
import 'dart:math' as math;
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
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

/// 屏幕时间统计卡片 - 优化了饼图尺寸和标记位置
class ScreenTimeCard extends StatelessWidget {
  final List<dynamic> stats;
  final bool hasPermission;
  final VoidCallback onOpenSettings;
  final VoidCallback onViewDetail;

  const ScreenTimeCard({
    super.key,
    required this.stats,
    required this.hasPermission,
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
    if (!hasPermission) {
      return Card(
        color: Colors.amber.withOpacity(0.1),
        margin: const EdgeInsets.only(bottom: 24),
        child: ListTile(
          leading: const Icon(Icons.lock_clock, color: Colors.orange),
          title: const Text("未开启屏幕时间统计"),
          subtitle: const Text("点击前往开启权限以同步手机使用时长"),
          onTap: onOpenSettings,
        ),
      );
    }

    if (stats.isEmpty) {
      return Card(
        elevation: 2,
        color: Theme.of(context).cardColor.withOpacity(0.95),
        child: const Padding(
          padding: EdgeInsets.all(30),
          child: Center(child: Text("暂无今日统计数据", style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    // 1. 计算总时长
    int totalTime = stats.fold(0, (sum, item) => sum + (item['duration'] as int));

    // 2. 聚合设备占比
    Map<String, int> deviceMap = {};
    for (var item in stats) {
      String d = item['device_name'] ?? "未知设备";
      if (d.contains("Phone")) d = "手机";
      else if (d.contains("Tablet")) d = "平板";
      else if (d.contains("Windows") || d.contains("PC") || d.contains("LAPT")) d = "电脑";
      deviceMap[d] = (deviceMap[d] ?? 0) + (item['duration'] as int);
    }

    // 3. 聚合应用占比 (取Top 3)
    List<dynamic> sortedApps = List.from(stats);
    sortedApps.sort((a, b) => b['duration'].compareTo(a['duration']));

    Map<String, int> appMap = {};
    int topSum = 0;
    for (var i = 0; i < math.min(3, sortedApps.length); i++) {
      appMap[sortedApps[i]['app_name']] = sortedApps[i]['duration'];
      topSum += sortedApps[i]['duration'] as int;
    }
    if (totalTime > topSum) {
      appMap["其他"] = totalTime - topSum;
    }

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor.withOpacity(0.95),
      child: InkWell(
        onTap: onViewDetail,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("今日总计", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                  Text(_formatSeconds(totalTime),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
              const SizedBox(height: 15),
              const Divider(),
              const SizedBox(height: 15),

              Row(
                children: [
                  // 图1: 设备分布 (高度增加)
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 140, // 增大绘图区域
                          child: CustomPaint(
                            painter: PieChartPainter(data: deviceMap, total: totalTime),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text("设备分布", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                  // 图2: App占比 (高度增加)
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 140, // 增大绘图区域
                          child: CustomPaint(
                            painter: PieChartPainter(
                              data: appMap,
                              total: totalTime,
                              isAppChart: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text("Top 应用", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app, size: 14, color: Colors.blue.withOpacity(0.6)),
                  const SizedBox(width: 4),
                  const Text("点击查看详细列表", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 增强版饼状图绘图器：优化了比例、文字距离和圆环厚度
class PieChartPainter extends CustomPainter {
  final Map<String, int> data;
  final int total;
  final bool isAppChart;

  PieChartPainter({required this.data, required this.total, this.isAppChart = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    // 调大半径比例，充分利用空间
    final radius = math.min(size.width, size.height) / 2.6;
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
        ..strokeWidth = 80 // 增加厚度，看起来更现代协调
        ..strokeCap = StrokeCap.round
        ..color = colors[i % colors.length];

      // 1. 绘制圆环扇区
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

      // 2. 绘制标注文字
      final middleAngle = startAngle + sweepAngle / 2;

      // 占比超过 2% 就尝试显示文字 (之前是 3%)
      if (sweepAngle > (math.pi * 3 * 0.02)) {
        // 适当减小文字偏移距离，让标签贴近大圆环
        final textRadius = radius + 60;
        final x = center.dx + textRadius * math.cos(middleAngle);
        final y = center.dy + textRadius * math.sin(middleAngle);

        String displayLabel = label;
        if (displayLabel.length > 6) displayLabel = "${displayLabel.substring(0, 5)}..";

        final textPainter = TextPainter(
          text: TextSpan(
            text: displayLabel,
            style: TextStyle(
                color: colors[i % colors.length].withOpacity(1.0),
                fontSize: 10, // 稍微调大字号
                fontWeight: FontWeight.bold,
                shadows: const [
                  Shadow(offset: Offset(0, 1), blurRadius: 1, color: Colors.black12)
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

/// 通用的空状态显示
class EmptyState extends StatelessWidget {
  final String text;
  final bool isLight;
  const EmptyState({super.key, required this.text, this.isLight = false});
  @override
  Widget build(BuildContext context) {
    Color borderColor = isLight ? Colors.white30 : Colors.grey.withOpacity(0.3);
    Color textColor = isLight ? Colors.white70 : Colors.grey;
    return Container(
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: textColor)),
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
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).cardColor.withOpacity(0.95),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(todayCount > 0 ? Icons.check_circle : Icons.error_outline, color: todayCount > 0 ? Colors.green : Colors.orangeAccent, size: 30), const SizedBox(width: 12), Expanded(child: Text(todayCount > 0 ? "今日已完成 $todayCount 次测验" : "今日还未完成测验", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey)]),
              const Divider(height: 30),
              Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("最佳战绩", style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 4), Text(stats['bestTime'] != null ? "${stats['bestTime']}秒" : "--", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("总正确率", style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 4), Text("${(accuracy * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 4), LinearProgressIndicator(value: accuracy, borderRadius: BorderRadius.circular(4))]))]),
            ],
          ),
        ),
      ),
    );
  }
}