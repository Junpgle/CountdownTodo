import 'package:flutter/services.dart';

/// Provides a stronger, platform-native confirmation vibration for strict focus.
class StrictFocusHapticService {
  static const MethodChannel _channel =
      MethodChannel('countdown_todo/strict_focus_haptics');

  static Future<void> notifyFocusStarted() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      await _fallbackHaptic();
    } catch (_) {
      await _fallbackHaptic();
    }
  }

  static Future<void> notifyFocusPaused() async {
    try {
      await _channel.invokeMethod<void>('pause');
    } on MissingPluginException {
      await _fallbackPauseHaptic();
    } catch (_) {
      await _fallbackPauseHaptic();
    }
  }

  static Future<void> _fallbackHaptic() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  static Future<void> _fallbackPauseHaptic() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
