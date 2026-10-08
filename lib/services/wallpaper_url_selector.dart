import 'dart:math';

/// Chooses a wallpaper URL that can trigger a fresh image-load lifecycle.
class WallpaperUrlSelector {
  const WallpaperUrlSelector._();

  static String? chooseAlternative(
    Iterable<String> urls, {
    required String? currentUrl,
    Random? random,
  }) {
    final candidates = urls
        .where((url) => url.isNotEmpty && url != currentUrl)
        .toSet()
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    return candidates[(random ?? Random()).nextInt(candidates.length)];
  }
}
