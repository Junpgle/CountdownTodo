import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/storage/user_session_storage.dart';
import '../models/thirty_day_challenge.dart';

/// 30 天挑战的本地存储。
///
/// 按当前登录用户隔离，避免不同账号在同一设备上看到彼此的挑战记录。
/// 目前不接入云端同步；数据格式独立，后续可以在不改动页面的前提下扩展同步。
abstract final class ThirtyDayChallengeRepository {
  static const String _storageKey = 'thirty_day_self_challenge_v1';
  static final ValueNotifier<int> activityRevision = ValueNotifier<int>(0);

  static Future<ThirtyDayChallengeState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _scopedKey());
    if (raw == null || raw.isEmpty) {
      final state = ThirtyDayChallengeState.initial();
      await _save(prefs, state);
      return state;
    }

    try {
      return ThirtyDayChallengeState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      final state = ThirtyDayChallengeState.initial();
      await _save(prefs, state);
      return state;
    }
  }

  static Future<bool> hasSeenIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedIntroKey()) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _scopedIntroKey(), true);
    await prefs.setBool(await _scopedStartedKey(), true);
    await prefs.setBool(await _scopedPausedKey(), false);
    activityRevision.value++;
  }

  static Future<bool> hasStarted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedStartedKey()) ??
        prefs.getBool(await _scopedIntroKey()) ??
        false;
  }

  static Future<bool> isPaused() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedPausedKey()) ?? false;
  }

  static Future<bool> isHabitCenterPromotionDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedHabitCenterPromotionKey()) ?? false;
  }

  static Future<void> dismissHabitCenterPromotion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _scopedHabitCenterPromotionKey(), true);
  }

  static Future<void> setPaused(bool paused) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _scopedPausedKey(), paused);
    activityRevision.value++;
  }

  /// 放弃当前挑战并清除本地保存的全部任务记录。
  static Future<void> abandonChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _scopedKey());
    await prefs.remove(await _scopedIntroKey());
    await prefs.remove(await _scopedStartedKey());
    await prefs.remove(await _scopedPausedKey());
    activityRevision.value++;
  }

  static Future<void> save(ThirtyDayChallengeState state) async {
    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, state);
  }

  /// 用新的自定义内容开启一场挑战，并将其设为当前设备上的活动挑战。
  static Future<ThirtyDayChallengeState> startNewChallenge({
    required String title,
    required Iterable<String> taskTitles,
  }) async {
    final state = ThirtyDayChallengeState.custom(
      title: title,
      taskTitles: taskTitles,
    );
    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, state);
    await prefs.setBool(await _scopedIntroKey(), true);
    await prefs.setBool(await _scopedStartedKey(), true);
    await prefs.setBool(await _scopedPausedKey(), false);
    activityRevision.value++;
    return state;
  }

  static Future<void> updateTask(
    ThirtyDayChallengeState state,
    int taskId, {
    String? customTitle,
    String? feeling,
    String? imageBase64,
  }) async {
    final task = _findTask(state, taskId);
    if (task == null) return;

    if (customTitle != null) {
      final trimmed = customTitle.trim();
      task.customTitle =
          trimmed.isEmpty || trimmed == task.originalTitle ? null : trimmed;
    }
    if (feeling != null) {
      task.feeling = feeling.trim();
      task.feelingUpdatedAt = DateTime.now();
    }
    if (imageBase64 != null) {
      final trimmed = imageBase64.trim();
      task.imageBase64 = trimmed.isEmpty ? null : trimmed;
      task.imageUpdatedAt = trimmed.isEmpty ? null : DateTime.now();
    }
    await save(state);
    activityRevision.value++;
  }

  static Future<void> setCompleted(
    ThirtyDayChallengeState state,
    int taskId,
    bool completed, {
    DateTime? completedAt,
  }) async {
    final task = _findTask(state, taskId);
    if (task == null) return;

    task.isCompleted = completed;
    task.completedAt = completed ? (completedAt ?? DateTime.now()) : null;
    await save(state);
    activityRevision.value++;
  }

  /// 重新开始这一轮挑战，但保留用户调整过的任务、感受和图片记录。
  static Future<void> resetProgress(ThirtyDayChallengeState state) async {
    for (final task in state.tasks) {
      task.isCompleted = false;
      task.completedAt = null;
    }
    await save(state);
    activityRevision.value++;
  }

  static Future<String> _scopedKey() async {
    final username = await UserSessionStorage.getCurrentUsername();
    if (username == null || username.isEmpty) return _storageKey;
    return '${_storageKey}_$username';
  }

  static Future<String> _scopedIntroKey() async {
    return '${await _scopedKey()}_intro_seen';
  }

  static Future<String> _scopedStartedKey() async {
    return '${await _scopedKey()}_started';
  }

  static Future<String> _scopedPausedKey() async {
    return '${await _scopedKey()}_paused';
  }

  static Future<String> _scopedHabitCenterPromotionKey() async {
    return '${await _scopedKey()}_habit_center_promotion_dismissed';
  }

  static Future<void> _save(
    SharedPreferences prefs,
    ThirtyDayChallengeState state,
  ) async {
    await prefs.setString(await _scopedKey(), jsonEncode(state.toJson()));
  }

  static ThirtyDayChallengeTask? _findTask(
    ThirtyDayChallengeState state,
    int taskId,
  ) {
    for (final task in state.tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }
}
