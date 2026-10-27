import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../utils/app_platform.dart';

/// Bounds decoded-image and Skia GPU resource caches on Windows.
///
/// Flutter otherwise budgets 12 RGBA frames at the physical window size.
/// On high-DPI Windows displays this can retain hundreds of MB per engine.
/// This is a cache budget, not a limit on live textures or total process memory.
class WindowsRenderCachePolicy {
  WindowsRenderCachePolicy._();

  static const int mainWindowBytes = 96 << 20;
  static const int inactiveMainWindowBytes = 16 << 20;
  static const int islandWindowBytes = 16 << 20;
  static const int mainImageBytes = 96 << 20;
  static const int inactiveMainImageBytes = 32 << 20;
  static const int islandImageBytes = 16 << 20;
  static const int mainImageEntries = 120;
  static const int inactiveMainImageEntries = 40;
  static const int islandImageEntries = 40;
  static bool _mainWindowActive = true;

  /// Call once in each engine before rendering. Do not flush caches on scroll
  /// or focus changes: that would repeatedly upload the same resources.
  static Future<bool> configure({
    bool island = false,
    bool enabled = true,
  }) async {
    if (!enabled || !AppPlatform.isWindows) return false;
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = island
        ? islandImageEntries
        : (_mainWindowActive ? mainImageEntries : inactiveMainImageEntries);
    imageCache.maximumSizeBytes = island
        ? islandImageBytes
        : (_mainWindowActive ? mainImageBytes : inactiveMainImageBytes);
    final resourceBudget = island
        ? islandWindowBytes
        : (_mainWindowActive ? mainWindowBytes : inactiveMainWindowBytes);
    try {
      return await SystemChannels.skia
              .invokeMethod<bool>(
                'Skia.setResourceCacheMaxBytes',
                resourceBudget,
              )
              .timeout(const Duration(seconds: 2)) ==
          true;
    } catch (error) {
      // An unsupported renderer must not prevent either window from starting.
      debugPrint('[WindowsRenderCache] Could not set resource budget: $error');
      return false;
    }
  }

  /// Shrinks the main engine's non-live caches while its window is inactive.
  /// Live section resources are released by the dashboard's bounded lifecycle;
  /// this only tightens the engine and image-cache LRU budgets.
  static Future<bool> setMainWindowActive(bool active) {
    if (!AppPlatform.isWindows || _mainWindowActive == active) {
      return Future<bool>.value(false);
    }
    _mainWindowActive = active;
    return configure();
  }
}
