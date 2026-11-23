import 'package:flutter/services.dart';

import '../utils/app_platform.dart';

enum DesktopFlutterRenderer { skia, impeller }

/// Reads and writes the renderer selected for future desktop Flutter engines
/// on Windows and macOS.
///
/// The native runner persists this value before engine startup, because Flutter
/// chooses its renderer when each engine is created.
class DesktopRendererPreference {
  DesktopRendererPreference._();

  static const MethodChannel _windowsChannel = MethodChannel(
    'com.math_quiz_app/windows_renderer',
  );
  static const MethodChannel _macosChannel = MethodChannel(
    'com.math_quiz_app/macos_renderer',
  );

  static bool get isSupported => AppPlatform.isWindows || AppPlatform.isMacOS;

  static DesktopFlutterRenderer get defaultRenderer =>
      DesktopFlutterRenderer.skia;

  static MethodChannel? get _activeChannel {
    if (AppPlatform.isWindows) return _windowsChannel;
    if (AppPlatform.isMacOS) return _macosChannel;
    return null;
  }

  static DesktopFlutterRenderer parseRenderer(
    String? value, {
    DesktopFlutterRenderer? fallback,
  }) {
    if (value == 'impeller') return DesktopFlutterRenderer.impeller;
    if (value == 'skia') return DesktopFlutterRenderer.skia;
    return fallback ?? defaultRenderer;
  }

  static String labelFor(
    DesktopFlutterRenderer renderer, {
    required bool isMacOS,
  }) {
    return renderer == DesktopFlutterRenderer.skia
        ? 'Skia（默认）'
        : 'Impeller（实验）';
  }

  static Future<DesktopFlutterRenderer> load() async {
    final channel = _activeChannel;
    if (channel == null) return defaultRenderer;

    final value = await channel.invokeMethod<String>('getRenderer');
    return parseRenderer(value, fallback: defaultRenderer);
  }

  static Future<void> save(DesktopFlutterRenderer renderer) async {
    final channel = _activeChannel;
    if (channel == null) return;

    final saved = await channel.invokeMethod<bool>(
      'setRenderer',
      renderer.name,
    );
    if (saved != true) {
      throw PlatformException(
        code: 'save_failed',
        message: 'Could not save the desktop renderer preference.',
      );
    }
  }
}
