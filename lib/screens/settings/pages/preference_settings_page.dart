import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
import '../server_choice_page.dart';
import '../wallpaper_settings_page.dart';
import '../home_text_config_page.dart';
import '../../animation_settings_page.dart';

class PreferenceSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const PreferenceSettingsPage({super.key, this.initialTarget, this.isEmbedded = false});

  @override
  State<PreferenceSettingsPage> createState() => _PreferenceSettingsPageState();
}

class _PreferenceSettingsPageState extends State<PreferenceSettingsPage> {
  final Map<String, GlobalKey> _itemKeys = {
    'sync_interval': GlobalKey(),
    'conflict_detection': GlobalKey(),
    'server_choice': GlobalKey(),
    'theme': GlobalKey(),
    'theme_color': GlobalKey(),
    'wallpaper': GlobalKey(),
    'home_text': GlobalKey(),
    'animation': GlobalKey(),
  };

  bool _isLoading = true;
  String? _highlightTarget;

  int _syncInterval = 0;
  bool _conflictDetectionEnabled = false;
  String _serverChoice = 'aliyun';
  String _themeMode = 'system';
  String _themeColorMode = 'default';
  Color? _customThemeColor;
  String _username = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    
    int interval = await StorageService.getSyncInterval();
    bool conflict = await StorageService.getConflictDetectionEnabled();
    String server = await StorageService.getServerChoice();
    String theme = await StorageService.getThemeMode();
    String themeColorMode = prefs.getString(StorageService.KEY_THEME_COLOR_MODE) ?? 'default';
    int? customColorVal = prefs.getInt(StorageService.KEY_CUSTOM_THEME_COLOR);

