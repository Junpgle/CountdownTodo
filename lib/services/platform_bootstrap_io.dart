import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/app_platform.dart';
import 'float_window_service.dart';
import 'window_service.dart';
import 'windows_island_bootstrap.dart';

class PlatformBootstrap {
  PlatformBootstrap._();

  static Future<bool> routeSecondaryWindow(List<String> args) =>
      WindowsIslandBootstrap.routeSecondaryWindow(args);

  static Future<void> initDatabaseFactory() async {
    if (AppPlatform.isDesktop) {
      // debugPrint("🛠️ [Main] 检测到桌面平台，正在全局初始化 SQL FFI 引擎...");
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<void> initWindowService() => WindowService.init();

  static Future<void> initMobileDownloader() async {
    if (AppPlatform.isAndroid || AppPlatform.isIOS) {
      await FlutterDownloader.initialize(debug: kDebugMode);
    }
  }

  static void waitUntilDesktopReady({required VoidCallback onReady}) {
    if (!AppPlatform.isDesktop) return;

    final windowOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: AppPlatform.isMacOS
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: AppPlatform.isMacOS ? false : true,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      onReady();
      await WindowService.restoreStartupBoundsAndRepairViewport();
      await windowManager.show();
      await windowManager.focus();
      await WindowService.initMacIslandAfterWindowReady();
      WindowService.schedulePostShowViewportRepair();
      if (AppPlatform.isWindows) {
        try {
          await FloatWindowService.init();
        } catch (e) {
          // debugPrint('FloatWindowService init failed: $e');
        }
      }
    });
  }
}
