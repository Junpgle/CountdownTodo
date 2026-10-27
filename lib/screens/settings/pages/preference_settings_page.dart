import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../storage_service.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/app_platform.dart';
import '../../../utils/time_utils.dart';
import '../../../utils/settings_navigation.dart';
import '../wallpaper_settings_page.dart';
import '../home_text_config_page.dart';
import 'home_layout_settings_page.dart';
import 'sidebar_menu_settings_page.dart';
import '../../feature_guide_screen.dart';
import '../../help/help_center_screen.dart';
import '../handlers/storage_management_handler.dart';
import '../dialogs/migration_dialog.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';
import '../../../widgets/floating_glass_control.dart';
import '../../../widgets/optional_liquid_glass_surface.dart';

class PreferenceSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const PreferenceSettingsPage({
    super.key,
    this.initialTarget,
    this.isEmbedded = false,
  });

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
    'home_layout': GlobalKey(),
    'sidebar_menu': GlobalKey(),
    'wallpaper': GlobalKey(),
    'home_text': GlobalKey(),
    'llm_retry': GlobalKey(),
    'migration': GlobalKey(),
    'cache': GlobalKey(),
    'storage': GlobalKey(),
    'help_center': GlobalKey(),
    'changelog': GlobalKey(),
    'feature_guide': GlobalKey(),
  };

  bool _isLoading = true;
  String? _highlightTarget;

  String _themeMode = 'system';
  bool _oledBlackModeEnabled = true;
  String _themeColorMode = 'default';
  Color? _customThemeColor;
  String _wallpaperProvider = 'bing';
  Map<String, dynamic> _homeTextConfig = {};
  String _username = '';

  String _cacheSizeStr = "计算中...";
  late StorageManagementHandler _storageManagementHandler;
  Timer? _highlightTimer;

  GlobalKey _navigationKey(String id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'settings-$id'));

  Future<T?> _openSettingsPage<T>(
    String id,
    Widget page, {
    RouteSettings? settings,
    bool rootNavigator = false,
  }) => SettingsNavigation.push<T>(
    context: context,
    page: page,
    sourceKey: _navigationKey(id),
    isEmbedded: widget.isEmbedded,
    rootNavigator: rootNavigator,
    settings: settings,
  );

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
      showMessage: (msg) => AppSnackBars.show(context, msg),
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
    _username = prefs.getString(StorageService.keyCurrentUser) ?? '';

    String theme = await StorageService.getThemeMode();
    bool oledBlackModeEnabled =
        prefs.getBool(StorageService.keyOledBlackMode) ?? true;
    String themeColorMode =
        prefs.getString(StorageService.keyThemeColorMode) ?? 'default';
    int? customColorVal = prefs.getInt(StorageService.keyCustomThemeColor);
    String wallpaperProvider = await StorageService.getWallpaperProvider();
    Map<String, dynamic> homeTextConfig =
        await StorageService.getHomeTextConfig();
    if (AppPlatform.isWeb && wallpaperProvider == 'custom') {
      wallpaperProvider = 'bing';
      await StorageService.saveWallpaperProvider(wallpaperProvider);
    }

    if (mounted) {
      setState(() {
        _themeMode = theme;
        _oledBlackModeEnabled = oledBlackModeEnabled;
        _themeColorMode = themeColorMode;
        _wallpaperProvider = wallpaperProvider;
        _homeTextConfig = homeTextConfig;
        if (customColorVal != null) {
          _customThemeColor = Color(customColorVal);
        }
        _isLoading = false;
      });
      if (widget.initialTarget != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToTarget(widget.initialTarget!);
        });
      }
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
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 3000), () {
        _highlightTimer = null;
        if (mounted) setState(() => _highlightTarget = null);
      });
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _showLoadingDialog(BuildContext context, String message) {
    AppDialogs.showLoading(context, message);
  }

  void _closeLoadingDialog(BuildContext context) {
    AppDialogs.close(context);
  }

  Future<void> _showMigrationDialog() async {
    await showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MigrationDialog(onSuccess: () {}),
    );
  }

  Future<void> _handleThemeColorModeChanged(String? val) async {
    if (val == null) return;

    if (val == 'image_extracted') {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        try {
          final imageBytes = await image.readAsBytes();
          final ImageProvider<Object> imageProvider = AppPlatform.isWindows
              ? ResizeImage(
                  MemoryImage(imageBytes),
                  width: 112,
                  height: 112,
                  policy: ResizeImagePolicy.fit,
                )
              : MemoryImage(imageBytes);
          final colorScheme = await ColorScheme.fromImageProvider(
            provider: imageProvider,
          );
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
    Color pickerColor =
        _customThemeColor ?? Theme.of(context).colorScheme.primary;
    await showAppDialog(
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
    return AppSettingsHighlightedTile(
      targetId: targetId,
      highlightTarget: _highlightTarget,
      itemKeys: _itemKeys,
      borderRadius: BorderRadius.zero,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWeb = AppPlatform.isWeb;
    if (_isLoading) {
      return const Scaffold(body: AppLoadingView());
    }
    return Scaffold(
      extendBodyBehindAppBar: !widget.isEmbedded,
      appBar: widget.isEmbedded
          ? null
          : FloatingGlassAppBar(
              flexibleSpace: const FloatingGlassTopBarBackground(),
              title: const Text('系统与外观'),
            ),
      body: floatingGlassSettingsBody(
        context,
        standalone: !widget.isEmbedded,
        child: ListView(
          padding: EdgeInsets.only(
            top: widget.isEmbedded
                ? 16
                : floatingGlassSettingsContentTopInset(context),
            bottom: 32,
          ),
          children: [
            // 1. 外观与色彩 (浅色、深色、自动 + 纯黑 OLED 模式 + 主题色盘)
            _buildMacGroupCard(
              children: [
                _buildAppearanceRow(),
                _buildMacDivider(),
                _buildOledBlackRow(),
                _buildMacDivider(),
                _buildColorSection(),
              ],
            ),

            // 2. 桌面与首页 (首页壁纸 + 首页文字 + 首页布局 + 侧边栏菜单)
            _buildMacSectionHeader('桌面与首页'),
            _buildMacGroupCard(
              children: [
                _buildWallpaperSection(),
                _buildMacDivider(),
                _buildHomeTextSection(),
                _buildMacDivider(),
                _buildHomeLayoutSection(),
                _buildMacDivider(),
                _buildSidebarMenuSection(),
              ],
            ),

            // 4. 系统与存储 Group Card (清理缓存 + 存储深度分析)
            _buildMacSectionHeader(isWeb ? '浏览器与存储' : '系统与存储'),
            _buildMacGroupCard(
              children: [
                _buildTile(
                  targetId: 'cache',
                  child: ListTile(
                    leading: Icon(
                      Icons.cleaning_services_outlined,
                      color: colorScheme.secondary,
                    ),
                    title: Text(isWeb ? '清理页面图片缓存' : '深度清理缓存与冗余'),
                    subtitle: Text(isWeb ? '清理当前浏览器页面的图片缓存' : '包含更新残留包与深度图片缓存'),
                    trailing: Text(
                      _cacheSizeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: _storageManagementHandler.clearCache,
                  ),
                ),
                if (!isWeb) ...[
                  _buildMacDivider(indent: 56),
                  _buildTile(
                    targetId: 'storage',
                    child: ListTile(
                      leading: Icon(
                        Icons.data_usage,
                        color: colorScheme.cdtWarning,
                      ),
                      title: const Text('存储空间深度分析'),
                      subtitle: const Text('找出占用数百MB的隐藏文件'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: _storageManagementHandler.showStorageAnalysis,
                    ),
                  ),
                ],
              ],
            ),

            // 5. 其他 Group Card (帮助与反馈 + 更新日志 + 版本引导 + 迁移)
            _buildMacSectionHeader('其他'),
            _buildMacGroupCard(
              children: [
                _buildTile(
                  targetId: 'help_center',
                  child: ListTile(
                    leading: Icon(
                      Icons.help_outline_rounded,
                      color: colorScheme.primary,
                    ),
                    title: const Text('帮助与反馈'),
                    subtitle: const Text('使用指南、快速上手、常见问题'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      _openSettingsPage(
                        'help_center',
                        HelpCenterScreen(username: _username),
                      );
                    },
                  ),
                ),
                _buildMacDivider(indent: 56),
                _buildTile(
                  targetId: 'changelog',
                  child: ListTile(
                    leading: Icon(
                      Icons.system_update_outlined,
                      color: colorScheme.primary,
                    ),
                    title: const Text('更新日志'),
                    subtitle: const Text('查看当前版本及历史更新内容'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      _openSettingsPage(
                        'changelog',
                        FeatureGuideScreen(
                          mode: FeatureGuideMode.changelog,
                          loggedInUser: _username,
                        ),
                        rootNavigator: true,
                      );
                    },
                  ),
                ),
                _buildMacDivider(indent: 56),
                _buildTile(
                  targetId: 'feature_guide',
                  child: ListTile(
                    leading: Icon(
                      Icons.school_outlined,
                      color: colorScheme.tertiary,
                    ),
                    title: const Text('版本引导'),
                    subtitle: const Text('查看新版本功能介绍与使用引导'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      _openSettingsPage(
                        'feature_guide',
                        FeatureGuideScreen(
                          mode: FeatureGuideMode.guide,
                          loggedInUser: _username,
                        ),
                        rootNavigator: true,
                      );
                    },
                  ),
                ),
                if (!isWeb) ...[
                  _buildMacDivider(indent: 56),
                  _buildTile(
                    targetId: 'migration',
                    child: ListTile(
                      leading: Icon(
                        Icons.move_to_inbox,
                        color: colorScheme.secondary,
                      ),
                      title: const Text('旧版本地数据一键迁移'),
                      subtitle: const Text('包含待办、课程、课表与习惯数据'),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: _showMigrationDialog,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperSection() {
    return _buildTile(
      targetId: 'wallpaper',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '首页壁纸',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                GestureDetector(
                  key: _navigationKey('wallpaper_advanced'),
                  onTap: () => _openSettingsPage(
                    'wallpaper_advanced',
                    WallpaperSettingsPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '首页壁纸设置'),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '高级设置',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWallpaperCard('bing', 'Bing每日一图', Icons.image_outlined),
                const SizedBox(width: 24),
                _buildWallpaperCard('github', 'GitHub随机', Icons.code),
                if (!AppPlatform.isWeb) ...[
                  const SizedBox(width: 24),
                  _buildWallpaperCard(
                    'custom',
                    '自定义图片',
                    Icons.folder_special_outlined,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperCard(String value, String title, IconData icon) {
    final isSelected = _wallpaperProvider == value;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        setState(() => _wallpaperProvider = value);
        StorageService.saveWallpaperProvider(value);
        StorageService.triggerWallpaperRefresh();
      },
      child: Column(
        children: [
          Container(
            width: 86,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? colorScheme.primary : Colors.transparent,
                width: 2.5,
              ),
              color: colorScheme.surfaceContainerHighest,
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                size: 28,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTextSection() {
    final now = DateTime.now();

    final usernameFormat =
        _homeTextConfig['usernameFormat'] as String? ?? '{name}';
    final displayName = usernameFormat.replaceAll(
      '{name}',
      _username.isNotEmpty ? _username : '用户',
    );

    final dateFormat =
        _homeTextConfig['dateFormat'] as String? ?? 'MM月dd日 EEEE';
    String dateStr;
    dateStr = AppTimeFormats.safeFormat(
      now,
      dateFormat,
      locale: 'zh_CN',
      fallbackPattern: 'MM月dd日 EEEE',
    );

    final salutationMode =
        _homeTextConfig['salutationMode'] as String? ?? 'timed';
    String salutation = '你好';
    if (salutationMode == 'fixed') {
      salutation = _homeTextConfig['fixedSalutation'] as String? ?? '你好';
    } else {
      final slots = _homeTextConfig['salutationSlots'] as List<dynamic>?;
      bool foundSlot = false;
      if (slots != null && slots.isNotEmpty) {
        final currentMinutes = now.hour * 60 + now.minute;
        for (var slot in slots) {
          final startM = slot['startHour'] * 60 + slot['startMinute'];
          final endM = slot['endHour'] * 60 + slot['endMinute'];
          bool inSlot = false;
          if (startM <= endM) {
            inSlot = currentMinutes >= startM && currentMinutes < endM;
          } else {
            inSlot = currentMinutes >= startM || currentMinutes < endM;
          }
          if (inSlot) {
            final txt = slot['text'] as String?;
            if (txt != null && txt.isNotEmpty) {
              salutation = txt;
              foundSlot = true;
              break;
            }
          }
        }
      }
      if (!foundSlot) {
        final hour = now.hour;
        if (hour >= 5 && hour < 12) {
          salutation = '上午好';
        } else if (hour >= 12 && hour < 14) {
          salutation = '中午好';
        } else if (hour >= 14 && hour < 18) {
          salutation = '下午好';
        } else if (hour >= 18 && hour < 23) {
          salutation = '晚上好';
        } else {
          salutation = '夜深了';
        }
      }
    }

    final greetingMode = _homeTextConfig['greetingMode'] as String? ?? 'timed';
    String greeting = '今天也要元气满满！';
    if (greetingMode == 'fixed') {
      final fixedList = _homeTextConfig['fixedGreetings'] as List<dynamic>?;
      if (fixedList != null && fixedList.isNotEmpty) {
        greeting = fixedList.first.toString();
      }
    } else {
      final timeSlots = _homeTextConfig['timeSlots'] as List<dynamic>?;
      if (timeSlots != null && timeSlots.isNotEmpty) {
        final currentMinutes = now.hour * 60 + now.minute;
        for (var slot in timeSlots) {
          final startM = slot['startHour'] * 60 + slot['startMinute'];
          final endM = slot['endHour'] * 60 + slot['endMinute'];
          bool inSlot = false;
          if (startM <= endM) {
            inSlot = currentMinutes >= startM && currentMinutes < endM;
          } else {
            inSlot = currentMinutes >= startM || currentMinutes < endM;
          }
          if (inSlot) {
            final greetings = slot['greetings'] as List<dynamic>?;
            if (greetings != null && greetings.isNotEmpty) {
              greeting = greetings.first.toString();
              break;
            }
          }
        }
      }
    }

    return _buildTile(
      targetId: 'home_text',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '首页文字',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                GestureDetector(
                  key: _navigationKey('home_text_advanced'),
                  onTap: () async {
                    final result = await _openSettingsPage<bool>(
                      'home_text_advanced',
                      HomeTextConfigPage(isEmbedded: widget.isEmbedded),
                      settings: const RouteSettings(name: '首页文字自定义'),
                    );
                    if (result == true && mounted) {
                      final newConfig =
                          await StorageService.getHomeTextConfig();
                      setState(() => _homeTextConfig = newConfig);
                    }
                  },
                  child: Row(
                    children: [
                      Text(
                        '高级设置',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              key: _navigationKey('home_text_preview'),
              onTap: () async {
                final result = await _openSettingsPage<bool>(
                  'home_text_preview',
                  HomeTextConfigPage(isEmbedded: widget.isEmbedded),
                  settings: const RouteSettings(name: '首页文字自定义'),
                );
                if (result == true && mounted) {
                  final newConfig = await StorageService.getHomeTextConfig();
                  setState(() => _homeTextConfig = newConfig);
                }
              },
              child: OptionalLiquidGlassCard(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                borderRadius: 16,
                highContrast: true,
                fallbackDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$salutation，${displayName.isEmpty ? "访客" : displayName}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '“ $greeting ”',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeLayoutSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildTile(
      targetId: 'home_layout',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '首页布局',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                GestureDetector(
                  key: _navigationKey('home_layout_advanced'),
                  onTap: () {
                    _openSettingsPage(
                      'home_layout_advanced',
                      HomeLayoutSettingsPage(isEmbedded: widget.isEmbedded),
                      settings: const RouteSettings(name: '首页布局'),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        '高级设置',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              key: _navigationKey('home_layout_preview'),
              onTap: () {
                _openSettingsPage(
                  'home_layout_preview',
                  HomeLayoutSettingsPage(isEmbedded: widget.isEmbedded),
                  settings: const RouteSettings(name: '首页布局'),
                );
              },
              child: OptionalLiquidGlassCard(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                borderRadius: 16,
                highContrast: true,
                fallbackDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiary.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Container(
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondary.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '组件排版与顺序',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '调整组件分组、顺序、显示状态和首页习惯展示数量',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarMenuSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildTile(
      targetId: 'sidebar_menu',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '侧边栏菜单',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                InkWell(
                  key: _navigationKey('sidebar_menu_advanced'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      _openSidebarMenuSettings('sidebar_menu_advanced'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '高级设置',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.primary,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: '配置侧边栏菜单',
              child: GestureDetector(
                key: _navigationKey('sidebar_menu_preview'),
                onTap: () => _openSidebarMenuSettings('sidebar_menu_preview'),
                child: OptionalLiquidGlassCard(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  borderRadius: 16,
                  highContrast: true,
                  fallbackDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildSidebarMenuPreview(colorScheme),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '功能入口与顺序',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '隐藏不常用功能，调整功能和工具入口的分组与顺序',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSidebarMenuSettings(String sourceId) {
    return _openSettingsPage(
      sourceId,
      SidebarMenuSettingsPage(isEmbedded: widget.isEmbedded),
      settings: const RouteSettings(name: '侧边栏菜单'),
    );
  }

  Widget _buildSidebarMenuPreview(ColorScheme colorScheme) {
    Widget menuLine({
      double width = double.infinity,
      bool highlighted = false,
    }) {
      return Container(
        width: width,
        height: 5,
        decoration: BoxDecoration(
          color: highlighted
              ? colorScheme.primary.withValues(alpha: 0.65)
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                menuLine(highlighted: true),
                menuLine(width: 15),
                menuLine(width: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== macOS 风格 Grouped Card 基础容器 =====
  Widget _buildMacGroupCard({
    required List<Widget> children,
    EdgeInsetsGeometry? margin,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262628) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildMacSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 28, right: 16, top: 22, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF98989D) : const Color(0xFF6C6C70),
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildMacDivider({double indent = 16, double endIndent = 16}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: indent,
      endIndent: endIndent,
      color: isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
    );
  }

  // ===== 外观行：浅色 / 深色 / 自动 Mini macOS 窗口微缩模型 =====
  Widget _buildAppearanceRow() {
    return _buildTile(
      targetId: 'theme',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 460;
            final miniatureRow = Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: isNarrow
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.end,
              children: [
                _buildAppearanceMiniature('light', '浅色'),
                const SizedBox(width: 14),
                _buildAppearanceMiniature('dark', '深色'),
                const SizedBox(width: 14),
                _buildAppearanceMiniature('system', '自动'),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '外观',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(child: miniatureRow),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '外观',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                miniatureRow,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppearanceMiniature(String value, String title) {
    final isSelected = _themeMode == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget previewContent;
    if (value == 'light') {
      previewContent = _buildLightWindowMiniature();
    } else if (value == 'dark') {
      previewContent = _buildDarkWindowMiniature();
    } else {
      // 自动模式：左右对半裁切
      previewContent = Row(
        children: [
          Expanded(child: _buildLightWindowMiniature(isLeftHalf: true)),
          Container(width: 1, color: Colors.black26),
          Expanded(child: _buildDarkWindowMiniature(isRightHalf: true)),
        ],
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() => _themeMode = value);
        StorageService.saveAppSetting(StorageService.keyThemeMode, value);
        StorageService.themeNotifier.value = value;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 96,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF007AFF)
                    : (isDark
                          ? const Color(0x26FFFFFF)
                          : const Color(0x1A000000)),
                width: isSelected ? 2.5 : 1.2,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: const Color(0xFF007AFF).withValues(alpha: 0.35),
                    blurRadius: 7,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: previewContent,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? (isDark ? Colors.white : const Color(0xFF007AFF))
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLightWindowMiniature({
    bool isLeftHalf = false,
    bool isRightHalf = false,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF68B2FF), Color(0xFF2C82F6), Color(0xFF1B62D6)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: isRightHalf ? -10 : 8,
            right: isLeftHalf ? -10 : 8,
            top: 10,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEDEDF2),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!isRightHalf) ...[
                          _buildTrafficDot(const Color(0xFFFF5F56)),
                          const SizedBox(width: 2.5),
                          _buildTrafficDot(const Color(0xFFFFBD2E)),
                          const SizedBox(width: 2.5),
                          _buildTrafficDot(const Color(0xFF27C93F)),
                          const Spacer(),
                        ],
                        Container(
                          width: 20,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1D1D6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (!isRightHalf)
                          Container(width: 16, color: const Color(0xFFF2F2F7)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF007AFF)
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  width: 32,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD1D1D6),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDarkWindowMiniature({
    bool isLeftHalf = false,
    bool isRightHalf = false,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E284A), Color(0xFF141A32), Color(0xFF0C1020)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: isRightHalf ? -10 : 8,
            right: isLeftHalf ? -10 : 8,
            top: 10,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(5),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!isRightHalf) ...[
                          _buildTrafficDot(const Color(0xFFFF5F56)),
                          const SizedBox(width: 2.5),
                          _buildTrafficDot(const Color(0xFFFFBD2E)),
                          const SizedBox(width: 2.5),
                          _buildTrafficDot(const Color(0xFF27C93F)),
                          const Spacer(),
                        ],
                        Container(
                          width: 20,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF48484A),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (!isRightHalf)
                          Container(width: 16, color: const Color(0xFF282828)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF007AFF)
                                        .withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  width: 32,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF48484A),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficDot(Color color) {
    return Container(
      width: 3.5,
      height: 3.5,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildOledBlackRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(
          Icons.brightness_2_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('纯黑 OLED 省电模式'),
        subtitle: Text(_oledBlackModeEnabled ? '深色界面使用纯黑背景' : '深色界面使用柔和深灰背景'),
        value: _oledBlackModeEnabled,
        onChanged: (enabled) {
          setState(() => _oledBlackModeEnabled = enabled);
          StorageService.oledBlackModeNotifier.value = enabled;
          unawaited(
            StorageService.saveAppSetting(
              StorageService.keyOledBlackMode,
              enabled,
            ),
          );
        },
      ),
    );
  }

  // ===== 主题颜色行：多色 SweepGradient + 苹果 8 种原生色 + 自定义 + 相册取色 =====
  Widget _buildColorSection() {
    final allPresetColors = [
      const Color(0xFF007AFF), // Blue
      const Color(0xFFAF52DE), // Purple
      const Color(0xFFFF2D55), // Pink
      const Color(0xFFFF3B30), // Red
      const Color(0xFFFF9500), // Orange
      const Color(0xFFFFCC00), // Yellow
      const Color(0xFF34C759), // Green
      const Color(0xFF8E8E93), // Grey
    ];

    return _buildTile(
      targetId: 'theme_color',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 450;
            final swatches = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMacColorDot(
                    mode: 'system_wallpaper',
                    color: null,
                    label: '多色',
                    isSelected:
                        _themeColorMode == 'system_wallpaper' ||
                        _themeColorMode == 'default',
                    onTap: () async {
                      await StorageService.setThemeColorMode(
                        'system_wallpaper',
                      );
                      setState(() => _themeColorMode = 'system_wallpaper');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildMacColorDot(
                    mode: 'app_wallpaper',
                    color: null,
                    label: '壁纸',
                    isSelected: _themeColorMode == 'app_wallpaper',
                    onTap: () async {
                      await StorageService.setThemeColorMode('app_wallpaper');
                      setState(() => _themeColorMode = 'app_wallpaper');
                    },
                  ),
                  const SizedBox(width: 8),
                  ...allPresetColors.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _buildMacColorDot(
                        mode: 'custom',
                        color: c,
                        label: null,
                        isSelected:
                            (_themeColorMode == 'custom') &&
                            _customThemeColor?.toARGB32() == c.toARGB32(),
                        onTap: () async {
                          await StorageService.setCustomThemeColor(c);
                          await StorageService.setThemeColorMode('custom');
                          setState(() {
                            _customThemeColor = c;
                            _themeColorMode = 'custom';
                          });
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildMacColorDot(
                      mode: 'custom_picker',
                      color: null,
                      label: '自选',
                      isSelected:
                          (_themeColorMode == 'custom') &&
                          _customThemeColor != null &&
                          !allPresetColors.any(
                            (c) =>
                                c.toARGB32() == _customThemeColor!.toARGB32(),
                          ),
                      onTap: _handlePickCustomThemeColor,
                    ),
                  ),
                  _buildMacColorDot(
                    mode: 'image_extracted',
                    color: null,
                    label: '取色',
                    isSelected: _themeColorMode == 'image_extracted',
                    onTap: () =>
                        _handleThemeColorModeChanged('image_extracted'),
                  ),
                ],
              ),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主题颜色',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  swatches,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '主题颜色',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: swatches,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMacColorDot({
    required String mode,
    required Color? color,
    required String? label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget dotContent;
    if (mode == 'system_wallpaper') {
      dotContent = Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Color(0xFFFF3B30),
              Color(0xFFFF9500),
              Color(0xFFFFCC00),
              Color(0xFF34C759),
              Color(0xFF007AFF),
              Color(0xFFAF52DE),
              Color(0xFFFF2D55),
              Color(0xFFFF3B30),
            ],
          ),
        ),
      );
    } else if (mode == 'custom_picker') {
      dotContent = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
        ),
        child: Icon(
          Icons.colorize_rounded,
          size: 13,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      );
    } else if (mode == 'app_wallpaper') {
      dotContent = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
        ),
        child: Icon(
          Icons.wallpaper_rounded,
          size: 13,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      );
    } else if (mode == 'image_extracted') {
      dotContent = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
        ),
        child: Icon(
          Icons.image_search_rounded,
          size: 13,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      );
    } else {
      dotContent = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? const Color(0xFF007AFF),
        ),
      );
    }

    final activeColor = (mode == 'system_wallpaper' || color == null)
        ? const Color(0xFF007AFF)
        : color;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? activeColor : Colors.transparent,
                width: 2.0,
              ),
            ),
            child: Container(
              width: isSelected ? 18 : 22,
              height: isSelected ? 18 : 22,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: dotContent,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? const Color(0xFF8E8E93)
                    : const Color(0xFF6C6C70),
              ),
            ),
          ] else
            const SizedBox(height: 15),
        ],
      ),
    );
  }
}
