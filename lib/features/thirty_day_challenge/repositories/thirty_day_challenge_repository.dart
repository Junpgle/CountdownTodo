import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/storage/user_session_storage.dart';
import '../models/thirty_day_challenge.dart';

/// 30 天挑战的本地存储。
///
/// 按当前登录用户隔离，避免不同账号在同一设备上看到彼此的挑战记录。
/// 目前不接入云端同步；数据格式独立，后续可以在不改动页面的前提下扩展同步。
abstract final class ThirtyDayChallengeRepository {
  static const String _storageKey = 'thirty_day_self_challenge_v1';

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
  }

  static Future<void> save(ThirtyDayChallengeState state) async {
    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, state);
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
  }

  /// 重新开始这一轮挑战，但保留用户调整过的任务、感受和图片记录。
  static Future<void> resetProgress(ThirtyDayChallengeState state) async {
    for (final task in state.tasks) {
      task.isCompleted = false;
      task.completedAt = null;
    }
    await save(state);
  }

  static Future<String> _scopedKey() async {
    final username = await UserSessionStorage.getCurrentUsername();
    if (username == null || username.isEmpty) return _storageKey;
    return '${_storageKey}_$username';
  }

  static Future<String> _scopedIntroKey() async {
    return '${await _scopedKey()}_intro_seen';
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
