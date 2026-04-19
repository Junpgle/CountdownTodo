import 'package:flutter/material.dart';
import 'dart:math';
import '../models.dart';

class TeamHeatmapWidget extends StatelessWidget {
  final List<TodoItem> todos;
  const TeamHeatmapWidget({super.key, required this.todos});

  Map<DateTime, int> _calcDensity() {
    final Map<DateTime, int> map = {};
    for (var t in todos) {
      if (t.isDeleted) continue;
      final dt = t.dueDate ?? DateTime.fromMillisecondsSinceEpoch(t.updatedAt);
      final day = DateTime(dt.year, dt.month, dt.day);
      map[day] = (map[day] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final density = _calcDensity();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text("全景任务热力分布 (Recent 35 Days)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5, // 5 周
            itemBuilder: (context, weekIdx) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  children: List.generate(7, (dayIdx) {
                    final date = today.subtract(Duration(days: ((4 - weekIdx) * 7 + (6 - dayIdx)).toInt()));
                    final count = density[DateTime(date.year, date.month, date.day)] ?? 0;
                    int intensity = 0;
                    if (count > 0 && count <= 2) intensity = 1;
                    else if (count > 2 && count <= 5) intensity = 2;
                    else if (count > 5 && count <= 9) intensity = 3;
                    else if (count > 9) intensity = 4;

                    return Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: _getHeatmapColor(intensity, isDark),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        _buildLegend(),
      ],
    );
  }

  Color _getHeatmapColor(int intensity, bool isDark) {
    if (intensity == 0) return isDark ? Colors.grey[900]! : Colors.grey[200]!;
    
    // 蓝色渐变系
    List<Color> levels = [
      Colors.blue[100]!,
      Colors.blue[300]!,
      Colors.blue[500]!,
      Colors.blue[800]!,
    ];
    return levels[min(intensity - 1, 3)];
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text("Less", style: TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(width: 4),
          ...List.generate(5, (i) => Container(
            width: 8, height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(color: _getHeatmapColor(i, false), borderRadius: BorderRadius.circular(1)),
          )),
          const SizedBox(width: 4),
          const Text("More", style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }
}
