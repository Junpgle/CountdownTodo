import 'dart:ui' as ui;

/// Shared immutable image filters used by repeatedly rebuilt UI surfaces.
///
/// ImageFilter.blur creates a new wrapper each time it is called, and that
/// wrapper lazily retains its native filter. These instances preserve the
/// existing blur settings while avoiding repeated wrapper/native allocation.
class AppImageFilters {
  AppImageFilters._();

  static final ui.ImageFilter blur6 = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6);
  static final ui.ImageFilter blur5 = ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5);
  static final ui.ImageFilter blur10 = ui.ImageFilter.blur(
    sigmaX: 10,
    sigmaY: 10,
  );
  static final ui.ImageFilter blur12 = ui.ImageFilter.blur(
    sigmaX: 12,
    sigmaY: 12,
  );
  static final ui.ImageFilter blur15 = ui.ImageFilter.blur(
    sigmaX: 15,
    sigmaY: 15,
  );
  static final ui.ImageFilter blur16 = ui.ImageFilter.blur(
    sigmaX: 16,
    sigmaY: 16,
  );
  static final ui.ImageFilter blur20 = ui.ImageFilter.blur(
    sigmaX: 20,
    sigmaY: 20,
  );
  static final ui.ImageFilter blur30 = ui.ImageFilter.blur(
    sigmaX: 30,
    sigmaY: 30,
  );
  static final ui.ImageFilter blur40 = ui.ImageFilter.blur(
    sigmaX: 40,
    sigmaY: 40,
  );
  static final ui.ImageFilter blur48 = ui.ImageFilter.blur(
    sigmaX: 48,
    sigmaY: 48,
  );
  static final ui.ImageFilter blur60 = ui.ImageFilter.blur(
    sigmaX: 60,
    sigmaY: 60,
  );
  static final ui.ImageFilter blur80 = ui.ImageFilter.blur(
    sigmaX: 80,
    sigmaY: 80,
  );
  static final ui.ImageFilter blur9Clamped = ui.ImageFilter.blur(
    sigmaX: 9,
    sigmaY: 9,
    tileMode: ui.TileMode.clamp,
  );
  static final ui.ImageFilter blur16Clamped = ui.ImageFilter.blur(
    sigmaX: 16,
    sigmaY: 16,
    tileMode: ui.TileMode.clamp,
  );

  static final Map<int, ui.ImageFilter> _quantizedClampedBlurCache = {};

  /// Returns a shared, quantized clamped blur filter to avoid instantiating native
  /// image filters on every sub-pixel scroll step.
  static ui.ImageFilter quantizedClampedBlur(double sigma) {
    if (sigma <= 0.01) {
      return _quantizedClampedBlurCache.putIfAbsent(
        0,
        () => ui.ImageFilter.blur(
          sigmaX: 0.0,
          sigmaY: 0.0,
          tileMode: ui.TileMode.clamp,
        ),
      );
    }
    // Quantize to 0.5 steps to avoid recreating native filters on dynamic scroll animations.
    final key = (sigma * 2).round();
    return _quantizedClampedBlurCache.putIfAbsent(
      key,
      () => ui.ImageFilter.blur(
        sigmaX: key / 2.0,
        sigmaY: key / 2.0,
        tileMode: ui.TileMode.clamp,
      ),
    );
  }

  /// Releases cached dynamic filters under memory pressure.
  static void clearFilterCache() {
    _quantizedClampedBlurCache.clear();
  }
}
