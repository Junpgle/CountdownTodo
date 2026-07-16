import 'dart:async' show TimeoutException, Timer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../screens/home_settings_screen.dart';
import '../utils/page_transitions.dart';
import '../utils/navigator_utils.dart';

class WindowService extends WindowListener with TrayListener {
  static const _keyX = 'main_window_x';
  static const _keyY = 'main_window_y';
  static const _keyW = 'main_window_w';
  static const _keyH = 'main_window_h';
  static const double _minStartupWidth = 720;
  static const double _minStartupHeight = 480;

  static const MethodChannel _nativeChannel =
      MethodChannel('com.math_quiz_app/window_native');
  static const MethodChannel _macAppStatusBarChannel =
      MethodChannel('countdown_todo/macos_app_status_bar');

  static Timer? _debounce;
  static Rect? _startupBounds;
  static bool _suppressBoundsSave = false;
  static bool _macIslandInitialized = false;

  static final WindowService _instance = WindowService._internal();

  WindowService._internal();

  static Future<void> init() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      debugPrint('[WindowService] Initializing...');
      await windowManager.ensureInitialized();
      debugPrint('[WindowService] windowManager.ensureInitialized() done');

      await windowManager.setPreventClose(true);
      debugPrint('[WindowService] windowManager.setPreventClose(true) done');

