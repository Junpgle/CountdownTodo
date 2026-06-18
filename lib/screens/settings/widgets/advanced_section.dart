import 'dart:io';
import 'package:flutter/material.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';

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
    return AppSettingsHighlightedTile(
      targetId: targetId,
      highlightTarget: highlightTarget,
      itemKeys: itemKeys,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSettingsSection(
      title: '高级设置',
      children: [
        if (Platform.isAndroid) ...[
          _buildTile(
            context: context,
            targetId: 'test_notification',
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              minLeadingWidth: 36,
              leading: Icon(Icons.notification_important_outlined,
                  size: 20, color: colorScheme.cdtWarning),
              title: const Text('测试课程实时通知', style: TextStyle(fontSize: 14)),
              subtitle: const Text('强制发送一个课程提醒用于排查显示问题',
                  style: TextStyle(fontSize: 12)),
              trailing: TextButton(
                  onPressed: onTestCourseNotification,
                  child: const Text("发送测试", style: TextStyle(fontSize: 12))),
            ),
          ),
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'live_updates',
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              minLeadingWidth: 36,
              leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.cdtInfoContainer,
                  child: Icon(Icons.notifications_active,
                      size: 18, color: colorScheme.cdtOnInfoContainer)),
              title: const Text('Android 16 实时活动',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(liveUpdatesStatus,
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 12)),
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
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'float_window_style',
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              minLeadingWidth: 36,
              leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.secondaryContainer,
                  child: Icon(Icons.smart_button,
                      size: 18, color: colorScheme.onSecondaryContainer)),
              title: const Text('小米超级岛支持',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(islandStatus,
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 12)),
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
            const AppSettingsDivider(),
            _buildTile(
              context: context,
              targetId: 'band_sync',
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                minLeadingWidth: 36,
                leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.cdtSuccessContainer,
                    child: Icon(Icons.watch,
                        size: 18, color: colorScheme.cdtOnSuccessContainer)),
                title: const Text('手环同步',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('与小米手环同步待办、课程、倒计时',
                    style: TextStyle(fontSize: 12)),
                trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(60, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20))),
                    onPressed: onOpenBandSync,
                    child: const Text('进入', style: TextStyle(fontSize: 12))),
              ),
            ),
          ],
        ],
        if (onOpenLanSync != null) ...[
          if (Platform.isAndroid) const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'lan_sync',
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              minLeadingWidth: 36,
              leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(Icons.wifi_tethering,
                      size: 18, color: colorScheme.onPrimaryContainer)),
              title: const Text('局域网同步',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle:
                  const Text('同账号设备间局域网同步数据', style: TextStyle(fontSize: 12)),
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
    );
  }
}