    if (mounted) {
      setState(() {
        _syncInterval = interval;
        _conflictDetectionEnabled = conflict;
        _serverChoice = server;
        _themeMode = theme;
        _themeColorMode = themeColorMode;
        if (customColorVal != null) {
          _customThemeColor = Color(customColorVal);
        }
        _isLoading = false;
      });
    }
  }

  void _scrollToTarget(String target) {
    final key = _itemKeys[target];
    if (key?.currentContext != null) {
      setState(() => _highlightTarget = target);
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted) setState(() => _highlightTarget = null);
      });
    }
  }

  Future<void> _setConflictDetectionEnabled(bool enabled) async {
    setState(() => _conflictDetectionEnabled = enabled);
    await StorageService.saveAppSetting(StorageService.KEY_CONFLICT_DETECTION_ENABLED, enabled);
    if (!enabled && _username.isNotEmpty && _username != '加载中...') {
      await StorageService.clearLocalTodoScheduleConflicts(_username);
    }
  }

  Future<void> _handleThemeColorModeChanged(String? val) async {
    if (val == null) return;
    
    if (val == 'image_extracted') {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        try {
          final colorScheme = await ColorScheme.fromImageProvider(provider: FileImage(File(image.path)));
          await StorageService.setCustomThemeColor(colorScheme.primary);
          setState(() => _customThemeColor = colorScheme.primary);
          await StorageService.setThemeColorMode(val);
          setState(() => _themeColorMode = val);
        } catch (e) {
          debugPrint('Failed to extract color from image: $e');
        }
      }
    } else if (val == 'custom') {
      _handlePickCustomThemeColor();
      await StorageService.setThemeColorMode(val);
      setState(() => _themeColorMode = val);
    } else {
      await StorageService.setThemeColorMode(val);
      setState(() => _themeColorMode = val);
    }
  }

  Future<void> _handlePickCustomThemeColor() async {
    Color pickerColor = _customThemeColor ?? Theme.of(context).colorScheme.primary;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择自定义颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (Color color) {
              pickerColor = color;
            },
            enableAlpha: false,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('确定'),
            onPressed: () {
              StorageService.setCustomThemeColor(pickerColor);
              setState(() {
                _customThemeColor = pickerColor;
                _themeColorMode = 'custom';
              });
              StorageService.setThemeColorMode('custom');
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTile({required String targetId, required Widget child}) {
    final bool isHighlighted = _highlightTarget == targetId;
    return Container(
      key: _itemKeys[targetId],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(
        title: const Text('偏好设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          _buildTile(
            targetId: 'sync_interval',
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('自动同步频率'),
              trailing: DropdownButton<int>(
                value: _syncInterval,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                  DropdownMenuItem(value: 10, child: Text('每 10 分钟')),
                  DropdownMenuItem(value: 60, child: Text('每小时')),
                  DropdownMenuItem(value: 0, child: Text('每次启动')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _syncInterval = val);
                    StorageService.saveAppSetting(StorageService.KEY_SYNC_INTERVAL, val);
                  }
                },
              ),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'conflict_detection',
            child: ListTile(
              leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
              title: const Text('冲突检测'),
              subtitle: const Text('检测待办时间重叠；关闭后首页不弹冲突提醒'),
              trailing: Switch(
                value: _conflictDetectionEnabled,
                activeThumbColor: Colors.orange,
                onChanged: _setConflictDetectionEnabled,
              ),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'server_choice',
            child: ListTile(
              leading: const Icon(Icons.cloud_queue),
              title: const Text('云端数据接口线路'),
              subtitle: Text(
                _serverChoice == 'cloudflare' ? '当前: Cloudflare' : '当前: 阿里云ECS (更快)',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    ServerChoicePage(
                      initialServerChoice: _serverChoice,
                      isEmbedded: widget.isEmbedded,
                    ),
                    settings: const RouteSettings(name: '云端数据接口线路'),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'theme',
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('深色模式/主题'),
              trailing: DropdownButton<String>(
                value: _themeMode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem(value: 'light', child: Text('浅色')),
                  DropdownMenuItem(value: 'dark', child: Text('深色')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _themeMode = val);
                    StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, val);
                    StorageService.themeNotifier.value = val;
                  }
                },
              ),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'theme_color',
            child: ListTile(
              leading: const Icon(Icons.format_paint_outlined),
              title: const Text('全局主题颜色'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_themeColorMode == 'custom' || _themeColorMode == 'image_extracted')
                    GestureDetector(
                      onTap: _handlePickCustomThemeColor,
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: _customThemeColor ?? Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                  DropdownButton<String>(
                    value: _themeColorMode,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'default', child: Text('默认蓝色')),
                      DropdownMenuItem(value: 'system_wallpaper', child: Text('跟随壁纸/系统')),
                      DropdownMenuItem(value: 'image_extracted', child: Text('从图片提取')),
                      DropdownMenuItem(value: 'custom', child: Text('自定义颜色')),
                    ],
                    onChanged: _handleThemeColorModeChanged,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'animation',
            child: ListTile(
              leading: Icon(Icons.animation_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('动画设置', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('页面切换动画、Container Transform、性能选项'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    AnimationSettingsPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '动画设置'),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'wallpaper',
            child: ListTile(
              leading: const Icon(Icons.wallpaper_outlined, color: Colors.deepPurple),
              title: const Text('首页壁纸设置'),
              subtitle: const Text('来源切换、必应选项配置 (地区/分辨率/格式)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '首页壁纸设置'),
                    builder: (context) => WallpaperSettingsPage(isEmbedded: widget.isEmbedded),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, indent: 56),
          _buildTile(
            targetId: 'home_text',
            child: ListTile(
              leading: const Icon(Icons.text_fields, color: Colors.teal),
              title: const Text('首页文字自定义'),
              subtitle: const Text('自定义问候语、日期格式、用户名显示'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '首页文字自定义'),
                    builder: (context) => HomeTextConfigPage(isEmbedded: widget.isEmbedded),
                  ),
                );
                if (result == true && context.mounted) {
                  setState(() {});
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
