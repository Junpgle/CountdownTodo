import 'package:flutter/services.dart';

import '../utils/app_platform.dart';

enum WindowsFlutterRenderer { skia, impeller }

/// Reads and writes the renderer selected for future Windows Flutter engines.
///
/// The native runner persists this value before engine startup, because Flutter
/// chooses its renderer when each engine is created.
class WindowsRendererPreference {
  WindowsRendererPreference._();

  static const MethodChannel _channel = MethodChannel(
    'com.math_quiz_app/windows_renderer',
  );

  static Future<WindowsFlutterRenderer> load() async {
    if (!AppPlatform.isWindows) return WindowsFlutterRenderer.skia;

    final value = await _channel.invokeMethod<String>('getRenderer');
    return value == 'impeller'
        ? WindowsFlutterRenderer.impeller
        : WindowsFlutterRenderer.skia;
  }

  static Future<void> save(WindowsFlutterRenderer renderer) async {
    if (!AppPlatform.isWindows) return;

    final saved = await _channel.invokeMethod<bool>(
      'setRenderer',
      renderer.name,
    );
    if (saved != true) {
      throw PlatformException(
        code: 'save_failed',
        message: 'Could not save the Windows renderer preference.',
      );
    }
  }
}
