import 'dart:async';
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
import '../main.dart';

class WindowService with WindowListener, TrayListener {
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
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
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

      if (Platform.isWindows) {
        await _initTray();
        await _initLaunchAtStartup();
      }
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

  // WindowListener overrides for closure
  @override
  void onWindowClose() async {
    debugPrint('[WindowService] onWindowClose called');

    try {
      // 优先使用 main.dart 中定义的 Flutter 确认对话框
      // 这能保证 UI 风格一致且受 Theme 控制
      final bool shouldExit = await showCloseDialog();
      debugPrint('[WindowService] showCloseDialog result: $shouldExit');

      if (shouldExit) {
        debugPrint('[WindowService] User confirmed exit, terminating process');
        // 先尝试隐藏窗口，给予即时反馈
        try {
          await windowManager.hide();
        } catch (_) {}
        // 强制终止进程，避免因其他插件或后台任务清理导致的死锁卡死
        TerminateProcess(GetCurrentProcess(), 0);
      } else {
        debugPrint('[WindowService] User chose to hide to tray');
        await windowManager.hide();
      }
    } catch (e) {
      debugPrint('[WindowService] onWindowClose Flutter dialog error: $e');
      // 如果 Flutter 对话框逻辑失败（例如 Navigator 尚未就绪），退而求其次使用原生 Win32 弹窗
      final result = _showNativeMessageBox();
      debugPrint('[WindowService] Native MessageBox result: $result');

      if (result == 6) {
        // IDYES = 6
        debugPrint('[WindowService] User chose to exit (native)');
        TerminateProcess(GetCurrentProcess(), 0);
      } else {
        debugPrint('[WindowService] User chose to hide (native)');
        await windowManager.hide();
      }
    }
  }

  int _showNativeMessageBox() {
    const mbYesno = 0x00000004;
    const mbDefbutton2 = 0x00000100;
    const mbTopmost = 0x00040000;
    const mbIconquestion = 0x00000020;

    final hwnd = GetForegroundWindow();
    final title = '关闭确认'.toNativeUtf16();
    final message = '选择操作：\n\n是 - 退出程序\n否 - 最小化到托盘'.toNativeUtf16();

    final result = MessageBox(
      hwnd,
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
