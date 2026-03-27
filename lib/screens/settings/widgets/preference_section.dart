import 'dart:io';
import 'package:flutter/material.dart';

class PreferenceSection extends StatelessWidget {
  final VoidCallback onManageHomeSections;
  final int syncInterval;
  final ValueChanged<int?> onSyncIntervalChanged;
  final String serverChoice;
  final Function(String?) onServerChoiceChanged;
  final String themeMode;
  final ValueChanged<String?> onThemeModeChanged;
  final String taiDbPath;
  final VoidCallback onPickTaiDatabase;
  final int floatWindowStyle; // 0: 经典, 1: 灵动岛, 2: 关闭
  final ValueChanged<int?>? onFloatWindowStyleChanged;
  final VoidCallback? onForceRefreshPressed;
  final VoidCallback? onIslandPriorityPressed;

  const PreferenceSection({
    Key? key,
    required this.onManageHomeSections,
    required this.syncInterval,
    required this.onSyncIntervalChanged,
    required this.serverChoice,
    required this.onServerChoiceChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.taiDbPath,
    required this.onPickTaiDatabase,
    required this.floatWindowStyle,
    this.onFloatWindowStyleChanged,
    this.onForceRefreshPressed,
    this.onIslandPriorityPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Text('偏好设置',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('首页模块管理'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onManageHomeSections,
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('自动同步频率'),
                trailing: DropdownButton<int>(
                  value: syncInterval,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                    DropdownMenuItem(value: 10, child: Text('每 10 分钟')),
                    DropdownMenuItem(value: 60, child: Text('每小时')),
                    DropdownMenuItem(value: 0, child: Text('每次启动')),
                  ],
                  onChanged: onSyncIntervalChanged,
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.cloud_queue),
                title: const Text('云端数据接口线路'),
                subtitle: const Text('切换服务器后需要重新登录，且不同服务器的登录状态不互通'),
                trailing: DropdownButton<String>(
                  value: serverChoice,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                        value: 'cloudflare', child: Text('Cloudflare (更安全)')),
                    DropdownMenuItem(value: 'aliyun', child: Text('阿里云ECS (更快)')),
                  ],
                  onChanged: onServerChoiceChanged,
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('深色模式/主题'),
                trailing: DropdownButton<String>(
                  value: themeMode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                    DropdownMenuItem(value: 'light', child: Text('浅色')),
                    DropdownMenuItem(value: 'dark', child: Text('深色')),
                  ],
                  onChanged: onThemeModeChanged,
                ),
              ),
              if (Platform.isWindows) ...[
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading:
                      const Icon(Icons.timer_outlined, color: Colors.indigo),
                  title: const Text('Tai 屏幕时间数据库'),
                  subtitle: Text(
                    taiDbPath.isEmpty ? '未设置，点击选择 data.db 文件' : taiDbPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: taiDbPath.isEmpty ? Colors.orange : Colors.grey,
                    ),
                  ),
                  trailing: const Icon(Icons.folder_open_outlined),
                  onTap: onPickTaiDatabase,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.layers_outlined, color: Colors.indigo),
                  title: const Text('灵动岛'),
                  subtitle: const Text('开启灵动岛式浮动窗口'),
                  trailing: Switch(
                    value: floatWindowStyle != 2,
                    activeColor: Colors.indigo,
                    onChanged: (val) {
                      if (onFloatWindowStyleChanged != null) {
                        // 开启则设为 1 (灵动岛)，关闭则设为 2 (关闭)
                        onFloatWindowStyleChanged!(val ? 1 : 2);
                      }
                    },
                  ),
                ),
                if (floatWindowStyle != 2) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.sort, color: Colors.indigo),
                    title: const Text('灵动岛信息流优先级'),
                    subtitle: const Text('拖拽排序：决定灵动岛左右两侧的信息展示优先级'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onIslandPriorityPressed,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.refresh, color: Colors.indigo),
                    title: const Text('强制刷新悬浮窗位置'),
                    subtitle: const Text('将灵动岛悬浮窗重置到屏幕中央'),
                    trailing: TextButton(
                      onPressed: onForceRefreshPressed,
                      child: const Text('强制刷新'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
