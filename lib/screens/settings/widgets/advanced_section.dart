import 'dart:io';
import 'package:flutter/material.dart';

class AdvancedSection extends StatelessWidget {
  final String? highlightTarget;
  final Map<String, GlobalKey>? itemKeys;
  final VoidCallback onShowMigrationDialog;
  final VoidCallback onTestCourseNotification;
  final String liveUpdatesStatus;
  final VoidCallback onCheckAndOpenLiveUpdates;
  final String islandStatus;
  final VoidCallback onCheckIslandSupport;
  final VoidCallback? onOpenBandSync;
  final VoidCallback? onOpenLanSync;

  const AdvancedSection({
    super.key,
    this.highlightTarget,
    this.itemKeys,
    required this.onShowMigrationDialog,
    required this.onTestCourseNotification,
    required this.liveUpdatesStatus,
    required this.onCheckAndOpenLiveUpdates,
    required this.islandStatus,
    required this.onCheckIslandSupport,
    this.onOpenBandSync,
    this.onOpenLanSync,
  });

  Widget _buildTile({
    required BuildContext context,
    required String targetId,
    required Widget child,
  }) {
    final bool isHighlighted = highlightTarget == targetId;
    return Container(
      key: itemKeys?[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text(
            '高级设置',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _buildTile(
                context: context,
                targetId: 'migration',
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  minLeadingWidth: 36,
                  leading: const CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.rocket_launch,
                          size: 18, color: Colors.white)),
                  title: const Text('从 Cloudflare 后端一键全量迁移',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('自动将 D1 上您的整套账户(密码)、待办、番茄钟打包移植至当前阿里云节点',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(60, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      onPressed: onShowMigrationDialog,
                      child: const Text('开始', style: TextStyle(fontSize: 12))),
                ),
              ),
              if (Platform.isAndroid) ...[
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'test_notification',
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    minLeadingWidth: 36,
                    leading: const Icon(Icons.notification_important_outlined,
                        size: 20, color: Colors.amber),
                    title: const Text('测试课程实时通知', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('强制发送一个课程提醒用于排查显示问题',
                        style: TextStyle(fontSize: 12)),
                    trailing: TextButton(
                        onPressed: onTestCourseNotification,
                        child:
                            const Text("发送测试", style: TextStyle(fontSize: 12))),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'live_updates',
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    minLeadingWidth: 36,
                    leading: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.notifications_active,
                            size: 18, color: Colors.white)),
                    title: const Text('Android 16 实时活动',
                        style:
                            TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(liveUpdatesStatus,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(60, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        onPressed: onCheckAndOpenLiveUpdates,
                        child: const Text('去开启', style: TextStyle(fontSize: 12))),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'float_window_style',
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    minLeadingWidth: 36,
                    leading: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.deepPurpleAccent,
                        child: Icon(Icons.smart_button,
                            size: 18, color: Colors.white)),
                    title: const Text('小米超级岛支持',
                        style:
                            TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(islandStatus,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(60, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        onPressed: onCheckIslandSupport,
                        child: const Text('检测', style: TextStyle(fontSize: 12))),
                  ),
                ),
                if (onOpenBandSync != null) ...[
                  const Divider(height: 1, indent: 56),
                  _buildTile(
                    context: context,
                    targetId: 'band_sync',
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 4.0),
                      minLeadingWidth: 36,
                      leading: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.indigo,
                          child:
                              Icon(Icons.watch, size: 18, color: Colors.white)),
                      title: const Text('手环同步',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: const Text('与小米手环同步待办、课程、倒计时',
                          style: TextStyle(fontSize: 12)),
                      trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(60, 32),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20))),
                          onPressed: onOpenBandSync,
                          child:
                              const Text('进入', style: TextStyle(fontSize: 12))),
                    ),
                  ),
                ],
              ],
              if (onOpenLanSync != null) ...[
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'lan_sync',
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 4.0),
                    minLeadingWidth: 36,
                    leading: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.cyan,
                        child: Icon(Icons.wifi_tethering,
                            size: 18, color: Colors.white)),
                    title: const Text('局域网同步',
                        style:
                            TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('同账号设备间局域网同步数据',
                        style: TextStyle(fontSize: 12)),
                    trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(60, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20))),
                        onPressed: onOpenLanSync,
                        child: const Text('进入', style: TextStyle(fontSize: 12))),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
