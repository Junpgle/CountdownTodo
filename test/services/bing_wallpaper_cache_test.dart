import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:countdown_todo/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bing Wallpaper Cache', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns null when no wallpaper is cached', () async {
      final cached = await StorageService.getCachedBingWallpaper();
      expect(cached, isNull);
    });

    test('saves and retrieves cached bing wallpaper', () async {
      await StorageService.saveCachedBingWallpaper(
        url: 'https://cn.bing.com/th?id=OHR.Test_1920x1080.jpg',
        copyright: 'Test Photographer (© Test)',
        date: '2026-10-31',
        params: '1920:jpg:0:zh-CN',
      );

      final cached = await StorageService.getCachedBingWallpaper();
      expect(cached, isNotNull);
      expect(cached!['url'], 'https://cn.bing.com/th?id=OHR.Test_1920x1080.jpg');
      expect(cached['copyright'], 'Test Photographer (© Test)');
      expect(cached['date'], '2026-10-31');
      expect(cached['params'], '1920:jpg:0:zh-CN');
    });

    test('clears cached bing wallpaper', () async {
      await StorageService.saveCachedBingWallpaper(
        url: 'https://cn.bing.com/th?id=OHR.Test_1920x1080.jpg',
        copyright: 'Test Photographer',
        date: '2026-10-31',
        params: '1920:jpg:0:zh-CN',
      );

      await StorageService.clearCachedBingWallpaper();

      final cached = await StorageService.getCachedBingWallpaper();
      expect(cached, isNull);
    });

    test('AppSettingsStorage directly saves and retrieves cache', () async {
      await AppSettingsStorage.saveCachedBingWallpaper(
        url: 'https://cn.bing.com/test.jpg',
        copyright: null,
        date: '2026-10-31',
        params: '1920:webp:1:en-US',
      );

      final cached = await AppSettingsStorage.getCachedBingWallpaper();
      expect(cached, isNotNull);
      expect(cached!['url'], 'https://cn.bing.com/test.jpg');
      expect(cached['copyright'], isNull);
      expect(cached['date'], '2026-10-31');
      expect(cached['params'], '1920:webp:1:en-US');
    });
  });
}
