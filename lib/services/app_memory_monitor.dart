import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_platform.dart';
import 'app_memory_snapshot_io.dart'
    if (dart.library.js_interop) 'app_memory_snapshot_web.dart';

/// 内存健康度评估级别
enum MemoryHealthLevel { normal, moderate, high }

/// 滑动体验与内存策略模式
enum MemoryPolicyMode {
  /// 标准平衡模式：兼顾流畅滑动与适度内存开销
  balanced,

  /// 极速流畅模式：扩大预载图层与图片纹理缓存，保证高刷屏极致流畅
  performance,

  /// 紧凑节约模式：限制缓存与驻留空间，适合小内存设备或后台保活
  eco,
}

/// 瞬时内存占用快照
@immutable
class MemorySnapshot {
  const MemorySnapshot({
    required this.currentRss,
    required this.maxRss,
    required this.imageCacheBytes,
    required this.imageCacheCount,
    required this.maxImageCacheBytes,
    required this.maxImageCacheCount,
    required this.timestamp,
    required this.isProcessMemorySupported,
  });

  /// 当前进程实际常驻物理内存（字节）
  final int currentRss;

  /// 进程历史物理内存峰值（字节）
  final int maxRss;

  /// 当前已解码图片缓存占用的内存（字节）
  final int imageCacheBytes;

  /// 当前缓存的图片纹理张数
  final int imageCacheCount;

  /// 图片缓存允许的最大内存上限（字节）
  final int maxImageCacheBytes;

  /// 图片缓存允许的最大张数上限
  final int maxImageCacheCount;

  /// 采样时间戳
  final DateTime timestamp;

  /// 当前平台是否支持原生物理常驻内存（RSS）采集
  final bool isProcessMemorySupported;

  /// 格式化物理内存（如 `142.8 MB`）
  String get currentRssFormatted => AppMemoryMonitor.formatBytes(currentRss);

  /// 格式化历史峰值（如 `180.2 MB`）
  String get maxRssFormatted => AppMemoryMonitor.formatBytes(maxRss);

  /// 格式化图片缓存（如 `18.4 MB`）
  String get imageCacheFormatted =>
      AppMemoryMonitor.formatBytes(imageCacheBytes);

  /// 格式化图片缓存上限（如 `96.0 MB`）
  String get maxImageCacheBytesFormatted =>
      AppMemoryMonitor.formatBytes(maxImageCacheBytes);

  /// 内存占用健康状态
  MemoryHealthLevel get healthLevel {
    if (!isProcessMemorySupported) {
      if (imageCacheBytes > 80 * 1024 * 1024) return MemoryHealthLevel.high;
      if (imageCacheBytes > 40 * 1024 * 1024) return MemoryHealthLevel.moderate;
      return MemoryHealthLevel.normal;
    }

    final mb = currentRss / (1024 * 1024);
    if (AppPlatform.isMobile) {
      if (mb > 380) return MemoryHealthLevel.high;
      if (mb > 240) return MemoryHealthLevel.moderate;
      return MemoryHealthLevel.normal;
    } else {
      if (mb > 700) return MemoryHealthLevel.high;
      if (mb > 450) return MemoryHealthLevel.moderate;
      return MemoryHealthLevel.normal;
    }
  }

  /// 状态描述文字
  String get healthDescription {
    switch (healthLevel) {
      case MemoryHealthLevel.normal:
        return '正常';
      case MemoryHealthLevel.moderate:
        return '良好';
      case MemoryHealthLevel.high:
        return '偏高';
    }
  }

  /// 当前 RSS 占历史峰值的比率（0.0 ~ 1.0）
  double get peakRatio {
    if (maxRss <= 0 || currentRss <= 0) return 0.0;
    return (currentRss / maxRss).clamp(0.0, 1.0);
  }
}

/// 应用内存监控与管理服务
class AppMemoryMonitor {
  AppMemoryMonitor._();

  static const String _keyPolicyMode = 'app_memory_policy_mode';

  static final ValueNotifier<MemorySnapshot> _snapshotNotifier =
      ValueNotifier<MemorySnapshot>(_createSnapshot());

  static final ValueNotifier<MemoryPolicyMode> _policyModeNotifier =
      ValueNotifier<MemoryPolicyMode>(MemoryPolicyMode.balanced);

  static final ValueNotifier<bool> _isAutoRefreshingNotifier =
      ValueNotifier<bool>(false);

  static Timer? _autoRefreshTimer;
  static bool _isInitialized = false;

  /// 内存快照监听器
  static ValueListenable<MemorySnapshot> get snapshot => _snapshotNotifier;

  /// 当前内存策略模式监听器
  static ValueListenable<MemoryPolicyMode> get policyMode =>
      _policyModeNotifier;

