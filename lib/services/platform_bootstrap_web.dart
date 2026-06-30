import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class PlatformBootstrap {
  PlatformBootstrap._();

  static Future<bool> routeSecondaryWindow(List<String> args) async => false;

  static void configureHttpOverrides() {}

  static Future<void> initDatabaseFactory() async {
    databaseFactory = databaseFactoryFfiWeb;
  }

  static Future<void> initWindowService() async {}

  static Future<void> initMobileDownloader() async {}

  static void waitUntilDesktopReady({
    required VoidCallback onReady,
  }) {}
}
