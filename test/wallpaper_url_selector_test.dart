import 'dart:math';

import 'package:countdown_todo/services/wallpaper_url_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WallpaperUrlSelector', () {
    test('chooses a different URL and ignores duplicate candidates', () {
      final selected = WallpaperUrlSelector.chooseAlternative(
        [
          'https://image.test/failed.jpg',
          'https://image.test/next.jpg',
          'https://image.test/next.jpg',
        ],
        currentUrl: 'https://image.test/failed.jpg',
        random: Random(1),
      );

      expect(selected, 'https://image.test/next.jpg');
    });

    test('returns null when there is no URL that can trigger a new load', () {
      expect(
        WallpaperUrlSelector.chooseAlternative(
          ['', 'https://image.test/failed.jpg'],
          currentUrl: 'https://image.test/failed.jpg',
          random: Random(1),
        ),
        isNull,
      );
    });
  });
}
