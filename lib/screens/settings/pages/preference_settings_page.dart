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
import '../calendar_sync_page.dart';
import '../../feature_guide_screen.dart';
import '../handlers/storage_management_handler.dart';
import '../dialogs/migration_dialog.dart';
import '../../../update_service.dart';

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
    'migration': GlobalKey(),
    'cache': GlobalKey(),
    'storage': GlobalKey(),
    'calendar_sync': GlobalKey(),
    'update': GlobalKey(),
    'feature_guide': GlobalKey(),
  };

  bool _isLoading = true;
  String? _highlightTarget;

  String _themeMode = 'system';
  String _themeColorMode = 'default';
  Color? _customThemeColor;
  String _username = '';

  bool _isCheckingUpdate = false;
  String _cacheSizeStr = "计算中...";
  late StorageManagementHandler _storageManagementHandler;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    
    _storageManagementHandler = StorageManagementHandler(
      context: context,
      getUsername: () => _username,
      onUpdateCacheSize: (val) {
        if (mounted) setState(() => _cacheSizeStr = val);
      },
      showLoading: (msg) => _showLoadingDialog(context, msg),
      closeLoading: () => _closeLoadingDialog(context),
      showMessage: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
    );
    _storageManagementHandler.calculateCacheSize();

    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString(StorageService.KEY_CURRENT_USER) ?? '';
    
    String theme = await StorageService.getThemeMode();
    String themeColorMode = prefs.getString(StorageService.KEY_THEME_COLOR_MODE) ?? 'default';
    int? customColorVal = prefs.getInt(StorageService.KEY_CUSTOM_THEME_COLOR);

    if (mounted) {
      setState(() {
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



  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _closeLoadingDialog(BuildContext context) {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _showMigrationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MigrationDialog(
        onSuccess: () {},
      ),
    );
  }

  Future<void> _checkUpdatesAndNotices() async {
    setState(() => _isCheckingUpdate = true);
    await UpdateService.checkUpdateAndPrompt(context, isManual: true);
    if (mounted) setState(() => _isCheckingUpdate = false);
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
        title: const Text('系统与外观'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
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
                  PageTransitions.slideHorizontal(
                    WallpaperSettingsPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '首页壁纸设置'),
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
                  PageTransitions.slideHorizontal(
                    HomeTextConfigPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '首页文字自定义'),
                  ),
                );
                if (result == true && context.mounted) {
                  setState(() {});
                }
              },
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('系统与存储', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'cache',
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined, color: Colors.brown),
              title: const Text('深度清理缓存与冗余'),
              subtitle: const Text('包含更新残留包与深度图片缓存'),
              trailing: Text(_cacheSizeStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              onTap: _storageManagementHandler.clearCache,
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'storage',
            child: ListTile(
              leading: const Icon(Icons.data_usage, color: Colors.orange),
              title: const Text('存储空间深度分析'),
              subtitle: const Text('找出占用数百MB的隐藏文件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _storageManagementHandler.showStorageAnalysis,
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'update',
            child: ListTile(
              leading: const Icon(Icons.system_update_outlined, color: Colors.green),
              title: const Text('检查新版本'),
              trailing: _isCheckingUpdate ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
              onTap: _isCheckingUpdate ? null : _checkUpdatesAndNotices,
            ),
          ),

          const Padding(
            padding: EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('其他工具', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          _buildTile(
            targetId: 'feature_guide',
            child: ListTile(
              leading: const Icon(Icons.school_outlined, color: Colors.indigo),
              title: const Text('重新查看新版教程与权限设置'),
              subtitle: const Text('可再次查看功能介绍与重新配置各项权限'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(const FeatureGuideScreen()),
                );
              },
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'migration',
            child: ListTile(
              leading: const Icon(Icons.move_to_inbox, color: Colors.teal),
              title: const Text('旧版本地数据一键迁移'),
              subtitle: const Text('包含待办、课程、课表与习惯数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showMigrationDialog,
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'calendar_sync',
            child: ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.redAccent),
              title: const Text('日历同步向导'),
              subtitle: const Text('将本软件课表双向同步至系统日历'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(
                    CalendarSyncPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '日历同步向导'),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
