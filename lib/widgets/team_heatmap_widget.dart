import 'package:flutter/material.dart';
import 'dart:math';

class TeamHeatmapWidget extends StatelessWidget {
  const TeamHeatmapWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text("团队协作热力分布 (30 Days)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        const SizedBox(height: 12),
        Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, // 一周 7 天
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: 30, // 最近 30 天
            itemBuilder: (context, index) {
              // 模拟热力数据深度 (0-4)
              int intensity = Random().nextInt(5); 
              return Container(
                decoration: BoxDecoration(
                  color: _getHeatmapColor(intensity, isDark),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
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
