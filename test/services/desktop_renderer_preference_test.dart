import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/services/desktop_renderer_preference.dart';
import 'package:countdown_todo/utils/app_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopRendererPreference', () {
    test('parseRenderer parses known values and falls back on unknown', () {
      expect(
        DesktopRendererPreference.parseRenderer(
          'skia',
          fallback: DesktopFlutterRenderer.impeller,
        ),
        DesktopFlutterRenderer.skia,
      );
      expect(
        DesktopRendererPreference.parseRenderer(
          'impeller',
          fallback: DesktopFlutterRenderer.skia,
        ),
        DesktopFlutterRenderer.impeller,
      );
      expect(
        DesktopRendererPreference.parseRenderer(
          null,
          fallback: DesktopFlutterRenderer.impeller,
        ),
        DesktopFlutterRenderer.impeller,
      );
      expect(
        DesktopRendererPreference.parseRenderer(
          'unknown',
          fallback: DesktopFlutterRenderer.skia,
        ),
        DesktopFlutterRenderer.skia,
      );
    });

    test('labelFor returns platform-specific labels', () {
      expect(
        DesktopRendererPreference.labelFor(
          DesktopFlutterRenderer.impeller,
          isMacOS: true,
        ),
        'Impeller（实验）',
      );
      expect(
        DesktopRendererPreference.labelFor(
          DesktopFlutterRenderer.skia,
          isMacOS: true,
        ),
        'Skia（默认）',
      );
      expect(
        DesktopRendererPreference.labelFor(
          DesktopFlutterRenderer.skia,
          isMacOS: false,
        ),
        'Skia（默认）',
      );
      expect(
        DesktopRendererPreference.labelFor(
          DesktopFlutterRenderer.impeller,
          isMacOS: false,
        ),
        'Impeller（实验）',
      );
    });

    test('load and save communicate over the active desktop channel', () async {
      if (!DesktopRendererPreference.isSupported) return;

      final channel = MethodChannel(
        AppPlatform.isMacOS
            ? 'com.math_quiz_app/macos_renderer'
            : 'com.math_quiz_app/windows_renderer',
      );
      var stored = AppPlatform.isMacOS ? 'impeller' : 'skia';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getRenderer') {
              return stored;
            }
            if (call.method == 'setRenderer') {
              stored = call.arguments as String;
              return true;
            }
            return null;
          });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      expect(
        await DesktopRendererPreference.load(),
        AppPlatform.isMacOS
            ? DesktopFlutterRenderer.impeller
            : DesktopFlutterRenderer.skia,
      );

      await DesktopRendererPreference.save(DesktopFlutterRenderer.skia);
      expect(stored, 'skia');
      expect(
        await DesktopRendererPreference.load(),
        DesktopFlutterRenderer.skia,
      );

      await DesktopRendererPreference.save(DesktopFlutterRenderer.impeller);
      expect(stored, 'impeller');
      expect(
        await DesktopRendererPreference.load(),
        DesktopFlutterRenderer.impeller,
      );
    });

    test('save throws PlatformException when native returns false', () async {
      if (!DesktopRendererPreference.isSupported) return;

      final channel = MethodChannel(
        AppPlatform.isMacOS
            ? 'com.math_quiz_app/macos_renderer'
            : 'com.math_quiz_app/windows_renderer',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setRenderer') return false;
            return null;
          });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await expectLater(
        DesktopRendererPreference.save(DesktopFlutterRenderer.skia),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
