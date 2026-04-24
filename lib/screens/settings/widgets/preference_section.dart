import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/llm_service.dart';
import '../../../utils/page_transitions.dart';
import '../llm_config_page.dart';
import '../wallpaper_settings_page.dart';

class PreferenceSection extends StatelessWidget {
  final String? highlightTarget;
  final Map<String, GlobalKey>? itemKeys; // 🚀 新增：子项 Key 映射
  final int syncInterval;
  final ValueChanged<int?> onSyncIntervalChanged;
  final String serverChoice;
  final VoidCallback onServerChoiceTap;
  final String themeMode;
  final ValueChanged<String?> onThemeModeChanged;
  final String taiDbPath;
  final VoidCallback onPickTaiDatabase;
  final int floatWindowStyle; // 0: 经典, 1: 灵动岛, 2: 关闭
  final ValueChanged<int?>? onFloatWindowStyleChanged;
  final VoidCallback? onForceRefreshPressed;
  final VoidCallback? onIslandPriorityPressed;
  final int llmRetryCount;
  final ValueChanged<int?>? onLLMRetryCountChanged;

  const PreferenceSection({
    Key? key,
    this.highlightTarget,
    this.itemKeys,
    required this.syncInterval,
    required this.onSyncIntervalChanged,
    required this.serverChoice,
    required this.onServerChoiceTap,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.taiDbPath,
    required this.onPickTaiDatabase,
    required this.floatWindowStyle,
    this.onFloatWindowStyleChanged,
    this.onForceRefreshPressed,
    this.onIslandPriorityPressed,
    this.llmRetryCount = 3,
    this.onLLMRetryCountChanged,
  }) : super(key: key);

  // 🚀 辅助方法：构建带高亮动画的 Tile
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
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2) 
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
              _buildTile(
                context: context,
                targetId: 'sync_interval',
                child: ListTile(
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
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'server_choice',
                child: ListTile(
                  leading: const Icon(Icons.cloud_queue),
                  title: const Text('云端数据接口线路'),
                  subtitle: Text(
                    serverChoice == 'cloudflare'
                        ? '当前: Cloudflare (更安全)'
                        : '当前: 阿里云ECS (更快)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onServerChoiceTap,
                ),
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'theme',
                child: ListTile(
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
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'llm_config',
                child: ListTile(
                  leading: const Icon(Icons.psychology_outlined,
                      color: Colors.deepPurple),
                  title: const Text('大模型API配置'),
                  subtitle: FutureBuilder<LLMConfig?>(
                    future: LLMService.getConfig(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Text('加载中...',
                            style: TextStyle(fontSize: 12));
                      }
                      final config = snapshot.data;
                      if (config == null || !config.isConfigured) {
                        return const Text(
                          '未配置，用于AI智能解析待办',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        );
                      }
                      return Text(
                        '已配置: ${config.model}',
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                      );
                    },
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      PageTransitions.slideHorizontal(
                        const LLMConfigPage(),
                      ),
                    );
                    if (result == true) {
                      (context as Element).markNeedsBuild();
                    }
                  },
                ),
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'llm_retry',
                child: ListTile(
                  leading: const Icon(Icons.refresh_outlined,
                      color: Colors.deepPurple),
                  title: const Text('图片识别重试次数'),
                  subtitle: const Text('识别超时后自动重试的次数（后台异步执行）'),
                  trailing: DropdownButton<int>(
                    value: llmRetryCount,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('不重试')),
                      DropdownMenuItem(value: 1, child: Text('1 次')),
                      DropdownMenuItem(value: 2, child: Text('2 次')),
                      DropdownMenuItem(value: 3, child: Text('3 次')),
                      DropdownMenuItem(value: 5, child: Text('5 次')),
                    ],
                    onChanged: onLLMRetryCountChanged,
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
              _buildTile(
                context: context,
                targetId: 'wallpaper',
                child: ListTile(
                  leading: const Icon(Icons.wallpaper_outlined,
                      color: Colors.deepPurple),
                  title: const Text('首页壁纸设置'),
                  subtitle: const Text('来源切换、必应选项配置 (地区/分辨率/格式)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const WallpaperSettingsPage()),
                    );
                  },
                ),
              ),
              if (Platform.isWindows) ...[
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'tai_db',
                  child: ListTile(
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
                ),
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'float_window_style',
                  child: ListTile(
                    leading:
                        const Icon(Icons.layers_outlined, color: Colors.indigo),
                    title: const Text('灵动岛'),
                    subtitle: const Text('开启灵动岛式浮动窗口'),
                    trailing: Switch(
                      value: floatWindowStyle != 2,
                      activeColor: Colors.indigo,
                      onChanged: (val) {
                        if (onFloatWindowStyleChanged != null) {
                          onFloatWindowStyleChanged!(val ? 1 : 2);
                        }
                      },
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _buildTile(
                  context: context,
                  targetId: 'force_refresh',
                  child: ListTile(
                    leading: const Icon(Icons.refresh, color: Colors.indigo),
                    title: const Text('强制刷新悬浮窗位置'),
                    subtitle: const Text('将灵动岛悬浮窗重置到屏幕中央'),
                    trailing: TextButton(
                      onPressed: onForceRefreshPressed,
                      child: const Text('强制刷新'),
                    ),
                  ),
                ),
                if (floatWindowStyle != 2) ...[
                  const Divider(height: 1, indent: 56),
                  _buildTile(
                    context: context,
                    targetId: 'island_priority',
                    child: ListTile(
                      leading: const Icon(Icons.priority_high, color: Colors.indigo),
                      title: const Text('灵动岛优先级设置'),
                      subtitle: const Text('配置哪些应用可以抢占灵动岛显示'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: onIslandPriorityPressed,
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
