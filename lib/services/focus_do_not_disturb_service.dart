import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level Do Not Disturb state for an active focus session.
///
/// On Android, the same state can also control the operating system's
/// interruption filter after the user grants notification policy access. On
/// iOS, macOS, Windows, and the web, the app-level part still works, but the
/// operating system's Focus/DND mode is not programmatically controllable by a
/// regular app.
class FocusDoNotDisturbService {
  static const activePreferenceKey = 'focus_do_not_disturb_active';
  static const untilPreferenceKey = 'focus_do_not_disturb_until_ms';
  static const _sessionPreferenceKey = 'focus_do_not_disturb_session_uuid';
  static const _maxActiveDuration = Duration(hours: 12);
  static const MethodChannel _channel = MethodChannel(
    'com.math_quiz.junpgle.com.math_quiz_app/notifications',
  );

  static bool _active = false;
  static int _untilMs = 0;
  static String? _sessionUuid;
  static Future<void>? _initialization;
  static Future<void> _operationTail = Future<void>.value();

  static bool get isActive {
    if (!_active) return false;
    return _untilMs <= 0 || _untilMs > DateTime.now().millisecondsSinceEpoch;
  }

  static int get activeUntilMs => isActive ? _untilMs : 0;

  static bool get supportsSystemDoNotDisturb =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Restores the state before background notification code can run.
  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(activePreferenceKey) ?? false;
    final untilMs = prefs.getInt(untilPreferenceKey) ?? 0;
    final sessionUuid = prefs.getString(_sessionPreferenceKey);
    final expired = active && untilMs > 0 && untilMs <= _nowMs();

    if (expired) {
      _active = false;
      _untilMs = 0;
      await _setNativeSystemDoNotDisturb(false);
      await prefs.setBool(activePreferenceKey, false);
      await prefs.remove(untilPreferenceKey);
      await prefs.remove(_sessionPreferenceKey);
      return;
    }

    _active = active;
    _untilMs = untilMs;
    _sessionUuid = active ? sessionUuid : null;
    await _setNativeSystemDoNotDisturb(
      active,
      untilMs: active ? untilMs : null,
    );
  }

  /// Changes the current app-level DND state in order, because the dashboard
  /// and workbench can both receive the same cross-device event.
  static Future<void> setActive(
    bool active, {
    String? sessionUuid,
    int? untilMs,
    bool force = false,
  }) {
    final operation = _operationTail.then<void>((_) async {
      // A cold-start reconciliation and a run-state listener can arrive at
      // the same time. Serialize both behind initialization so a stale
      // persisted state cannot win a race with the caller's update.
      await initialize();
      if (!active &&
          !force &&
          _sessionUuid != null &&
          sessionUuid != _sessionUuid) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (active) {
        final now = _nowMs();
        _active = true;
        _untilMs = untilMs != null && untilMs > now
            ? untilMs
            : now + _maxActiveDuration.inMilliseconds;
        _sessionUuid = sessionUuid ?? _sessionUuid;
        await prefs.setBool(activePreferenceKey, true);
        await prefs.setInt(untilPreferenceKey, _untilMs);
        if (_sessionUuid != null) {
          await prefs.setString(_sessionPreferenceKey, _sessionUuid!);
        } else {
          await prefs.remove(_sessionPreferenceKey);
        }
        await _setNativeSystemDoNotDisturb(true, untilMs: _untilMs);
      } else {
        _active = false;
        _untilMs = 0;
        _sessionUuid = null;
        await _setNativeSystemDoNotDisturb(false);
        await prefs.setBool(activePreferenceKey, false);
        await prefs.remove(untilPreferenceKey);
        await prefs.remove(_sessionPreferenceKey);
      }
    });
    _operationTail = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  static Future<void> clear({String? sessionUuid}) {
    return setActive(false, sessionUuid: sessionUuid);
  }

  static Future<bool> hasSystemDoNotDisturbAccess() async {
    if (!supportsSystemDoNotDisturb) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'getSystemDoNotDisturbAccess',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSystemDoNotDisturbSettings() async {
    if (!supportsSystemDoNotDisturb) return;
    try {
      await _channel.invokeMethod<void>('openSystemDoNotDisturbSettings');
    } catch (_) {}
  }

  static Future<void> _setNativeSystemDoNotDisturb(
    bool active, {
    int? untilMs,
  }) async {
    if (!supportsSystemDoNotDisturb) return;
    try {
      await _channel.invokeMethod<void>('setSystemDoNotDisturb', {
        'enabled': active,
        if (untilMs != null) 'untilMs': untilMs,
      });
    } catch (_) {}
  }

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}
