import 'dart:io';

/// 原生平台物理内存信息读取实现
class PlatformProcessMemory {
  PlatformProcessMemory._();

  /// 当前进程常驻物理内存（字节）
  static int get currentRss {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  /// 进程历史物理内存峰值（字节）
  static int get maxRss {
    try {
      return ProcessInfo.maxRss;
    } catch (_) {
      return 0;
    }
  }

  /// 是否支持系统级物理内存读取
  static bool get isSupported => true;
}
