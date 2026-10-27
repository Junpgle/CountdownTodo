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
  static const int islandWindowBytes = 16 << 20;
  static const int mainImageBytes = 96 << 20;
  static const int islandImageBytes = 16 << 20;
  static const int mainImageEntries = 120;
  static const int islandImageEntries = 40;

  /// Call once in each engine before rendering. Do not flush caches on scroll
  /// or focus changes: that would repeatedly upload the same resources.
  static Future<bool> configure({
    bool island = false,
    bool enabled = true,
  }) async {
    if (!enabled || !AppPlatform.isWindows) return false;
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = island ? islandImageEntries : mainImageEntries;
    imageCache.maximumSizeBytes = island ? islandImageBytes : mainImageBytes;
    try {
      return await SystemChannels.skia
              .invokeMethod<bool>(
                'Skia.setResourceCacheMaxBytes',
                island ? islandWindowBytes : mainWindowBytes,
              )
              .timeout(const Duration(seconds: 2)) ==
          true;
    } catch (error) {
      // An unsupported renderer must not prevent either window from starting.
      debugPrint('[WindowsRenderCache] Could not set resource budget: $error');
      return false;
    }
  }
}
