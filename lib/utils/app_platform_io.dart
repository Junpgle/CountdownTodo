import 'dart:io' show Platform;

class AppPlatform {
  AppPlatform._();

  static bool get isWeb => false;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isDesktop => isWindows || isLinux || isMacOS;
  static bool get isMobile => isAndroid || isIOS;
  static String get operatingSystem => Platform.operatingSystem;
  static String? get resolvedExecutable => Platform.resolvedExecutable;
}
