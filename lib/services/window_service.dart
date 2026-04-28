import 'dart:async' show unawaited, TimeoutException, Timer;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';
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

  static Timer? _debounce;

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
        try {
          await windowManager.setBounds(Rect.fromLTWH(
              x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()));
        } catch (_) {}
      }

      // Register listener for move/resize to persist bounds with debounce
      windowManager.addListener(_instance);
      debugPrint('[WindowService] windowManager.addListener(_instance) done');

      if (Platform.isWindows) {
        await _initTray();
        await _initLaunchAtStartup();
      }
      debugPrint('[WindowService] Initialization complete!');
    } catch (e) {
      debugPrint('[WindowService] init error: $e');
    }
  }

  static Future<void> _initTray() async {
    try {
      trayManager.addListener(_instance);
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/icon/app_icon.ico'
            : 'assets/icon/app_icon.png',
      );
      await trayManager.setToolTip('CountDownTodo');
      await _updateTrayMenu();
    } catch (e) {
      debugPrint('[WindowService] initTray error: $e');
    }
  }

  static Future<void> _updateTrayMenu() async {
    try {
      bool isLaunchAtStartup = await launchAtStartup.isEnabled();
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

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      try {
        final b = await windowManager.getBounds();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_keyX, b.left.toInt());
        await prefs.setInt(_keyY, b.top.toInt());
        await prefs.setInt(_keyW, b.width.toInt());
        await prefs.setInt(_keyH, b.height.toInt());
      } catch (_) {}
    });
  }

  // WindowListener overrides
  @override
  void onWindowMove() {
    _scheduleSave();
  }

  @override
  void onWindowResize() {
    _scheduleSave();
  }

  // TrayListener overrides
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
        TerminateProcess(GetCurrentProcess(), 0);
        break;
    }
  }

  bool _isHandlingClose = false;
  static Future<bool> Function()? onShowCloseConfirm;

  // WindowListener overrides for closure
  @override
  void onWindowClose() {
    debugPrint('[WindowService] ⚠️ onWindowClose() called - preventing close immediately');
    
    // 立即处理，不等待
    _doHandleWindowClose();
  }

  Future<void> _doHandleWindowClose() async {
    debugPrint('[WindowService] _doHandleWindowClose triggered (isHandlingClose: $_isHandlingClose)');
    
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
          debugPrint('[WindowService] Calling Flutter close confirm callback...');
          shouldExit = await onShowCloseConfirm!().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('[WindowService] Flutter callback timed out, using native dialog');
              failureReason = 'Flutter callback timeout';
              throw TimeoutException('Close dialog timeout');
            },
          );
          debugPrint('[WindowService] Flutter callback succeeded: shouldExit=$shouldExit');
        } else {
          debugPrint('[WindowService] No close dialog handler registered, showing native dialog');
          failureReason = 'No callback registered';
          throw Exception('No callback registered');
        }
      } catch (e) {
        debugPrint('[WindowService] Flutter dialog failed ($failureReason): $e, showing native dialog');
        final result = _showNativeMessageBox();
        shouldExit = (result == 6); // IDYES = 6
        debugPrint('[WindowService] Native dialog result: $result, shouldExit=$shouldExit');
      }

      debugPrint('[WindowService] Final decision: shouldExit=$shouldExit');

      if (shouldExit) {
        debugPrint('[WindowService] User chose exit - terminating application');
        try {
          await windowManager.hide();
        } catch (_) {}
        // 强制退出程序
        TerminateProcess(GetCurrentProcess(), 0);
      } else {
        debugPrint('[WindowService] User chose minimize - hiding window');
        try {
          await windowManager.hide();
        } catch (e) {
          debugPrint('[WindowService] Error hiding window: $e');
        }
        // ⚠️ 关键修复：通过 setPreventClose(true) 来真正阻止窗口关闭
        // 这会让 window_manager 知道我们处理了关闭事件
        try {
          await windowManager.setPreventClose(true);
          debugPrint('[WindowService] Successfully prevented window close');
        } catch (e) {
          debugPrint('[WindowService] Error preventing close: $e');
        }
      }
    } catch (e) {
      debugPrint('[WindowService] Critical error in close logic: $e');
      TerminateProcess(GetCurrentProcess(), 0);
    } finally {
      _isHandlingClose = false;
    }
  }

  int _showNativeMessageBox() {
    const mbYesno = 0x00000004;
    const mbDefbutton2 = 0x00000100;
    const mbTopmost = 0x00040000;
    const mbIconquestion = 0x00000020;

    // 使用 0 作为父窗口句柄，确保对话框在任何情况下都能作为独立顶层窗口弹出
    final title = '关闭确认'.toNativeUtf16();
    final message = '选择操作：\n\n是 - 退出程序\n否 - 最小化到托盘'.toNativeUtf16();

    final result = MessageBox(
      0,
      message,
      title,
      mbYesno | mbDefbutton2 | mbTopmost | mbIconquestion,
    );

    calloc.free(title);
    calloc.free(message);

    return result;
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
