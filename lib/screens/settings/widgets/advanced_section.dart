import 'dart:io';
import 'package:flutter/material.dart';

class AdvancedSection extends StatelessWidget {
  final VoidCallback onShowMigrationDialog;
  final VoidCallback onTestCourseNotification;
  final String liveUpdatesStatus;
  final VoidCallback onCheckAndOpenLiveUpdates;
  final String islandStatus;
  final VoidCallback onCheckIslandSupport;

  const AdvancedSection({
    Key? key,
    required this.onShowMigrationDialog,
    required this.onTestCourseNotification,
    required this.liveUpdatesStatus,
    required this.onCheckAndOpenLiveUpdates,
    required this.islandStatus,
    required this.onCheckIslandSupport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('高级设置与数据迁移',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.rocket_launch, color: Colors.white)),
            title: const Text('从 Cloudflare 后端一键全量迁移',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                    '自动将 D1 上您的整套账户(密码)、待办、番茄钟打包移植至当前阿里云节点，实现无缝搬家。',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13))),
            trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20))),
                onPressed: onShowMigrationDialog,
                child: const Text('开始')),
          ),
        ),
        const SizedBox(height: 12),
        if (Platform.isAndroid) ...[
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const Icon(Icons.notification_important_outlined,
                  color: Colors.amber),
              title: const Text('测试课程实时通知'),
              subtitle: const Text('强制发送一个课程提醒用于排查显示问题'),
              trailing: TextButton(
                  onPressed: onTestCourseNotification,
                  child: const Text("发送测试")),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.notifications_active, color: Colors.white)),
              title: const Text('Android 16 实时活动',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(liveUpdatesStatus,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13))),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: onCheckAndOpenLiveUpdates,
                  child: const Text('去开启')),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: const CircleAvatar(
                  backgroundColor: Colors.deepPurpleAccent,
                  child: Icon(Icons.smart_button, color: Colors.white)),
              title: const Text('小米超级岛支持',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(islandStatus,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13))),
              trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  onPressed: onCheckIslandSupport,
                  child: const Text('检测')),
            ),
          ),
        ],
      ],
    );
  }
}