  /// 是否处于自动定时刷新状态
  static ValueListenable<bool> get isAutoRefreshing =>
      _isAutoRefreshingNotifier;

  /// 当前最新内存快照
  static MemorySnapshot get currentSnapshot => _snapshotNotifier.value;

  /// 初始化服务并读取存储的策略
  static Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final modeName = prefs.getString(_keyPolicyMode);
      if (modeName != null) {
        final mode = MemoryPolicyMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => MemoryPolicyMode.balanced,
        );
        _policyModeNotifier.value = mode;
        _applyPolicyToRuntime(mode);
      }
    } catch (_) {}

    refresh();
  }

  /// 抓取一次内存快照并通知监听者
  static MemorySnapshot refresh() {
    final snapshot = _createSnapshot();
    _snapshotNotifier.value = snapshot;
    return snapshot;
  }

  static MemorySnapshot _createSnapshot() {
    final imageCache = PaintingBinding.instance.imageCache;
    return MemorySnapshot(
      currentRss: PlatformProcessMemory.currentRss,
      maxRss: PlatformProcessMemory.maxRss,
      imageCacheBytes: imageCache.currentSizeBytes,
      imageCacheCount: imageCache.currentSize,
      maxImageCacheBytes: imageCache.maximumSizeBytes,
      maxImageCacheCount: imageCache.maximumSize,
      timestamp: DateTime.now(),
      isProcessMemorySupported: PlatformProcessMemory.isSupported,
    );
  }

  /// 切换自动刷新状态（开启或关闭）
  static void setAutoRefresh(
    bool enabled, {
    Duration interval = const Duration(seconds: 2),
  }) {
    if (_isAutoRefreshingNotifier.value == enabled) return;
    _isAutoRefreshingNotifier.value = enabled;

    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;

    if (enabled) {
      refresh();
      _autoRefreshTimer = Timer.periodic(interval, (_) {
        refresh();
      });
    }
  }

  /// 一键深度整理与释放缓存
  ///
  /// 清空已解码图片缓存及悬挂强引用，并立即刷新内存采样。
  /// 返回清理前后减少的图片缓存字节数。
  static Future<int> cleanCache() async {
    final imageCache = PaintingBinding.instance.imageCache;
    final beforeBytes = imageCache.currentSizeBytes;

    imageCache.clear();
    imageCache.clearLiveImages();

    // 给予引擎一小段释放纹理的时间
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final afterBytes = imageCache.currentSizeBytes;
    refresh();

    final freedBytes = beforeBytes - afterBytes;
    return freedBytes > 0 ? freedBytes : 0;
  }

  /// 设置内存管理策略模式
  static Future<void> setPolicyMode(MemoryPolicyMode mode) async {
    if (_policyModeNotifier.value == mode) return;
    _policyModeNotifier.value = mode;
    _applyPolicyToRuntime(mode);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPolicyMode, mode.name);
    } catch (_) {}

    refresh();
  }

  static void _applyPolicyToRuntime(MemoryPolicyMode mode) {
    final imageCache = PaintingBinding.instance.imageCache;
    if (AppPlatform.isWeb) {
      switch (mode) {
        case MemoryPolicyMode.performance:
          imageCache.maximumSize = 180;
          imageCache.maximumSizeBytes = 128 << 20;
          break;
        case MemoryPolicyMode.balanced:
          imageCache.maximumSize = 120;
          imageCache.maximumSizeBytes = 80 << 20;
          break;
        case MemoryPolicyMode.eco:
          imageCache.maximumSize = 60;
          imageCache.maximumSizeBytes = 40 << 20;
          break;
      }
      return;
    }

    if (AppPlatform.isMobile) {
      switch (mode) {
        case MemoryPolicyMode.performance:
          imageCache.maximumSize = 150;
          imageCache.maximumSizeBytes = 144 << 20; // 144MB
          break;
        case MemoryPolicyMode.balanced:
          imageCache.maximumSize = 100;
          imageCache.maximumSizeBytes = 96 << 20; // 96MB
          break;
        case MemoryPolicyMode.eco:
          imageCache.maximumSize = 50;
          imageCache.maximumSizeBytes = 48 << 20; // 48MB
          break;
      }
    } else {
      switch (mode) {
        case MemoryPolicyMode.performance:
          imageCache.maximumSize = 260;
          imageCache.maximumSizeBytes = 320 << 20; // 320MB
          break;
        case MemoryPolicyMode.balanced:
          imageCache.maximumSize = 180;
          imageCache.maximumSizeBytes = 192 << 20; // 192MB
          break;
        case MemoryPolicyMode.eco:
          imageCache.maximumSize = 90;
          imageCache.maximumSizeBytes = 96 << 20; // 96MB
          break;
      }
    }
  }

  /// 字节大小格式化工具
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024.0 && i < suffixes.length - 1) {
      count /= 1024.0;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
