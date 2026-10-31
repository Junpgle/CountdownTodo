import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/services/windows_render_cache_policy.dart';
import 'package:countdown_todo/utils/app_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final imageCache = PaintingBinding.instance.imageCache;
  final originalMaximumSize = imageCache.maximumSize;
  final originalMaximumSizeBytes = imageCache.maximumSizeBytes;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.skia, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    imageCache.maximumSize = originalMaximumSize;
    imageCache.maximumSizeBytes = originalMaximumSizeBytes;
    imageCache.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.skia, null);
  });

  test('bounds main and island caches on Windows', () async {
    if (!AppPlatform.isWindows) {
      expect(await WindowsRenderCachePolicy.configure(), isFalse);
      expect(calls, isEmpty);
      return;
    }

    expect(await WindowsRenderCachePolicy.configure(), isTrue);
    expect(imageCache.maximumSize, WindowsRenderCachePolicy.mainImageEntries);
    expect(
      imageCache.maximumSizeBytes,
      WindowsRenderCachePolicy.mainImageBytes,
    );

    expect(await WindowsRenderCachePolicy.configure(island: true), isTrue);
    expect(imageCache.maximumSize, WindowsRenderCachePolicy.islandImageEntries);
    expect(
      imageCache.maximumSizeBytes,
      WindowsRenderCachePolicy.islandImageBytes,
    );
    expect(
      calls.map((call) => call.method),
      everyElement('Skia.setResourceCacheMaxBytes'),
    );
    expect(calls.map((call) => call.arguments), [
      WindowsRenderCachePolicy.mainWindowBytes,
      WindowsRenderCachePolicy.islandWindowBytes,
    ]);
  });

  test('disabled policy leaves caches untouched', () async {
    final beforeMaximumSize = imageCache.maximumSize;
    final beforeMaximumSizeBytes = imageCache.maximumSizeBytes;

    expect(await WindowsRenderCachePolicy.configure(enabled: false), isFalse);
    expect(imageCache.maximumSize, beforeMaximumSize);
    expect(imageCache.maximumSizeBytes, beforeMaximumSizeBytes);
    expect(calls, isEmpty);
  });
}
