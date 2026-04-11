import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/llm_service.dart';
import '../../../utils/page_transitions.dart';
import '../llm_config_page.dart';

class PreferenceSection extends StatelessWidget {
  final VoidCallback onManageHomeSections;
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
  final String wallpaperProvider;
  final ValueChanged<String?>? onWallpaperProviderChanged;
  final String wallpaperImageFormat;
  final int wallpaperIndex;
  final String wallpaperMkt;
  final String wallpaperResolution;
  final ValueChanged<String?>? onWallpaperImageFormatChanged;
  final ValueChanged<int?>? onWallpaperIndexChanged;
  final ValueChanged<String?>? onWallpaperMktChanged;
  final ValueChanged<String?>? onWallpaperResolutionChanged;

  const PreferenceSection({
    Key? key,
    required this.onManageHomeSections,
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
    this.wallpaperProvider = 'bing',
    this.onWallpaperProviderChanged,
    this.wallpaperImageFormat = 'jpg',
    this.wallpaperIndex = 0,
    this.wallpaperMkt = 'zh-CN',
    this.wallpaperResolution = 'UHD',
    this.onWallpaperImageFormatChanged,
    this.onWallpaperIndexChanged,
    this.onWallpaperMktChanged,
    this.onWallpaperResolutionChanged,
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
                subtitle: Text(
                  serverChoice == 'cloudflare'
                      ? '当前: Cloudflare (更安全)'
                      : '当前: 阿里云ECS (更快)',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onServerChoiceTap,
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
              const Divider(height: 1, indent: 56),
              ListTile(
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
              const Divider(height: 1, indent: 56),
              ListTile(
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
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.wallpaper_outlined,
                    color: Colors.deepPurple),
                title: const Text('首页壁纸来源'),
                subtitle: const Text('GitHub: 随机仓库壁纸 | Bing: 必应每日一图'),
                trailing: DropdownButton<String>(
                  value: wallpaperProvider,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'github', child: Text('GitHub 随机')),
                    DropdownMenuItem(value: 'bing', child: Text('Bing 每日一图')),
                  ],
                  onChanged: onWallpaperProviderChanged,
                ),
              ),
              if (wallpaperProvider == 'bing') ...[
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.image_outlined,
                      color: Colors.deepPurple, size: 20),
                  title: const Text('图片格式', style: TextStyle(fontSize: 14)),
                  trailing: DropdownButton<String>(
                    value: wallpaperImageFormat,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'jpg', child: Text('JPG')),
                      DropdownMenuItem(value: 'webp', child: Text('WebP')),
                    ],
                    onChanged: onWallpaperImageFormatChanged,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.history,
                      color: Colors.deepPurple, size: 20),
                  title: const Text('壁纸索引', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('0为今日，1为昨日...', style: TextStyle(fontSize: 11)),
                  trailing: DropdownButton<int>(
                    value: wallpaperIndex,
                    underline: const SizedBox(),
                    items: List.generate(
                        8,
                        (i) => DropdownMenuItem(
                            value: i, child: Text(i == 0 ? '今日' : '$i 天前'))),
                    onChanged: onWallpaperIndexChanged,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.language_outlined,
                      color: Colors.deepPurple, size: 20),
                  title: const Text('地区/语言', style: TextStyle(fontSize: 14)),
                  trailing: DropdownButton<String>(
                    value: wallpaperMkt,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'zh-CN', child: Text('中国 (简体)')),
                      DropdownMenuItem(value: 'en-US', child: Text('美国 (英语)')),
                      DropdownMenuItem(value: 'ja-JP', child: Text('日本 (日语)')),
                      DropdownMenuItem(value: 'en-AU', child: Text('澳大利亚')),
                      DropdownMenuItem(value: 'en-GB', child: Text('英国')),
                      DropdownMenuItem(value: 'de-DE', child: Text('德国')),
                      DropdownMenuItem(value: 'en-NZ', child: Text('新西兰')),
                      DropdownMenuItem(value: 'en-CA', child: Text('加拿大')),
                      DropdownMenuItem(value: 'en-IN', child: Text('印度')),
                      DropdownMenuItem(value: 'fr-FR', child: Text('法国')),
                      DropdownMenuItem(value: 'it-IT', child: Text('意大利')),
                      DropdownMenuItem(value: 'es-ES', child: Text('西班牙')),
                      DropdownMenuItem(value: 'pt-BR', child: Text('巴西')),
                    ],
                    onChanged: onWallpaperMktChanged,
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.monitor_outlined,
                      color: Colors.deepPurple, size: 20),
                  title: const Text('分辨率', style: TextStyle(fontSize: 14)),
                  trailing: DropdownButton<String>(
                    value: wallpaperResolution,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: '1366', child: Text('1366x768')),
                      DropdownMenuItem(value: '1920', child: Text('1080P')),
                      DropdownMenuItem(value: '3840', child: Text('4K (3840)')),
                      DropdownMenuItem(value: 'UHD', child: Text('超高清 (UHD)')),
                    ],
                    onChanged: onWallpaperResolutionChanged,
                  ),
                ),
              ],
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
                  leading:
                      const Icon(Icons.layers_outlined, color: Colors.indigo),
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
