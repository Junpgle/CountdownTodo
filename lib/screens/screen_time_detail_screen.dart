import 'package:flutter/material.dart';

class ScreenTimeDetailScreen extends StatelessWidget {
  final List<dynamic> stats;

  const ScreenTimeDetailScreen({super.key, required this.stats});

  String _formatDetailedTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    if (h > 0) return "${h}h ${m}m";
    if (m > 0) return "${m}m ${s}s";
    return "${s}s";
  }

  String _simplifyDeviceName(String device) {
    device = device.toLowerCase();
    if (device.contains("phone")) return "手机";
    if (device.contains("tablet")) return "平板";
    if (device.contains("windows") || device.contains("pc") || device.contains("lapt")) return "电脑";
    return "其他设备";
  }

  IconData _getDeviceIcon(String device) {
    device = device.toLowerCase();
    if (device.contains("phone")) return Icons.smartphone;
    if (device.contains("tablet")) return Icons.tablet_android;
    if (device.contains("windows") || device.contains("pc") || device.contains("lapt")) return Icons.laptop_windows;
    return Icons.devices;
  }

  @override
  Widget build(BuildContext context) {
    // 1. 数据聚合：合并同一个 App 在不同设备上的时间
    // 结构: Map<"抖音", {"total": 3600, "devices": {"Android-Phone": 2000, "Android-Tablet": 1600}}>
    Map<String, Map<String, dynamic>> groupedStats = {};

    for (var item in stats) {
      String appName = item['app_name'] ?? "未知应用";
      String deviceName = item['device_name'] ?? "未知设备";
      int duration = item['duration'] ?? 0;

      if (!groupedStats.containsKey(appName)) {
        groupedStats[appName] = {
          'total': 0,
          'devices': <String, int>{},
        };
      }

      groupedStats[appName]!['total'] = (groupedStats[appName]!['total'] as int) + duration;

      Map<String, int> deviceMap = groupedStats[appName]!['devices'];
      deviceMap[deviceName] = (deviceMap[deviceName] ?? 0) + duration;
    }

    // 2. 将字典转为列表并按总时长降序排序
    List<MapEntry<String, Map<String, dynamic>>> sortedList = groupedStats.entries.toList();
    sortedList.sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));

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
        separatorBuilder: (ctx, i) => const Divider(height: 24),
        itemBuilder: (ctx, i) {
          final appName = sortedList[i].key;
          final totalDuration = sortedList[i].value['total'] as int;
          final devices = sortedList[i].value['devices'] as Map<String, int>;

          // 构建子标题：设备明细，例如：[📱 手机: 1h 2m]  [💻 电脑: 30m]
          List<Widget> deviceWidgets = devices.entries.map((e) {
            String dName = _simplifyDeviceName(e.key);
            return Container(
              margin: const EdgeInsets.only(right: 12, top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getDeviceIcon(e.key), size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text("$dName: ${_formatDetailedTime(e.value)}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            );
          }).toList();

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: Text(
                  appName.isNotEmpty ? appName[0].toUpperCase() : "?",
                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)
              ),
            ),
            title: Text(appName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            // 使用 Wrap 使设备标签可以在多端使用时自动换行
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Wrap(
                children: deviceWidgets,
              ),
            ),
            trailing: Text(
              _formatDetailedTime(totalDuration),
              style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600, fontSize: 16),
            ),
          );
        },
      ),
    );
  }
}