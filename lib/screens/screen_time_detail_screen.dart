import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection; // 修复：隐藏 intl 自带的 TextDirection，使用 Flutter 原生的
import 'dart:math' as math;
import '../storage_service.dart';

// 定义数据过滤范围
enum DeviceFilter { all, pc, mobile, phone, tablet }

extension DeviceFilterExtension on DeviceFilter {
  String get label {
    switch (this) {
      case DeviceFilter.all: return "聚合数据";
      case DeviceFilter.pc: return "电脑端";
      case DeviceFilter.mobile: return "移动端";
      case DeviceFilter.phone: return "手机";
      case DeviceFilter.tablet: return "平板";
    }
  }
}

class ScreenTimeDetailScreen extends StatefulWidget {
  final List<dynamic> todayStats; // 今日精确数据

  const ScreenTimeDetailScreen({super.key, required this.todayStats});

  @override
  State<ScreenTimeDetailScreen> createState() => _ScreenTimeDetailScreenState();
}

class _ScreenTimeDetailScreenState extends State<ScreenTimeDetailScreen> {
  DeviceFilter _currentFilter = DeviceFilter.all;
  Map<String, List<dynamic>> _historyStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.getScreenTimeHistory();
    // 确保今日历史被今日的精确数据覆盖
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    history[todayStr] = widget.todayStats;

