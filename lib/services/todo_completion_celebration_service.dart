import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 待办完成触觉反馈与全清庆祝服务
class TodoCompletionCelebrationService {
  TodoCompletionCelebrationService._();

  static const String _keyHapticEnabled = 'todo_completion_haptics_enabled';
  static const String _keyCelebrationEnabled =
      'todo_all_done_celebration_enabled';

  static bool _hapticsEnabled = true;
  static bool _celebrationEnabled = true;
  static bool _initialized = false;

  static bool get isHapticsEnabled => _hapticsEnabled;
  static bool get isCelebrationEnabled => _celebrationEnabled;

  /// 初始化偏好设置（如尚未加载）
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _hapticsEnabled = prefs.getBool(_keyHapticEnabled) ?? true;
    _celebrationEnabled = prefs.getBool(_keyCelebrationEnabled) ?? true;
    _initialized = true;
  }

  /// 更新触觉震动开关
  static Future<void> setHapticsEnabled(bool enabled) async {
    _hapticsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHapticEnabled, enabled);
  }

  /// 更新全清庆祝开关
  static Future<void> setCelebrationEnabled(bool enabled) async {
    _celebrationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCelebrationEnabled, enabled);
  }

  /// 触发轻量单项完成震动
  static void playCompletionImpact() {
    if (!_hapticsEnabled) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {
      // 平台不支持或桌面端静默忽略
    }
  }

  /// 触发全清庆祝震动
  static void playCelebrationImpact() {
    if (!_hapticsEnabled) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {
      // 平台不支持或桌面端静默忽略
    }
  }
}
