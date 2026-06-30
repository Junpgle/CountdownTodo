import 'package:flutter/material.dart';
import '../../../services/llm_service.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/page_transitions.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../llm_config_page.dart';
import '../wallpaper_settings_page.dart';
import '../home_text_config_page.dart';

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
  final bool conflictDetectionEnabled;
  final ValueChanged<bool>? onConflictDetectionChanged;
  final String themeColorMode;
  final ValueChanged<String?> onThemeColorModeChanged;
  final Color? customThemeColor;
  final VoidCallback onPickCustomThemeColor;

  const PreferenceSection({
    super.key,
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
    this.conflictDetectionEnabled = false,
    this.onConflictDetectionChanged,
    required this.themeColorMode,
    required this.onThemeColorModeChanged,
    this.customThemeColor,
    required this.onPickCustomThemeColor,
  });

  // 🚀 辅助方法：构建带高亮动画的 Tile
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
      title: '偏好设置',
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
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'conflict_detection',
          child: ListTile(
            leading: Icon(Icons.warning_amber_outlined,
                color: colorScheme.cdtWarning),
            title: const Text('冲突检测'),
            subtitle: const Text('检测待办时间重叠；关闭后首页不弹冲突提醒'),
            trailing: Switch(
              value: conflictDetectionEnabled,
              activeThumbColor: colorScheme.cdtWarning,
              onChanged: onConflictDetectionChanged,
            ),
          ),
        ),
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'server_choice',
          child: ListTile(
            leading: const Icon(Icons.cloud_queue),
            title: const Text('云端数据接口线路'),
            subtitle: Text(
              serverChoice == 'cloudflare'
                  ? '当前: Cloudflare (2026/06/01 即将禁用)'
                  : '当前: 阿里云ECS (更快)',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onServerChoiceTap,
          ),
        ),
        const AppSettingsDivider(),
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
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'theme_color',
          child: ListTile(
            leading: const Icon(Icons.format_paint_outlined),
            title: const Text('全局主题颜色'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (themeColorMode == 'custom' ||
                    themeColorMode == 'image_extracted')
                  GestureDetector(
                    onTap: onPickCustomThemeColor,
                    child: Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: customThemeColor ??
                            Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: colorScheme.outline),
                      ),
                    ),
                  ),
                DropdownButton<String>(
                  value: themeColorMode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'default', child: Text('默认蓝色')),
                    DropdownMenuItem(
                        value: 'system_wallpaper', child: Text('跟随壁纸/系统')),
                    DropdownMenuItem(
                        value: 'image_extracted', child: Text('从图片提取')),
                    DropdownMenuItem(value: 'custom', child: Text('自定义颜色')),
                  ],
                  onChanged: onThemeColorModeChanged,
                ),
              ],
            ),
          ),
        ),
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'llm_config',
          child: ListTile(
            leading:
                Icon(Icons.psychology_outlined, color: colorScheme.primary),
            title: const Text('大模型API配置'),
            subtitle: FutureBuilder<LLMConfig?>(
              future: LLMService.getConfig(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text('加载中...', style: TextStyle(fontSize: 12));
                }
                final config = snapshot.data;
                if (config == null || !config.isConfigured) {
                  return Text(
                    '未配置，用于AI智能解析待办',
                    style:
                        TextStyle(fontSize: 12, color: colorScheme.cdtWarning),
                  );
                }
                return Text(
                  '已配置: ${config.model}',
                  style: TextStyle(fontSize: 12, color: colorScheme.cdtSuccess),
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
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'llm_retry',
          child: ListTile(
            leading: Icon(Icons.refresh_outlined, color: colorScheme.primary),
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
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'wallpaper',
          child: ListTile(
            leading: Icon(Icons.wallpaper_outlined, color: colorScheme.primary),
            title: const Text('首页壁纸设置'),
            subtitle: const Text('来源切换、必应选项配置 (地区/分辨率/格式)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                PageTransitions.material(
                    builder: (context) => const WallpaperSettingsPage()),
              );
            },
          ),
        ),
        const AppSettingsDivider(),
        _buildTile(
          context: context,
          targetId: 'home_text',
          child: ListTile(
            leading: Icon(Icons.text_fields, color: colorScheme.secondary),
            title: const Text('首页文字自定义'),
            subtitle: const Text('自定义问候语、日期格式、用户名显示'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await Navigator.push<bool>(
                context,
                PageTransitions.material(
                    builder: (context) => const HomeTextConfigPage()),
              );
              if (result == true && context.mounted) {
                (context as Element).markNeedsBuild();
              }
            },
          ),
        ),
        if (AppPlatform.isWindows) ...[
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'tai_db',
            child: ListTile(
              leading: Icon(Icons.timer_outlined, color: colorScheme.primary),
              title: const Text('Tai 屏幕时间数据库'),
              subtitle: Text(
                taiDbPath.isEmpty ? '未设置，点击选择 data.db 文件' : taiDbPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: taiDbPath.isEmpty
                      ? colorScheme.cdtWarning
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.folder_open_outlined),
              onTap: onPickTaiDatabase,
            ),
          ),
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'float_window_style',
            child: ListTile(
              leading: Icon(Icons.layers_outlined, color: colorScheme.primary),
              title: const Text('灵动岛'),
              subtitle: const Text('开启灵动岛式浮动窗口'),
              trailing: Switch(
                value: floatWindowStyle != 2,
                activeThumbColor: colorScheme.primary,
                onChanged: (val) {
                  if (onFloatWindowStyleChanged != null) {
                    onFloatWindowStyleChanged!(val ? 1 : 2);
                  }
                },
              ),
            ),
          ),
          const AppSettingsDivider(),
          _buildTile(
            context: context,
            targetId: 'force_refresh',
            child: ListTile(
              leading: Icon(Icons.refresh, color: colorScheme.primary),
              title: const Text('强制刷新悬浮窗位置'),
              subtitle: const Text('将灵动岛悬浮窗重置到屏幕中央'),
              trailing: TextButton(
                onPressed: onForceRefreshPressed,
                child: const Text('强制刷新'),
              ),
            ),
          ),
          if (floatWindowStyle != 2) ...[
            const AppSettingsDivider(),
            _buildTile(
              context: context,
              targetId: 'island_priority',
              child: ListTile(
                leading: Icon(Icons.priority_high, color: colorScheme.primary),
                title: const Text('灵动岛优先级设置'),
                subtitle: const Text('配置哪些应用可以抢占灵动岛显示'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onIslandPriorityPressed,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
