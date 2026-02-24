import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: textColor)),
    );
  }
}

/// 屏幕时间卡片
class ScreenTimeCard extends StatelessWidget {
  final List<dynamic> stats;
  final bool hasPermission;
  final VoidCallback onOpenSettings;

  const ScreenTimeCard({
    super.key,
    required this.stats,
    required this.hasPermission,
    required this.onOpenSettings,
  });

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

    return Card(
      elevation: 2,
      color: Theme.of(context).cardColor.withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: stats.isEmpty
            ? const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text("暂无数据，请确保已在 Android 设置中授权", textAlign: TextAlign.center),
          ),
        )
            : Column(
          children: stats.take(3).map((app) {
            int min = app['duration'];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.app_registration, size: 18, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(app['app_name'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                    "${min ~/ 60}h ${min % 60}m",
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
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
              Row(
                children: [
                  Icon(
                    todayCount > 0 ? Icons.check_circle : Icons.error_outline,
                    color: todayCount > 0 ? Colors.green : Colors.orangeAccent,
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      todayCount > 0 ? "今日已完成 $todayCount 次测验" : "今日还未完成测验",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: todayCount > 0 ? Colors.green : Colors.orangeAccent,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("最佳战绩 (全对)",
                            style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          stats['bestTime'] != null ? "${stats['bestTime']}秒" : "--",
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("总正确率",
                            style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          "${(accuracy * 100).toStringAsFixed(1)}%",
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: accuracy, borderRadius: BorderRadius.circular(4)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}