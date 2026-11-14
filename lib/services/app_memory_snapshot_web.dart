/// Web 平台内存安全占位实现
class PlatformProcessMemory {
  PlatformProcessMemory._();

  static int get currentRss => 0;

  static int get maxRss => 0;

  static bool get isSupported => false;
}
