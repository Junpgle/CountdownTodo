import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 习惯打卡触觉反馈、仪式启动与长按打卡配置服务。
class HabitCelebrationService {
  HabitCelebrationService._();

  static const String _keyHapticsEnabled = 'habit_checkin_haptics_enabled';
  static const String _keyCelebrationEnabled =
      'habit_goal_met_celebration_enabled';
  static const String _keyHoldToCheckinEnabled =
      'habit_hold_to_checkin_enabled';

  static bool _hapticsEnabled = true;
  static bool _celebrationEnabled = true;
  static bool _holdToCheckinEnabled = false;
  static bool _initialized = false;

  /// 是否开启打卡震动反馈（默认开启）。
  static bool get isHapticsEnabled => _hapticsEnabled;

  /// 是否开启目标达成/连胜达成全屏庆祝弹层（默认开启）。
  static bool get isCelebrationEnabled => _celebrationEnabled;

  /// 是否启用长按蓄力打卡模式（默认关闭，开启后长按 0.6s 盖章确认）。
  static bool get isHoldToCheckinEnabled => _holdToCheckinEnabled;

  /// 初始化偏好设置（已缓存则立即返回）。
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _hapticsEnabled = prefs.getBool(_keyHapticsEnabled) ?? true;
    _celebrationEnabled = prefs.getBool(_keyCelebrationEnabled) ?? true;
    _holdToCheckinEnabled = prefs.getBool(_keyHoldToCheckinEnabled) ?? false;
    _initialized = true;
  }

  /// 更新触觉震动开关。
  static Future<void> setHapticsEnabled(bool enabled) async {
    _hapticsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHapticsEnabled, enabled);
  }

  /// 更新目标达成庆祝开关。
  static Future<void> setCelebrationEnabled(bool enabled) async {
    _celebrationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCelebrationEnabled, enabled);
  }

  /// 更新长按蓄力打卡开关。
  static Future<void> setHoldToCheckinEnabled(bool enabled) async {
    _holdToCheckinEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHoldToCheckinEnabled, enabled);
  }

  /// 长按蓄力过程中的微弱刻度触感。
  static void playHoldStepImpact() {
    if (!_hapticsEnabled) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {
      // 桌面端或不支持平台静默忽略
    }
  }

  /// 单次打卡完成震动反馈。
  static void playCheckinImpact() {
    if (!_hapticsEnabled) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {
      // 桌面端或不支持平台静默忽略
    }
  }

  /// 目标达成 / 突破连续天数强力庆祝震动反馈。
  static void playGoalMetImpact() {
    if (!_hapticsEnabled) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {
      // 桌面端或不支持平台静默忽略
    }
  }
}