    if (mounted) {
      setState(() {
        _historyStats = history;
        _isLoading = false;
      });
    }
  }

  // --- 核心过滤方法 ---
  bool _matchesFilter(String deviceName, DeviceFilter filter) {
    deviceName = deviceName.toLowerCase();
    switch (filter) {
      case DeviceFilter.all: return true;
      case DeviceFilter.pc: return deviceName.contains("windows") || deviceName.contains("pc") || deviceName.contains("lapt");
      case DeviceFilter.mobile: return deviceName.contains("phone") || deviceName.contains("tablet");
      case DeviceFilter.phone: return deviceName.contains("phone");
      case DeviceFilter.tablet: return deviceName.contains("tablet");
    }
  }

  List<dynamic> _getFilteredStats(List<dynamic> rawStats, DeviceFilter filter) {
    return rawStats.where((item) {
      String dName = item['device_name'] ?? "";
      return _matchesFilter(dName, filter);
    }).toList();
  }

  int _getTotalDuration(List<dynamic> rawStats, DeviceFilter filter) {
    final filtered = _getFilteredStats(rawStats, filter);
    return filtered.fold(0, (sum, item) => sum + (item['duration'] as int));
  }

  String _formatHM(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h ${m}m";
    return "${m}m";
  }

  // 按 App 聚合当前列表的数据
  List<MapEntry<String, Map<String, dynamic>>> _getGroupedApps(List<dynamic> filteredStats) {
    Map<String, Map<String, dynamic>> grouped = {};
    for (var item in filteredStats) {
      String appName = item['app_name'] ?? "未知应用";
      int duration = item['duration'] ?? 0;
      if (!grouped.containsKey(appName)) {
        grouped[appName] = {'total': 0};
      }
      grouped[appName]!['total'] = (grouped[appName]!['total'] as int) + duration;
    }
    var sorted = grouped.entries.toList();
    sorted.sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("详细数据")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    DateTime now = DateTime.now();
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    String yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    int todayTotal = _getTotalDuration(_historyStats[todayStr] ?? [], _currentFilter);
    int yesterdayTotal = _getTotalDuration(_historyStats[yesterdayStr] ?? [], _currentFilter);
    int diff = todayTotal - yesterdayTotal;

    // 获取聚合后的今日应用排行
    final filteredTodayStats = _getFilteredStats(_historyStats[todayStr] ?? [], _currentFilter);
    final topApps = _getGroupedApps(filteredTodayStats);

    return Scaffold(
      appBar: AppBar(
        title: const Text("屏幕使用时间", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: CustomScrollView(
        slivers: [
          // 1. 过滤选项卡
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: DeviceFilter.values.map((filter) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: _currentFilter == filter,
                      onSelected: (selected) {
                        if (selected) setState(() => _currentFilter = filter);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 2. 今日总览卡片
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("今日屏幕使用时长", style: TextStyle(fontSize: 14, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        _formatHM(todayTotal),
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(diff >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 16, color: diff >= 0 ? Colors.orange : Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            "较昨日${diff >= 0 ? '增加' : '减少'} ${_formatHM(diff.abs())}",
                            style: TextStyle(fontSize: 12, color: diff >= 0 ? Colors.orange : Colors.green, fontWeight: FontWeight.w600),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. 近七日条形图
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("近七日使用情况", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: _buildBarChart(now),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 4. 今日 Top 4 宫格
          if (topApps.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text("今日最常使用", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 2.2, // 控制方块的高宽比
                      ),
                      itemCount: math.min(4, topApps.length),
                      itemBuilder: (ctx, i) {
                        final app = topApps[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                child: Text(
                                  app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(app.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(_formatHM(app.value['total'] as int), style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                  ],
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

          // 5. 详细列表标题
          if (topApps.length > 4)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text("其余应用明细", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),

          // 6. 其余应用列表
          if (topApps.length > 4)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                  final app = topApps[i + 4]; // 从第 5 个开始
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey.shade200,
                      child: Text(
                        app.key.isNotEmpty ? app.key[0].toUpperCase() : "?",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(app.key, style: const TextStyle(fontSize: 14)),
                    trailing: Text(_formatHM(app.value['total'] as int), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  );
                },
                childCount: topApps.length - 4,
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }

  Widget _buildBarChart(DateTime now) {
    List<int> dailyTotals = [];
    List<String> labels = [];

    // 收集过去 7 天的数据
    for (int i = 6; i >= 0; i--) {
      DateTime d = now.subtract(Duration(days: i));
      String dateStr = DateFormat('yyyy-MM-dd').format(d);
      String labelStr = i == 0 ? "今日" : DateFormat('MM/dd').format(d);

      int total = _getTotalDuration(_historyStats[dateStr] ?? [], _currentFilter);
      dailyTotals.add(total);
      labels.add(labelStr);
    }

    return CustomPaint(
      painter: BarChartPainter(
        data: dailyTotals,
        labels: labels,
        primaryColor: Theme.of(context).colorScheme.primary,
        textColor: Colors.blueGrey,
      ),
    );
  }
}

// --- 纯手工绘制：带高亮与平均线的柱状图 ---
class BarChartPainter extends CustomPainter {
  final List<int> data;
  final List<String> labels;
  final Color primaryColor;
  final Color textColor;

  BarChartPainter({required this.data, required this.labels, required this.primaryColor, required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double bottomPadding = 30.0;
    final double topPadding = 20.0;
    final double chartHeight = size.height - bottomPadding - topPadding;

    int maxVal = data.reduce(math.max);
    if (maxVal == 0) maxVal = 1; // 防除0

    double avgVal = data.reduce((a, b) => a + b) / data.length;

    final double barWidth = (size.width / data.length) * 0.4;
    final double spacing = size.width / data.length;

    final Paint barPaint = Paint()..style = PaintingStyle.fill;

    // 1. 画每根柱子和底部标签
    for (int i = 0; i < data.length; i++) {
      double xCenter = (i * spacing) + (spacing / 2);
      double barH = (data[i] / maxVal) * chartHeight;

      // 区分今日颜色
      barPaint.color = (i == data.length - 1) ? primaryColor : primaryColor.withOpacity(0.3);

      // 绘制圆角柱体
      Rect barRect = Rect.fromLTWH(xCenter - barWidth / 2, size.height - bottomPadding - barH, barWidth, barH);
      RRect rRect = RRect.fromRectAndRadius(barRect, const Radius.circular(4));
      canvas.drawRRect(rRect, barPaint);

      // 如果是最高值，在柱体上方画一个小皇冠/标记值
      if (data[i] == maxVal && maxVal > 1) {
        String hm = _formatHM(data[i]);
        _drawText(canvas, hm, Offset(xCenter, size.height - bottomPadding - barH - 15), fontSize: 10, color: primaryColor, bold: true);
      }

      // 绘制底部日期标签
      _drawText(canvas, labels[i], Offset(xCenter, size.height - 15), fontSize: 11, color: textColor);
    }

    // 2. 绘制平均水平虚线
    if (avgVal > 0) {
      double avgY = size.height - bottomPadding - ((avgVal / maxVal) * chartHeight);
      final Paint dashPaint = Paint()
        ..color = Colors.orangeAccent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, Offset(0, avgY), Offset(size.width, avgY), dashPaint);

      // 平均线说明文字
      _drawText(canvas, "平均: ${_formatHM(avgVal.toInt())}", Offset(size.width - 20, avgY - 10), fontSize: 10, color: Colors.orange.shade800);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, {double fontSize = 12, Color color = Colors.black, bool bold = false}) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 5;
    const double dashSpace = 5;
    double distance = (p2 - p1).distance;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;

    double startX = p1.dx;
    double startY = p1.dy;

    while (distance >= 0) {
      double drawLen = math.min(dashWidth, distance);
      canvas.drawLine(Offset(startX, startY), Offset(startX + dx * drawLen, startY + dy * drawLen), paint);
      startX += dx * (dashWidth + dashSpace);
      startY += dy * (dashWidth + dashSpace);
      distance -= (dashWidth + dashSpace);
    }
  }

  String _formatHM(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return "${h}h${m}m";
    return "${m}m";
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}