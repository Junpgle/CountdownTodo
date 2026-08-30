import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_platform.dart';
import 'notification_service.dart';

/// Rendering workarounds for Android window modes that are not equivalent to
/// a normal full-screen Flutter surface.
class AndroidWindowRenderingPolicy {
  AndroidWindowRenderingPolicy._();

  static const MethodChannel _channel = MethodChannel(
    'com.math_quiz.junpgle.com.math_quiz_app/notifications',
  );

  /// Android 17's mini/freeform compositor can lose a subtree that is painted
  /// through a destination-in alpha mask. Keep the workaround opt-in so
  /// Android 16 and normal Android 17 windows retain the existing treatment.
  static final ValueNotifier<bool> disableShaderContentFade =
      ValueNotifier<bool>(false);

  static Future<void>? _initialization;
  static StreamSubscription<MethodCall>? _windowConfigurationSubscription;
  static bool _isAndroid17 = false;
  static bool _isInMultiWindowMode = false;

  static Future<void> initialize() {
    if (!AppPlatform.isAndroid) return Future<void>.value();

    final existing = _initialization;
    if (existing != null) return existing;

    _windowConfigurationSubscription ??= NotificationService.listen(
      'windowConfigurationChanged',
      (call) => _updateFromArguments(call.arguments),
    );

    final future = _loadInitialWindowConfiguration();
    _initialization = future;
    return future;
  }

  static Future<void> _loadInitialWindowConfiguration() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'getWindowRenderingInfo',
      );
      _updateFromArguments(result);
    } on PlatformException catch (error) {
      debugPrint('[AndroidWindowRenderingPolicy] query failed: $error');
    } on MissingPluginException catch (error) {
      debugPrint('[AndroidWindowRenderingPolicy] unavailable: $error');
    }
  }

  static void _updateFromArguments(dynamic arguments) {
    if (arguments is! Map) return;

    final sdkInt = _readInt(arguments['androidSdkInt']);
    if (sdkInt != null) {
      _isAndroid17 = sdkInt >= 37;
    } else if (arguments['isAndroid17'] is bool) {
      _isAndroid17 = arguments['isAndroid17'] as bool;
    }

    if (arguments['isInMultiWindowMode'] is bool) {
      _isInMultiWindowMode = arguments['isInMultiWindowMode'] as bool;
    }

    final shouldDisable = _isAndroid17 && _isInMultiWindowMode;
    if (disableShaderContentFade.value != shouldDisable) {
      disableShaderContentFade.value = shouldDisable;
    }
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
