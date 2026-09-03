import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_platform.dart';

/// App-wide view of Android's system Battery Saver state.
///
/// Android pushes changes through an EventChannel. A method call is retained as
/// a cold-start/resume fallback for vendor systems that delay broadcasts.
abstract final class PowerSaveModeService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.math_quiz_app/power_save_mode');
  static const EventChannel _eventChannel =
      EventChannel('com.math_quiz_app/power_save_mode_events');

  static final ValueNotifier<bool> _enabledNotifier = ValueNotifier(false);
  static StreamSubscription<dynamic>? _eventSubscription;
  static Future<void>? _initializeFuture;

  static ValueListenable<bool> get enabledListenable => _enabledNotifier;

  static bool get isEnabled => AppPlatform.isAndroid && _enabledNotifier.value;

  static Future<void> initialize() =>
      _initializeFuture ??= _initializePlatformState();

  static Future<void> _initializePlatformState() async {
    if (!AppPlatform.isAndroid) {
      _setEnabled(false);
      return;
    }

    _ensureEventSubscription();
    await refresh();
  }

  static void _ensureEventSubscription() {
    if (!AppPlatform.isAndroid || _eventSubscription != null) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          _updateFromPlatform,
          onError: (_) {
            // Keep the last confirmed native state. A resume refresh provides the
            // fallback when an OEM drops or delays the broadcast stream.
          },
          onDone: () => _eventSubscription = null,
        );
  }

  static Future<void> refresh() async {
    if (!AppPlatform.isAndroid) {
      _setEnabled(false);
      return;
    }

    _ensureEventSubscription();
    try {
      final enabled =
          await _methodChannel.invokeMethod<bool>('refreshPowerSaveMode');
      if (enabled != null) _setEnabled(enabled);
    } on MissingPluginException {
      // Older/non-Android embeddings do not expose this bridge.
    } on PlatformException {
      // Preserve the last event-driven value and retry on the next resume.
    }
  }

  static void _updateFromPlatform(dynamic value) {
    if (value is bool) {
      _setEnabled(value);
    } else if (value is num) {
      _setEnabled(value != 0);
    }
  }

  static void _setEnabled(bool enabled) {
    if (_enabledNotifier.value == enabled) return;
    _enabledNotifier.value = enabled;
  }

  @visibleForTesting
  static void updateFromPlatformForTesting(dynamic value) {
    _updateFromPlatform(value);
  }

  static Future<void> dispose() async {
    final subscription = _eventSubscription;
    _eventSubscription = null;
    try {
      await subscription?.cancel();
    } on PlatformException {
      // Engine teardown can race with EventChannel cancellation.
    } on MissingPluginException {
      // No native bridge was registered.
    }
    _initializeFuture = null;
    _setEnabled(false);
  }
}
