import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../storage_service.dart';
import '../../../utils/page_transitions.dart';
import '../server_choice_page.dart';
import '../wallpaper_settings_page.dart';
import '../home_text_config_page.dart';
import '../../feature_guide_screen.dart';
import '../handlers/storage_management_handler.dart';
import '../dialogs/migration_dialog.dart';
import '../../../update_service.dart';
import '../../../utils/theme_color_tokens.dart';

class PreferenceSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const PreferenceSettingsPage(
      {super.key, this.initialTarget, this.isEmbedded = false});

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
    'migration': GlobalKey(),
    'cache': GlobalKey(),
    'storage': GlobalKey(),
    'update': GlobalKey(),
    'feature_guide': GlobalKey(),
  };

  bool _isLoading = true;
  String? _highlightTarget;

  String _themeMode = 'system';
  String _themeColorMode = 'default';
  Color? _customThemeColor;
  String _wallpaperProvider = 'bing';
  Map<String, dynamic> _homeTextConfig = {};
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
      showMessage: (msg) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg))),
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
    String themeColorMode =
        prefs.getString(StorageService.KEY_THEME_COLOR_MODE) ?? 'default';
    int? customColorVal = prefs.getInt(StorageService.KEY_CUSTOM_THEME_COLOR);
    String wallpaperProvider = await StorageService.getWallpaperProvider();
    Map<String, dynamic> homeTextConfig =
        await StorageService.getHomeTextConfig();

    if (mounted) {
      setState(() {
        _themeMode = theme;
        _themeColorMode = themeColorMode;
        _wallpaperProvider = wallpaperProvider;
        _homeTextConfig = homeTextConfig;
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
          final colorScheme = await ColorScheme.fromImageProvider(
              provider: FileImage(File(image.path)));
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
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('系统与外观'),
            ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          _buildWallpaperSection(),
          const Divider(height: 1, indent: 56),
          _buildHomeTextSection(),
          _buildAppearanceSection(),
          _buildColorSection(),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('系统与存储',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant)),
          ),
          _buildTile(
            targetId: 'cache',
            child: ListTile(
              leading: Icon(Icons.cleaning_services_outlined,
                  color: colorScheme.secondary),
              title: const Text('深度清理缓存与冗余'),
              subtitle: const Text('包含更新残留包与深度图片缓存'),
              trailing: Text(_cacheSizeStr,
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
              onTap: _storageManagementHandler.clearCache,
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'storage',
            child: ListTile(
              leading: Icon(Icons.data_usage, color: colorScheme.cdtWarning),
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
              leading: Icon(Icons.system_update_outlined,
                  color: colorScheme.cdtSuccess),
              title: const Text('检查新版本'),
              trailing: _isCheckingUpdate
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: _isCheckingUpdate ? null : _checkUpdatesAndNotices,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 8.0, top: 24.0),
            child: Text('其他工具',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant)),
          ),
          _buildTile(
            targetId: 'feature_guide',
            child: ListTile(
              leading: Icon(Icons.school_outlined, color: colorScheme.primary),
              title: const Text('重新查看新版教程与权限设置'),
              subtitle: const Text('可再次查看功能介绍与重新配置各项权限'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  PageTransitions.slideHorizontal(FeatureGuideScreen(
                    isManualReview: true,
                    loggedInUser: _username,
                  )),
                );
              },
            ),
          ),
          const Divider(height: 1, indent: 72),
          _buildTile(
            targetId: 'migration',
            child: ListTile(
              leading: Icon(Icons.move_to_inbox, color: colorScheme.secondary),
              title: const Text('旧版本地数据一键迁移'),
              subtitle: const Text('包含待办、课程、课表与习惯数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showMigrationDialog,
            ),
          ),
          const SizedBox(height: 32),
        ],
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
                Text('首页壁纸',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    PageTransitions.slideHorizontal(
                      WallpaperSettingsPage(isEmbedded: widget.isEmbedded),
                      settings: const RouteSettings(name: '首页壁纸设置'),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text('高级设置',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary)),
                      Icon(Icons.chevron_right,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary),
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
                const SizedBox(width: 24),
                _buildWallpaperCard(
                    'custom', '自定义图片', Icons.folder_special_outlined),
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
                      spreadRadius: 1)
              ],
            ),
            child: Center(
              child: Icon(icon,
                  size: 28,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : null,
              )),
        ],
      ),
    );
  }

  Widget _buildHomeTextSection() {
    final now = DateTime.now();

    final usernameFormat =
        _homeTextConfig['usernameFormat'] as String? ?? '{name}';
    final displayName = usernameFormat.replaceAll(
        '{name}', _username.isNotEmpty ? _username : '用户');

    final dateFormat =
        _homeTextConfig['dateFormat'] as String? ?? 'MM月dd日 EEEE';
    String dateStr;
    try {
      dateStr = DateFormat(dateFormat, 'zh_CN').format(now);
    } catch (_) {
      dateStr = DateFormat('MM月dd日 EEEE', 'zh_CN').format(now);
    }

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
        if (hour >= 5 && hour < 12)
          salutation = '上午好';
        else if (hour >= 12 && hour < 14)
          salutation = '中午好';
        else if (hour >= 14 && hour < 18)
          salutation = '下午好';
        else if (hour >= 18 && hour < 23)
          salutation = '晚上好';
        else
          salutation = '夜深了';
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
                Text('首页文字',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      PageTransitions.slideHorizontal(
                        HomeTextConfigPage(isEmbedded: widget.isEmbedded),
                        settings: const RouteSettings(name: '首页文字自定义'),
                      ),
                    );
                    if (result == true && mounted) {
                      final newConfig =
                          await StorageService.getHomeTextConfig();
                      setState(() => _homeTextConfig = newConfig);
                    }
                  },
                  child: Row(
                    children: [
                      Text('高级设置',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary)),
                      Icon(Icons.chevron_right,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push<bool>(
                  context,
                  PageTransitions.slideHorizontal(
                    HomeTextConfigPage(isEmbedded: widget.isEmbedded),
                    settings: const RouteSettings(name: '首页文字自定义'),
                  ),
                );
                if (result == true && mounted) {
                  final newConfig = await StorageService.getHomeTextConfig();
                  setState(() => _homeTextConfig = newConfig);
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '$salutation，${displayName.isEmpty ? "访客" : displayName}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(dateStr,
                        style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('“ $greeting ”',
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.primary,
                              fontStyle: FontStyle.italic)),
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

  Widget _buildAppearanceSection() {
    return _buildTile(
      targetId: 'theme',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildAppearanceCard('system', '自动', _buildAutoIcon()),
                const SizedBox(width: 24),
                _buildAppearanceCard('light', '浅色', _buildLightIcon()),
                const SizedBox(width: 24),
                _buildAppearanceCard('dark', '深色', _buildDarkIcon()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard(String value, String title, Widget icon) {
    final isSelected = _themeMode == value;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        setState(() => _themeMode = value);
        StorageService.saveAppSetting(StorageService.KEY_THEME_MODE, value);
        StorageService.themeNotifier.value = value;
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
                      spreadRadius: 1)
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: icon,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : null,
              )),
        ],
      ),
    );
  }

  Widget _buildLightIcon() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Column(
        children: [
          Container(height: 14, color: colorScheme.surfaceContainerHighest),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Row(
                children: [
                  Expanded(
                      flex: 1,
                      child: Container(
                          color: colorScheme.surfaceContainerHigh,
                          margin: const EdgeInsets.only(right: 4))),
                  Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(2)),
                      )),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDarkIcon() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.inverseSurface,
      child: Column(
        children: [
          Container(
              height: 14,
              color: colorScheme.inversePrimary.withValues(alpha: 0.28)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Row(
                children: [
                  Expanded(
                      flex: 1,
                      child: Container(
                          color: colorScheme.onInverseSurface
                              .withValues(alpha: 0.14),
                          margin: const EdgeInsets.only(right: 4))),
                  Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                            color: colorScheme.inversePrimary,
                            borderRadius: BorderRadius.circular(2)),
                      )),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildAutoIcon() {
    return Row(
      children: [
        Expanded(child: _buildLightIcon()),
        Expanded(child: _buildDarkIcon()),
      ],
    );
  }

  Widget _buildColorSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final allPresetColors = [
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.grey
    ];

    List<Color> displayColors;
    if (isMobile) {
      displayColors = [Colors.blue, Colors.purple, Colors.orange, Colors.green];
      if (_themeColorMode == 'custom' && _customThemeColor != null) {
        if (allPresetColors.any((c) => c.value == _customThemeColor!.value)) {
          if (!displayColors.any((c) => c.value == _customThemeColor!.value)) {
            displayColors[3] = _customThemeColor!;
          }
        }
      }
    } else {
      displayColors = allPresetColors;
    }

    return _buildTile(
      targetId: 'theme_color',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('主题颜色',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildColorCircle(
                        'system_wallpaper', null, '多色/自动', displayColors),
                    const SizedBox(width: 12),
                    _buildColorCircle(
                        'app_wallpaper', null, '应用壁纸', displayColors),
                    const SizedBox(width: 12),
                    ...displayColors.map((c) => Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: _buildColorCircle(
                              'custom', c, null, displayColors),
                        )),
                    _buildColorCircle(
                        'custom_picker', null, '自定义', displayColors),
                    const SizedBox(width: 12),
                    _buildColorCircle(
                        'image_extracted', null, '图片取色', displayColors),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorCircle(
      String mode, Color? color, String? label, List<Color> displayColors) {
    bool isSelected = false;

    if (mode == 'system_wallpaper') {
      isSelected =
          _themeColorMode == 'system_wallpaper' || _themeColorMode == 'default';
    } else if (mode == 'app_wallpaper') {
      isSelected = _themeColorMode == 'app_wallpaper';
    } else if (mode == 'custom' && color != null) {
      isSelected = (_themeColorMode == 'custom') &&
          _customThemeColor?.value == color.value;
    } else if (mode == 'custom_picker') {
      isSelected = (_themeColorMode == 'custom') &&
          !displayColors.any((c) => c.value == _customThemeColor?.value);
    } else if (mode == 'image_extracted') {
      isSelected = _themeColorMode == 'image_extracted';
    }

    Widget inner;
    if (mode == 'system_wallpaper') {
      inner = Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Colors.blue,
              Colors.purple,
              Colors.red,
              Colors.orange,
              Colors.yellow,
              Colors.green,
              Colors.blue
            ],
          ),
        ),
      );
    } else if (mode == 'app_wallpaper') {
      inner = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Icon(Icons.wallpaper,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    } else if (mode == 'custom_picker') {
      inner = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Icon(Icons.colorize,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    } else if (mode == 'image_extracted') {
      inner = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Icon(Icons.image,
            size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    } else {
      inner = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? Theme.of(context).colorScheme.primary,
        ),
      );
    }

    return GestureDetector(
      onTap: () async {
        if (mode == 'system_wallpaper' || mode == 'app_wallpaper') {
          await StorageService.setThemeColorMode(mode);
          setState(() => _themeColorMode = mode);
        } else if (mode == 'custom' && color != null) {
          await StorageService.setCustomThemeColor(color);
          await StorageService.setThemeColorMode('custom');
          setState(() {
            _customThemeColor = color;
            _themeColorMode = 'custom';
          });
        } else if (mode == 'custom_picker') {
          await _handlePickCustomThemeColor();
        } else if (mode == 'image_extracted') {
          await _handleThemeColorModeChanged('image_extracted');
        }
      },
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: inner,
            ),
            if (label != null) ...[
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ]
          ],
        ),
      ),
    );
  }
}
