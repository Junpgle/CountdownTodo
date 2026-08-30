import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/app_platform.dart';
import 'notification_service.dart';

/// Rendering workarounds for Android window modes that are not equivalent to
/// a normal full-screen Flutter surface.
class AndroidWindowRenderingPolicy {
  AndroidWindowRenderingPolicy._();

  static const double _maxTopInset = 64.0;

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
  static bool _isFreeformWindow = false;
  static bool _isCompactWindow = false;

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

    if (arguments['isFreeformWindow'] is bool) {
      _isFreeformWindow = arguments['isFreeformWindow'] as bool;
    }

    if (arguments['isCompactWindow'] is bool) {
      _isCompactWindow = arguments['isCompactWindow'] as bool;
    } else {
      // Keep compatibility with older native builds that only sent the
      // multi-window bit.
      _isCompactWindow = _isInMultiWindowMode || _isFreeformWindow;
    }

    final shouldDisable = _isAndroid17 &&
        (_isCompactWindow || _isInMultiWindowMode || _isFreeformWindow);
    if (disableShaderContentFade.value != shouldDisable) {
      disableShaderContentFade.value = shouldDisable;
    }
  }

  /// Android 17 freeform windows can report a caption-bar inset in screen
  /// coordinates instead of window coordinates. Flutter then exposes a huge
  /// [MediaQueryData.padding.top], which causes page content to be laid out
  /// below the visible mini window. Keep a real status/caption inset, but put
  /// an upper bound on the malformed value. The value-based fallback is
  /// intentional: a vendor may deliver the bad inset before its native
  /// freeform callback reaches Dart.
  static MediaQueryData normalizeCompactWindowMediaQuery(MediaQueryData data) {
    final hasOversizedTopInset = _hasOversizedTopInset(data);
    if (!disableShaderContentFade.value && !hasOversizedTopInset) {
      return data;
    }

    final topPadding = _clampTopInset(data.padding.top, _maxTopInset);
    final viewTopPadding = _clampTopInset(data.viewPadding.top, _maxTopInset);
    final topViewInset = _clampTopInset(data.viewInsets.top, _maxTopInset);

    if (topPadding == data.padding.top &&
        viewTopPadding == data.viewPadding.top &&
        topViewInset == data.viewInsets.top) {
      return data;
    }

    return data.copyWith(
      padding: data.padding.copyWith(top: topPadding),
      viewPadding: data.viewPadding.copyWith(top: viewTopPadding),
      viewInsets: data.viewInsets.copyWith(top: topViewInset),
    );
  }

  static bool _hasOversizedTopInset(MediaQueryData data) {
    return data.padding.top > _maxTopInset ||
        data.viewPadding.top > _maxTopInset ||
        data.viewInsets.top > _maxTopInset;
  }

  static double _clampTopInset(double value, double maxValue) {
    if (!value.isFinite || value <= 0.0) return 0.0;
    return math.min(value, maxValue);
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
