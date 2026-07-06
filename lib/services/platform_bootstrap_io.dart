import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/app_platform.dart';
import '../windows_island/island_entry.dart' as island_entry;
import '../windows_island/island_ipc_paths.dart';
import 'float_window_service.dart';
import 'window_service.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class PlatformBootstrap {
  PlatformBootstrap._();

  static Future<bool> routeSecondaryWindow(List<String> args) async {
    if (args.isNotEmpty && args[0] == 'multi_window') {
      await appendIslandIpcLog(
          'main routed multi_window args=${args.join('|')}');
      await island_entry.islandMain(args);
      return true;
    }
    return false;
  }

  static void configureHttpOverrides() {
    HttpOverrides.global = MyHttpOverrides();
  }

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
      await FlutterDownloader.initialize(debug: kDebugMode, ignoreSsl: true);
    }
  }

  static void waitUntilDesktopReady({
    required VoidCallback onReady,
  }) {
    if (!AppPlatform.isDesktop) return;

    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      onReady();
      await WindowService.restoreStartupBoundsAndRepairViewport();
      await windowManager.show();
      await windowManager.focus();
      await WindowService.initMacStatusItemAfterWindowReady();
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
