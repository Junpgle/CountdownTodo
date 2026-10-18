import 'package:flutter/material.dart';
import 'dart:math';
import '../models.dart';

const _teamHeatmapColorLevels = <Color>[
  Color(0xFFBBDEFB),
  Color(0xFF64B5F6),
  Color(0xFF2196F3),
  Color(0xFF1565C0),
];

class TeamHeatmapWidget extends StatefulWidget {
  final List<TodoItem> todos;
  final int viewDays;
  const TeamHeatmapWidget({super.key, required this.todos, this.viewDays = 35});

  @override
  State<TeamHeatmapWidget> createState() => _TeamHeatmapWidgetState();
}

class _TeamHeatmapWidgetState extends State<TeamHeatmapWidget> {
  List<TodoItem>? _densitySource;
  Map<int, int> _densityCache = const {};

  int _dateKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  Map<int, int> _calcDensity(List<TodoItem> todos) {
    final Map<int, int> map = {};
    for (var t in todos) {
      if (t.isDeleted) continue;
      final dt = t.dueDate ?? DateTime.fromMillisecondsSinceEpoch(t.updatedAt);
      final day = _dateKey(dt);
      map[day] = (map[day] ?? 0) + 1;
    }
    return map;
  }

  Map<int, int> _densityFor(List<TodoItem> todos) {
    if (identical(_densitySource, todos)) return _densityCache;
    final density = _calcDensity(todos);
    _densitySource = todos;
    _densityCache = density;
    return density;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final density = _densityFor(widget.todos);
    final viewDays = widget.viewDays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weeks = (viewDays / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
              "全景任务热力分布 (${viewDays >= 30 ? '月视图' : viewDays >= 14 ? '双周' : '周视图'})",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: weeks, // 动态周数
            itemBuilder: (context, weekIdx) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  children: List.generate(7, (dayIdx) {
                    final date = today.subtract(Duration(
                        days: ((weeks - 1 - weekIdx) * 7 + (6 - dayIdx))
                            .toInt()));
                    final count = density[_dateKey(date)] ?? 0;
                    int intensity = 0;
                    if (count > 0 && count <= 2) {
                      intensity = 1;
                    } else if (count > 2 && count <= 5) {
                      intensity = 2;
                    } else if (count > 5 && count <= 9) {
                      intensity = 3;
                    } else if (count > 9) {
                      intensity = 4;
                    }

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
        _buildLegend(isDark),
      ],
    );
  }

  Color _getHeatmapColor(int intensity, bool isDark) {
    if (intensity == 0) return isDark ? Colors.grey[900]! : Colors.grey[200]!;

    return _teamHeatmapColorLevels[min(intensity - 1, 3)];
  }

  Widget _buildLegend(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text("Less",
              style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(width: 4),
          ...List.generate(
              5,
              (i) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                        color: _getHeatmapColor(i, isDark),
                        borderRadius: BorderRadius.circular(1)),
                  )),
          const SizedBox(width: 4),
          Text("More",
              style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.white38 : Colors.black38)),
        ],
      ),
    );
  }
}