      final prefs = await SharedPreferences.getInstance();
      final int? x = prefs.getInt(_keyX);
      final int? y = prefs.getInt(_keyY);
      final int? w = prefs.getInt(_keyW);
      final int? h = prefs.getInt(_keyH);
      if (x != null && y != null && w != null && h != null) {
        final bounds = Rect.fromLTWH(
            x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
        if (_isUsableBounds(bounds)) {
          _startupBounds = bounds;
        }
      }

      windowManager.addListener(_instance);
      debugPrint('[WindowService] windowManager.addListener(_instance) done');
      if (Platform.isMacOS) {
        _macAppStatusBarChannel.setMethodCallHandler(_handleMacStatusBarCall);
      }

      if (Platform.isWindows) {
        await _initTray();
      }
      if (Platform.isWindows || Platform.isMacOS) {
        await _initLaunchAtStartup();
      }
      debugPrint('[WindowService] Initialization complete!');
    } catch (e) {
      debugPrint('[WindowService] init error: $e');
    }
  }

  static Future<void> initMacIslandAfterWindowReady() async {
    if (!Platform.isMacOS || _macIslandInitialized) return;
    _macIslandInitialized = true;
    debugPrint('[WindowService] macOS island initialization starting');
    await configureMacIsland();
  }

  static Future<void> configureMacIsland() async {
    if (!Platform.isMacOS) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('macos_island_enabled') ??
        prefs.getBool('macos_status_bar_enabled') ??
        true;
    final showOnNotchlessDisplay =
        prefs.getBool('macos_island_show_without_notch') ?? true;
    final remindersEnabled =
        prefs.getBool('macos_island_reminders_enabled') ?? true;
    await _macAppStatusBarChannel.invokeMethod('configureIsland', {
      'enabled': enabled,
      'showOnNotchlessDisplay': showOnNotchlessDisplay,
      'remindersEnabled': remindersEnabled,
    });
    final shortcutRegistered = await setMacIslandVisibilityShortcut(
      key: enabled ? (prefs.getString('macos_island_shortcut_key') ?? '') : '',
      command: prefs.getBool('macos_island_shortcut_command') ?? false,
      option: prefs.getBool('macos_island_shortcut_option') ?? false,
      control: prefs.getBool('macos_island_shortcut_control') ?? false,
      shift: prefs.getBool('macos_island_shortcut_shift') ?? false,
    );
    if (!shortcutRegistered) {
      debugPrint('[WindowService] macOS island shortcut registration failed');
    }
  }

  static Future<bool> setMacIslandVisibilityShortcut({
    required String key,
    required bool command,
    required bool option,
    required bool control,
    required bool shift,
  }) async {
    if (!Platform.isMacOS) return false;
    try {
      return await _macAppStatusBarChannel.invokeMethod<bool>(
            'setIslandVisibilityShortcut',
            {
              'key': key,
              'command': command,
              'option': option,
              'control': control,
              'shift': shift,
            },
          ) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('[WindowService] set macOS island shortcut failed: $error');
      return false;
    }
  }

  static Future<void> _initTray() async {
    try {
      debugPrint(
          '[WindowService] _initTray: starting, iconPath=${Platform.isWindows ? 'assets/icon/app_icon.ico' : 'assets/icon/app_icon.png'}');
      trayManager.addListener(_instance);
      await _setTrayIcon();
      debugPrint('[WindowService] _initTray: setIcon done');
      await trayManager.setToolTip('CountDownTodo');
      await _updateTrayMenu();
      if (Platform.isMacOS) {
        Future<void>.delayed(const Duration(milliseconds: 800), () async {
          await _setTrayIcon();
          await trayManager.setToolTip('CountDownTodo');
          await _updateTrayMenu();
          debugPrint('[WindowService] _initTray: macOS delayed refresh done');
        });
      }
      debugPrint('[WindowService] _initTray: complete');
    } catch (e) {
      debugPrint('[WindowService] initTray error: $e');
    }
  }

  static Future<void> _setTrayIcon() {
    if (Platform.isMacOS) {
      return trayManager.setIcon('assets/icon/app_icon.png');
    }
    return trayManager.setIcon(
      'assets/icon/app_icon.ico',
      iconSize: 18,
    );
  }

  static Future<void> _updateTrayMenu() async {
    try {
      bool isLaunchAtStartup = false;
      try {
        isLaunchAtStartup = await launchAtStartup.isEnabled();
      } catch (_) {
        // macOS 可能不支持 isEnabled
      }
      Menu menu = Menu(
        items: [
          MenuItem(
            key: 'open_settings',
            label: '打开设置',
          ),
          MenuItem(
            key: 'auto_launch',
            label: isLaunchAtStartup ? '开机自启动: 已开启' : '开机自启动: 已关闭',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'show_window',
            label: '显示程序',
          ),
          MenuItem(
            key: 'exit_app',
            label: '退出程序',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('[WindowService] updateTrayMenu error: $e');
    }
  }

  static Future<dynamic> _handleMacStatusBarCall(MethodCall call) async {
    switch (call.method) {
      case 'openSettings':
        await windowManager.show();
        await windowManager.focus();
        appNavigatorKey.currentState?.push(
          PageTransitions.slideHorizontal(const SettingsPage()),
        );
        return true;
      default:
        return null;
    }
  }

  static Future<void> _initLaunchAtStartup() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
      );
    } catch (e) {
      debugPrint('[WindowService] initLaunchAtStartup error: $e');
    }
  }

  static bool _isUsableBounds(Rect bounds) {
    return bounds.left.isFinite &&
        bounds.top.isFinite &&
        bounds.width.isFinite &&
        bounds.height.isFinite &&
        bounds.width >= _minStartupWidth &&
        bounds.height >= _minStartupHeight;
  }

  static Future<void> restoreStartupBoundsAndRepairViewport() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    final bounds = _startupBounds;
    if (bounds == null || !_isUsableBounds(bounds)) return;

    try {
      _suppressBoundsSave = true;
      await windowManager.setBounds(bounds);

      if (Platform.isWindows) {
        final nudged = Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width + 1,
          bounds.height,
        );
        await windowManager.setBounds(nudged);
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await windowManager.setBounds(bounds);
      }
    } catch (e) {
      debugPrint('[WindowService] restore startup bounds failed: $e');
    } finally {
      _suppressBoundsSave = false;
    }
  }

  static void schedulePostShowViewportRepair() {
    if (!Platform.isWindows) return;
    for (final delay in const [
      Duration(milliseconds: 80),
      Duration(milliseconds: 300),
      Duration(milliseconds: 900),
    ]) {
      Future<void>.delayed(delay, () async {
        await _nudgeCurrentBoundsForViewportRepair();
      });
    }
  }

  static Future<void> _nudgeCurrentBoundsForViewportRepair() async {
    try {
      final bounds = await windowManager.getBounds();
      if (!_isUsableBounds(bounds)) return;

      _suppressBoundsSave = true;
      final nudged = Rect.fromLTWH(
        bounds.left,
        bounds.top,
        bounds.width + 1,
        bounds.height,
      );
      await windowManager.setBounds(nudged);
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await windowManager.setBounds(bounds);
    } catch (e) {
      debugPrint('[WindowService] viewport repair failed: $e');
    } finally {
      _suppressBoundsSave = false;
    }
  }

  void _scheduleSave() {
    if (_suppressBoundsSave) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      try {
        if (_suppressBoundsSave) return;
        final b = await windowManager.getBounds();
        if (!_isUsableBounds(b)) {
          return;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_keyX, b.left.toInt());
        await prefs.setInt(_keyY, b.top.toInt());
        await prefs.setInt(_keyW, b.width.toInt());
        await prefs.setInt(_keyH, b.height.toInt());
      } catch (_) {}
    });
  }

  @override
  void onWindowMove() {
    _scheduleSave();
  }

  @override
  void onWindowResize() {
    _scheduleSave();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await _updateTrayMenu();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() async {
    await _updateTrayMenu();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'open_settings':
        await windowManager.show();
        await windowManager.focus();
        appNavigatorKey.currentState?.push(
          PageTransitions.slideHorizontal(const SettingsPage()),
        );
        break;
      case 'auto_launch':
        bool isEnabled = await launchAtStartup.isEnabled();
        if (isEnabled) {
          await launchAtStartup.disable();
        } else {
          await launchAtStartup.enable();
        }
        _updateTrayMenu();
        break;
      case 'exit_app':
        exit(0);
    }
  }

  bool _isHandlingClose = false;
  static Future<bool> Function()? onShowCloseConfirm;

  @override
  void onWindowClose() {
    debugPrint(
        '[WindowService] onWindowClose() called - preventing close immediately');
    _doHandleWindowClose();
  }

  Future<void> _doHandleWindowClose() async {
    debugPrint(
        '[WindowService] _doHandleWindowClose triggered (isHandlingClose: $_isHandlingClose)');

    if (_isHandlingClose) {
      debugPrint('[WindowService] Already handling close, ignoring');
      return;
    }
    _isHandlingClose = true;

    try {
      bool shouldExit = true;
      String? failureReason;

      try {
        if (onShowCloseConfirm != null) {
          debugPrint(
              '[WindowService] Calling Flutter close confirm callback...');
          shouldExit = await onShowCloseConfirm!().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint(
                  '[WindowService] Flutter callback timed out, using native dialog');
              failureReason = 'Flutter callback timeout';
              throw TimeoutException('Close dialog timeout');
            },
          );
          debugPrint(
              '[WindowService] Flutter callback succeeded: shouldExit=$shouldExit');
        } else {
          debugPrint(
              '[WindowService] No close dialog handler registered, showing native dialog');
          failureReason = 'No callback registered';
          throw Exception('No callback registered');
        }
      } catch (e) {
        debugPrint(
            '[WindowService] Flutter dialog failed ($failureReason): $e, showing native dialog');
        final result = await _showNativeCloseDialog();
        shouldExit = (result == 6);
        debugPrint(
            '[WindowService] Native dialog result: $result, shouldExit=$shouldExit');
      }

      debugPrint('[WindowService] Final decision: shouldExit=$shouldExit');

      if (shouldExit) {
        debugPrint('[WindowService] User chose exit - terminating application');
        try {
          await windowManager.hide();
        } catch (_) {}
        exit(0);
      } else {
        debugPrint('[WindowService] User chose minimize - hiding window');
        try {
          await windowManager.hide();
        } catch (e) {
          debugPrint('[WindowService] Error hiding window: $e');
        }
        try {
          await windowManager.setPreventClose(true);
          debugPrint('[WindowService] Successfully prevented window close');
        } catch (e) {
          debugPrint('[WindowService] Error preventing close: $e');
        }
      }
    } catch (e) {
      debugPrint('[WindowService] Critical error in close logic: $e');
      exit(0);
    } finally {
      _isHandlingClose = false;
    }
  }

  Future<int> _showNativeCloseDialog() async {
    try {
      final result = await _nativeChannel.invokeMethod<int>(
        'showNativeCloseDialog',
      );
      return result ?? -1;
    } catch (e) {
      debugPrint('[WindowService] Native close dialog failed: $e');
      return -1;
    }
  }

  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowLeaveFullScreen() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowFocus() {}
  @override
  void onWindowBlur() {}
}
