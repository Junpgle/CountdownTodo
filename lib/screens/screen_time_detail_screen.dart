import 'package:flutter/material.dart';

class ScreenTimeDetailScreen extends StatelessWidget {
  final List<dynamic> stats;

  const ScreenTimeDetailScreen({super.key, required this.stats});

  String _formatDetailedTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    if (h > 0) return "$h小时 $m分钟 $s秒";
    if (m > 0) return "$m分钟 $s秒";
    return "$s秒";
  }

  IconData _getDeviceIcon(String device) {
    device = device.toLowerCase();
    if (device.contains("phone")) return Icons.smartphone;
    if (device.contains("tablet")) return Icons.tablet_android;
    if (device.contains("windows") || device.contains("pc")) return Icons.laptop_windows;
    return Icons.devices;
  }

  @override
  Widget build(BuildContext context) {
    // 按时间降序排列
    List<dynamic> sortedList = List.from(stats);
    sortedList.sort((a, b) => b['duration'].compareTo(a['duration']));

    return Scaffold(
      appBar: AppBar(
        title: const Text("屏幕使用时间详情"),
        centerTitle: true,
      ),
      body: sortedList.isEmpty
          ? const Center(child: Text("暂无数据"))
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sortedList.length,
        separatorBuilder: (ctx, i) => const Divider(),
        itemBuilder: (ctx, i) {
          final item = sortedList[i];
          final String appName = item['app_name'] ?? "未知应用";
          final String deviceName = item['device_name'] ?? "未知设备";
          final int duration = item['duration'] ?? 0;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: Icon(_getDeviceIcon(deviceName), size: 20, color: Colors.blue),
            ),
            title: Text(appName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("设备: $deviceName", style: const TextStyle(fontSize: 12)),
            trailing: Text(
              _formatDetailedTime(duration),
              style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w500),
            ),
          );
        },
      ),
    );
  }
}