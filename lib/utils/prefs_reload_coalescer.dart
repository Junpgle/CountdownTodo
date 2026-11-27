import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_platform.dart';

/// Coalesces concurrent [SharedPreferences.reload] calls and throttles
/// back-to-back reloads in production so repeated guards do not re-read the
/// entire preferences store across the platform channel.
class PrefsReloadCoalescer {
  PrefsReloadCoalescer._();

  static const Duration defaultMinReloadInterval = Duration(seconds: 2);

  static Future<SharedPreferences>? _inFlight;
  static DateTime? _lastReloadedAt;

  static Future<SharedPreferences> getFresh({
    Duration minInterval = defaultMinReloadInterval,
    bool force = false,
    @visibleForTesting bool bypassTestReload = false,
    @visibleForTesting Future<void> Function(SharedPreferences prefs)? reloadFn,
    @visibleForTesting DateTime Function()? clock,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final runReload = reloadFn ?? (p) => p.reload();

    if (AppPlatform.isFlutterTest && !bypassTestReload) {
      await runReload(prefs);
      return prefs;
    }

    final now = (clock ?? DateTime.now)();
    final last = _lastReloadedAt;
    if (!force && last != null && now.difference(last) < minInterval) {
      return prefs;
    }

    final existing = _inFlight;
    if (existing != null) return existing;

    final task = () async {
      await runReload(prefs);
      _lastReloadedAt = (clock ?? DateTime.now)();
      return prefs;
    }();
    _inFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_inFlight, task)) _inFlight = null;
    }
  }

  /// Marks the in-memory preferences cache as fresh after an in-process write.
  static void markFresh({@visibleForTesting DateTime Function()? clock}) {
    _lastReloadedAt = (clock ?? DateTime.now)();
  }

  @visibleForTesting
  static void reset() {
    _inFlight = null;
    _lastReloadedAt = null;
  }
}
