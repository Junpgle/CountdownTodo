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
import '../../../services/notification_service.dart';
import '../../../services/window_service.dart';
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
    'mac_status_bar': GlobalKey(),
    'mac_island_shortcut': GlobalKey(),
    'mac_island_reminders': GlobalKey(),
    'mac_island_clipboard_links': GlobalKey(),
    'mac_island_without_notch': GlobalKey(),
    'mac_island_test': GlobalKey(),
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
  bool _macIslandEnabled = true;
  bool _macIslandRemindersEnabled = true;
  bool _macIslandClipboardLinksEnabled = true;
  bool _macIslandShowWithoutNotch = true;
  String _macIslandShortcutKey = '';
  bool _macIslandShortcutCommand = false;
  bool _macIslandShortcutOption = false;
  bool _macIslandShortcutControl = false;
  bool _macIslandShortcutShift = false;

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
          _macIslandEnabled = prefs.getBool('macos_island_enabled') ??
              prefs.getBool('macos_status_bar_enabled') ??
              true;
          _macIslandShowWithoutNotch =
              prefs.getBool('macos_island_show_without_notch') ?? true;
          _macIslandRemindersEnabled =
              prefs.getBool('macos_island_reminders_enabled') ?? true;
          _macIslandClipboardLinksEnabled =
              prefs.getBool('macos_island_clipboard_links_enabled') ?? true;
          _macIslandShortcutKey =
              prefs.getString('macos_island_shortcut_key') ?? '';
          _macIslandShortcutCommand =
              prefs.getBool('macos_island_shortcut_command') ?? false;
          _macIslandShortcutOption =
              prefs.getBool('macos_island_shortcut_option') ?? false;
          _macIslandShortcutControl =
              prefs.getBool('macos_island_shortcut_control') ?? false;
          _macIslandShortcutShift =
              prefs.getBool('macos_island_shortcut_shift') ?? false;
        });
      }
    }
  }

  _MacIslandShortcut get _macIslandShortcut => _MacIslandShortcut(
        key: _macIslandShortcutKey,
        command: _macIslandShortcutCommand,
        option: _macIslandShortcutOption,
        control: _macIslandShortcutControl,
        shift: _macIslandShortcutShift,
      );

  Future<void> _editMacIslandShortcut() async {
    final shortcut = await showDialog<_MacIslandShortcut>(
      context: context,
      builder: (context) =>
          _MacIslandShortcutDialog(initialShortcut: _macIslandShortcut),
    );
    if (shortcut == null || !mounted) return;

    final registered = await WindowService.setMacIslandVisibilityShortcut(
      key: shortcut.key,
      command: shortcut.command,
      option: shortcut.option,
      control: shortcut.control,
      shift: shortcut.shift,
    );
    if (!registered) {
      if (mounted) {
        AppSnackBars.error(context, '快捷键已被其他应用占用，请换一个组合');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('macos_island_shortcut_key', shortcut.key),
      prefs.setBool('macos_island_shortcut_command', shortcut.command),
      prefs.setBool('macos_island_shortcut_option', shortcut.option),
      prefs.setBool('macos_island_shortcut_control', shortcut.control),
      prefs.setBool('macos_island_shortcut_shift', shortcut.shift),
    ]);
    if (!mounted) return;
    setState(() {
      _macIslandShortcutKey = shortcut.key;
      _macIslandShortcutCommand = shortcut.command;
      _macIslandShortcutOption = shortcut.option;
      _macIslandShortcutControl = shortcut.control;
      _macIslandShortcutShift = shortcut.shift;
    });
    AppSnackBars.success(
      context,
      shortcut.isEmpty ? '已清除灵动岛隐藏快捷键' : '快捷键已设为 ${shortcut.displayText}',
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
              title: 'Mac 灵动岛',
              padding: EdgeInsets.only(left: 16, bottom: 8, top: 16),
            ),
            _buildTile(
              targetId: 'mac_status_bar',
              child: ListTile(
                leading: Icon(Icons.call_to_action_rounded,
                    color: colorScheme.primary),
                title: const Text('启用刘海灵动岛'),
                subtitle: const Text('专注时在屏幕顶部显示倒计时，菜单栏不再显示应用图标'),
                trailing: Switch(
                  value: _macIslandEnabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (val) async {
                    setState(() => _macIslandEnabled = val);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('macos_island_enabled', val);
                    await prefs.setBool('macos_tray_icon_enabled', false);
                    await WindowService.configureMacIsland();
                    if (!val) {
                      MacPomodoroStatusBarService.clearNative();
                    } else {
                      await MacPomodoroStatusBarService.syncCurrentStatus();
                    }
                    if (!context.mounted) return;
                    AppSnackBars.success(
                        context, val ? 'Mac 灵动岛已开启' : 'Mac 灵动岛已关闭');
                  },
                ),
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_island_shortcut',
              child: ListTile(
                enabled: _macIslandEnabled,
                leading: Icon(
                  Icons.keyboard_command_key_rounded,
                  color: _macIslandEnabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                title: const Text('隐藏/恢复灵动岛快捷键'),
                subtitle: Text(
                  _macIslandShortcut.isEmpty
                      ? '未设置；设置全局快捷键后可临时让出菜单栏空间'
                      : '按 ${_macIslandShortcut.displayText} 隐藏，再按一次恢复',
                ),
                trailing: OutlinedButton(
                  onPressed: _macIslandEnabled ? _editMacIslandShortcut : null,
                  child: Text(_macIslandShortcut.isEmpty ? '设置' : '修改'),
                ),
                onTap: _macIslandEnabled ? _editMacIslandShortcut : null,
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_island_reminders',
              child: ListTile(
                leading: Icon(Icons.notifications_active_outlined,
                    color: colorScheme.primary),
                title: const Text('在灵动岛显示提醒'),
                subtitle: const Text('待办、课程和计划到点时自动展开，支持稍后提醒'),
                trailing: Switch(
                  value: _macIslandRemindersEnabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: _macIslandEnabled
                      ? (val) async {
                          setState(() => _macIslandRemindersEnabled = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(
                              'macos_island_reminders_enabled', val);
                          await WindowService.configureMacIsland();
                          if (val) {
                            final reminders = await NotificationService
                                .getScheduledReminders();
                            await MacPomodoroStatusBarService
                                .scheduleIslandReminders(
                              reminders,
                              clearFirst: true,
                              restoring: true,
                            );
                          } else {
                            MacPomodoroStatusBarService.clearIslandReminders();
                          }
                        }
                      : null,
                ),
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_island_clipboard_links',
              child: ListTile(
                enabled: _macIslandEnabled,
                leading: Icon(
                  Icons.link_rounded,
                  color: _macIslandEnabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                title: const Text('检测剪贴板网址'),
                subtitle: const Text('复制网页链接时短暂展开灵动岛，可确认后用浏览器打开'),
                trailing: Switch(
                  value: _macIslandClipboardLinksEnabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: _macIslandEnabled
                      ? (val) async {
                          setState(() => _macIslandClipboardLinksEnabled = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(
                              'macos_island_clipboard_links_enabled', val);
                          await WindowService.configureMacIsland();
                        }
                      : null,
                ),
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_island_test',
              child: ListTile(
                enabled: _macIslandEnabled && _macIslandRemindersEnabled,
                leading: Icon(Icons.play_circle_outline_rounded,
                    color: _macIslandEnabled && _macIslandRemindersEnabled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant),
                title: const Text('测试灵动岛提醒'),
                subtitle: const Text('立即显示一条测试提醒，用于检查位置和交互'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _macIslandEnabled && _macIslandRemindersEnabled
                    ? () async {
                        await MacPomodoroStatusBarService.showTestReminder();
                      }
                    : null,
              ),
            ),
            const AppSettingsDivider(indent: 72),
            _buildTile(
              targetId: 'mac_island_without_notch',
              child: ListTile(
                leading:
                    Icon(Icons.desktop_mac_rounded, color: colorScheme.primary),
                title: const Text('无刘海屏幕也显示'),
                subtitle: const Text('在外接显示器或无刘海 Mac 顶部显示居中胶囊'),
                trailing: Switch(
                  value: _macIslandShowWithoutNotch,
                  activeThumbColor: colorScheme.primary,
                  onChanged: _macIslandEnabled
                      ? (val) async {
                          setState(() => _macIslandShowWithoutNotch = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(
                              'macos_island_show_without_notch', val);
                          await WindowService.configureMacIsland();
                        }
                      : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MacIslandShortcut {
  const _MacIslandShortcut({
    required this.key,
    required this.command,
    required this.option,
    required this.control,
    required this.shift,
  });

  const _MacIslandShortcut.empty()
      : key = '',
        command = false,
        option = false,
        control = false,
        shift = false;

  final String key;
  final bool command;
  final bool option;
  final bool control;
  final bool shift;

  bool get isEmpty => key.isEmpty;
  bool get hasGlobalModifier => command || option || control;

  String get displayText {
    if (isEmpty) return '未设置';
    final buffer = StringBuffer();
    if (control) buffer.write('⌃');
    if (option) buffer.write('⌥');
    if (shift) buffer.write('⇧');
    if (command) buffer.write('⌘');
    buffer.write(key);
    return buffer.toString();
  }
}

class _MacIslandShortcutDialog extends StatefulWidget {
  const _MacIslandShortcutDialog({required this.initialShortcut});

  final _MacIslandShortcut initialShortcut;

  @override
  State<_MacIslandShortcutDialog> createState() =>
      _MacIslandShortcutDialogState();
}

class _MacIslandShortcutDialogState extends State<_MacIslandShortcutDialog> {
  late final FocusNode _focusNode;
  late _MacIslandShortcut _shortcut;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'macIslandShortcutRecorder');
    _shortcut = widget.initialShortcut;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String? _normalizedKey(LogicalKeyboardKey logicalKey) {
    final label = logicalKey.keyLabel.toUpperCase();
    if (RegExp(r'^[A-Z0-9]$').hasMatch(label)) return label;
    if (RegExp(r'^F(?:[1-9]|1[0-2])$').hasMatch(label)) return label;
    return null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = _normalizedKey(event.logicalKey);
    if (key == null) return;

    final keyboard = HardwareKeyboard.instance;
    final shortcut = _MacIslandShortcut(
      key: key,
      command: keyboard.isMetaPressed,
      option: keyboard.isAltPressed,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
    );
    if (!shortcut.hasGlobalModifier) {
      setState(() => _validationMessage = '请至少同时按住 ⌘、⌥ 或 ⌃ 中的一个；⇧ 不能单独使用');
      return;
    }
    setState(() {
      _shortcut = shortcut;
      _validationMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('设置灵动岛快捷键'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('按下“修饰键 + 字母、数字或 F1–F12”。快捷键在其他 App 中也能使用。'),
            const SizedBox(height: 16),
            KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _focusNode.requestFocus,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    _shortcut.isEmpty ? '请按快捷键' : _shortcut.displayText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: _shortcut.isEmpty
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationMessage!,
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.initialShortcut.isEmpty)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _MacIslandShortcut.empty(),
            ),
            child: const Text('清除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _shortcut.isEmpty
              ? null
              : () => Navigator.pop(context, _shortcut),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
