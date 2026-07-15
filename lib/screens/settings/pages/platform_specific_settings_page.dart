import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import '../../../utils/app_platform.dart';
import '../../../services/tai_service.dart';
import '../../../storage_service.dart';
import '../../../services/float_window_service.dart';
import '../../../services/island_manager_bridge.dart';
import '../../../services/island_data_provider.dart';
import '../../../services/macos_pomodoro_status_bar_service.dart';
import '../../../services/permission_request_coordinator.dart';
import '../../../utils/app_dialogs.dart';
import '../../../utils/theme_color_tokens.dart';
import '../../../widgets/app_settings_widgets.dart';
import '../../../widgets/app_state_views.dart';
import '../dialogs/island_priority_dialog.dart';

class PlatformSpecificSettingsPage extends StatefulWidget {
  final String? initialTarget;
  final bool isEmbedded;
  const PlatformSpecificSettingsPage(
      {super.key, this.initialTarget, this.isEmbedded = false});

  @override
  State<PlatformSpecificSettingsPage> createState() =>
      _PlatformSpecificSettingsPageState();
}

class _PlatformSpecificSettingsPageState
    extends State<PlatformSpecificSettingsPage> {
  static const platform =
      MethodChannel('com.math_quiz.junpgle.com.math_quiz_app/notifications');

  final Map<String, GlobalKey> _itemKeys = {
    'float_window_style': GlobalKey(),
    'force_refresh': GlobalKey(),
    'island_priority': GlobalKey(),
    'tai_db': GlobalKey(),
    'live_updates': GlobalKey(),
    'island_support': GlobalKey(),
    'test_notification': GlobalKey(),
    'mac_tray_icon': GlobalKey(),
    'mac_status_bar': GlobalKey(),
    'mac_icon_size': GlobalKey(),
  };

  String? _highlightTarget;

  // Windows Specific
  int _floatWindowStyle = 0;
  String _taiDbPath = '';

  // Android Specific
  String _islandStatus = "点击检测设备是否支持";
  String _liveUpdatesStatus = "点击检测或去开启 (Android 16+)";
  late final PermissionRequestCoordinator _permissionCoordinator;

  // macOS Specific
  bool _macTrayIconEnabled = true;
  bool _macStatusBarEnabled = true;
  int _macIconSize = 18;

  @override
  void initState() {
    super.initState();
    _permissionCoordinator = PermissionRequestCoordinator(
      context: context,
      platformChannel: platform,
    );
    _loadSettings();
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTarget(widget.initialTarget!);
      });
    }
  }

  @override
  void dispose() {
    _permissionCoordinator.dispose();
    super.dispose();
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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (AppPlatform.isWindows) {
      String? username = prefs.getString(StorageService.KEY_CURRENT_USER);
      int style = 0;
      if (username != null && username.isNotEmpty) {
        style = prefs.getInt('float_window_style_$username') ?? 0;
      }
      style = style == 0 ? (prefs.getInt('float_window_style') ?? 0) : style;

      final taiPath = await TaiService.getSavedDbPath() ??
          await TaiService.detectDefaultPath();
      if (taiPath != null) await TaiService.saveDbPath(taiPath);

      if (mounted) {
        setState(() {
          _floatWindowStyle = style;
          _taiDbPath = taiPath ?? '';
        });
      }
    }
    if (AppPlatform.isMacOS) {
      if (mounted) {
        setState(() {
          _macTrayIconEnabled = prefs.getBool('macos_tray_icon_enabled') ?? true;
          _macStatusBarEnabled = prefs.getBool('macos_status_bar_enabled') ?? true;
          _macIconSize = prefs.getInt('macos_tray_icon_size') ?? 18;
        });
      }
    }
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

  // --- Windows Methods ---
  Future<void> _pickTaiDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite'],
      dialogTitle: '选择 Tai 数据库文件',
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final valid = await TaiService.validateDb(path);

    if (!valid) {
      if (mounted) {
        AppSnackBars.error(context, '❌ 无效的 Tai 数据库文件');
      }
      return;
    }

    await TaiService.saveDbPath(path);
    setState(() => _taiDbPath = path);

    if (mounted) {
      AppSnackBars.success(context, '✅ 数据库路径已保存');
    }
  }

  void _showIslandPriorityDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const IslandPriorityDialog(),
    );
    if (changed == true) {
      if (mounted) {
        AppSnackBars.success(context, '✅ 灵动岛优先级已更新');
      }
      FloatWindowService.invalidateCache();
      Future.delayed(const Duration(milliseconds: 300), () async {
        if (!mounted) return;
        try {
          await FloatWindowService.update();
        } catch (e) {
          debugPrint('[Settings] Island priority refresh failed: $e');
        }
      });
    }
  }

  // --- Android Methods ---
  Future<void> _checkAndOpenLiveUpdates() async {
    try {
      final result =
          await _permissionCoordinator.request(AppPermissionKind.liveUpdates);
      if (!mounted) return;
      if (result.cancelledByUser) {
        setState(() => _liveUpdatesStatus = "用户暂未允许实时通知权限");
      } else if (result.granted) {
        setState(() => _liveUpdatesStatus = "✅ 已拥有实时通知权限");
      } else {
        setState(() => _liveUpdatesStatus = "权限仍未开启");
        AppSnackBars.warning(context, '尚未开启"推广的通知/实时更新"权限');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _liveUpdatesStatus = "检测失败: '${e.message}'.");
      }
    }
  }

  Future<void> _checkIslandSupport() async {
    try {
      final bool result = await platform.invokeMethod('checkIslandSupport');
      setState(() {
        if (result) {
          _islandStatus = "✅ 设备已支持超级岛！";
        } else {
          _islandStatus = "❌ 不支持，或未开启状态栏显示权限";
        }
      });
    } on PlatformException catch (e) {
      setState(() => _islandStatus = "检测失败: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String pageTitle = AppPlatform.isWindows
        ? 'Windows 专属设置'
        : (AppPlatform.isAndroid
            ? 'Android 专属整合'
            : (AppPlatform.isMacOS ? 'macOS 专属设置' : '平台专属设置'));

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(pageTitle),
            ),
      body: ListView(
        children: [
          if (!AppPlatform.isWindows &&
              !AppPlatform.isAndroid &&
              !AppPlatform.isMacOS) ...[
            const AppEmptyState(
              icon: Icons.stars_rounded,
              title: '当前平台无专属设置',
              message: '您的设备正在以最佳状态运行该应用，无需任何额外配置即可享受全部核心功能。',
              padding: EdgeInsets.only(top: 100, left: 32, right: 32),
            ),
          ],
          if (AppPlatform.isWindows) ...[
            const AppSettingsSectionHeader(
              title: '屏幕时间统计',
              padding: EdgeInsets.only(left: 16, bottom: 8, top: 16),
            ),
            _buildTile(
              targetId: 'tai_db',
              child: ListTile(
                leading: Icon(Icons.timer_outlined, color: colorScheme.primary),
                title: const Text('Tai 屏幕时间数据库'),
                subtitle: Text(
                  _taiDbPath.isEmpty ? '未设置，点击选择 data.db 文件' : _taiDbPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _taiDbPath.isEmpty
                        ? colorScheme.cdtWarning
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.folder_open_outlined),
                onTap: _pickTaiDatabase,
              ),
            ),
            const AppSettingsSectionHeader(
              title: '桌面挂件设置',
              padding: EdgeInsets.only(left: 16, bottom: 8, top: 24),
            ),
            _buildTile(
              targetId: 'float_window_style',
              child: ListTile(
                leading:
                    Icon(Icons.layers_outlined, color: colorScheme.primary),
                title: const Text('桌面灵动岛'),
                subtitle: const Text('开启灵动岛式浮动窗口'),
                trailing: Switch(
                  value: _floatWindowStyle != 2,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (val) async {
                    int newStyle = val ? 1 : 2;
                    setState(() => _floatWindowStyle = newStyle);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('float_window_style', newStyle);
                    if (newStyle == 2) {
                      try {
                        IslandDataProvider().invalidateCache();
                        IslandManagerBridge.clearIslandCache('island-1');
                      } catch (_) {
                        // Ignore cleanup failures; the setting value was saved.
                      }
                    } else {
                      try {
                        IslandDataProvider().invalidateCache();
                        IslandManagerBridge.clearIslandCache('island-1');
                        await IslandManagerBridge.createIsland('island-1');
                      } catch (_) {
                        // Ignore stale island window errors during style changes.
                      }
                      try {
                        await FloatWindowService.update(forceReset: true);
                      } catch (_) {
                        // The next island refresh will retry if this update fails.
                      }
                    }
                  },
                ),
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'force_refresh',
              child: ListTile(
                leading: Icon(Icons.refresh, color: colorScheme.primary),
                title: const Text('强制刷新悬浮窗位置'),
                subtitle: const Text('将灵动岛悬浮窗重置到屏幕中央'),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await StorageService.saveIslandBounds('island-1', {});
                    } catch (_) {}
                    try {
                      IslandDataProvider().invalidateCache();
                    } catch (_) {}
                    try {
                      IslandManagerBridge.clearIslandCache('island-1');
                    } catch (_) {}
                    try {
                      await FloatWindowService.update(forceReset: true);
                    } catch (_) {}
                  },
                  child: const Text('强制刷新'),
                ),
              ),
            ),
            if (_floatWindowStyle != 2) ...[
              const AppSettingsDivider(indent: 72),
              _buildTile(
                targetId: 'island_priority',
                child: ListTile(
                  leading:
                      Icon(Icons.priority_high, color: colorScheme.primary),
                  title: const Text('灵动岛优先级设置'),
                  subtitle: const Text('配置哪些应用可以抢占灵动岛显示'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showIslandPriorityDialog,
                ),
              ),
            ],
          ],
          if (AppPlatform.isAndroid) ...[
            const AppSettingsSectionHeader(
              title: 'Android 系统特性',
              padding: EdgeInsets.only(left: 16, bottom: 8, top: 16),
            ),
            _buildTile(
              targetId: 'live_updates',
              child: ListTile(
                leading: Icon(Icons.update, color: colorScheme.cdtSuccess),
                title: const Text('Android 16 实时活动 (Live Updates)'),
                subtitle: Text(_liveUpdatesStatus,
                    style: TextStyle(
                        color: _liveUpdatesStatus.contains('✅')
                            ? colorScheme.cdtSuccess
                            : colorScheme.cdtWarning,
                        fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _checkAndOpenLiveUpdates,
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'island_support',
              child: ListTile(
                leading: Icon(Icons.phone_android, color: colorScheme.primary),
                title: const Text('检测状态栏超级岛支持 (OriginOS/ColorOS等)'),
                subtitle: Text(_islandStatus,
                    style: TextStyle(
                        color: _islandStatus.contains('✅')
                            ? colorScheme.cdtSuccess
                            : colorScheme.cdtWarning,
                        fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _checkIslandSupport,
              ),
            ),
          ],
          if (AppPlatform.isMacOS) ...[
            const AppSettingsSectionHeader(
              title: '菜单栏设置',
              padding: EdgeInsets.only(left: 16, bottom: 8, top: 16),
            ),
            _buildTile(
              targetId: 'mac_tray_icon',
              child: ListTile(
                leading:
                    Icon(Icons.apps_rounded, color: colorScheme.primary),
                title: const Text('显示托盘图标'),
                subtitle: const Text('在菜单栏显示应用图标，支持右键菜单快捷操作'),
                trailing: Switch(
                  value: _macTrayIconEnabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (val) async {
                    setState(() => _macTrayIconEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('macos_tray_icon_enabled', val);
                    if (mounted) {
                      AppSnackBars.success(
                          context, '设置已保存，重启应用后生效');
                    }
                  },
                ),
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_status_bar',
              child: ListTile(
                leading:
                    Icon(Icons.timer_outlined, color: colorScheme.primary),
                title: const Text('显示专注计时'),
                subtitle:
                    const Text('专注时在菜单栏显示番茄钟倒计时，支持暂停/结束操作'),
                trailing: Switch(
                  value: _macStatusBarEnabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (val) async {
                    setState(() => _macStatusBarEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('macos_status_bar_enabled', val);
                    if (!val) {
                      MacPomodoroStatusBarService.clearNative();
                    }
                    if (mounted) {
                      AppSnackBars.success(context, val
                          ? '专注计时已开启，下次专注时生效'
                          : '专注计时已关闭');
                    }
                  },
                ),
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_icon_size',
              child: ListTile(
                leading:
                    Icon(Icons.photo_size_select_large, color: colorScheme.primary),
                title: const Text('托盘图标大小'),
                subtitle: Text('当前: $_macIconSize px',
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 12)),
                trailing: SizedBox(
                  width: 160,
                  child: Slider(
                    value: _macIconSize.toDouble(),
                    min: 12,
                    max: 28,
                    divisions: 16,
                    label: '$_macIconSize px',
                    activeColor: colorScheme.primary,
                    onChanged: (val) {
                      setState(() => _macIconSize = val.round());
                    },
                    onChangeEnd: (val) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt(
                          'macos_tray_icon_size', val.round());
                      if (mounted) {
                        AppSnackBars.success(
                            context, '设置已保存，重启应用后生效');
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
