import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/storage/user_session_storage.dart';
import '../../../services/storage/storage_key_scope.dart';
import '../models/thirty_day_challenge.dart';

/// 30 天挑战的本地存储。
///
/// 按当前登录用户隔离，避免不同账号在同一设备上看到彼此的挑战记录。
/// 目前不接入云端同步；数据格式独立，后续可以在不改动页面的前提下扩展同步。
abstract final class ThirtyDayChallengeRepository {
  static const String _storageKey = 'thirty_day_self_challenge_v1';
  static final ValueNotifier<int> activityRevision = ValueNotifier<int>(0);

  static Future<ThirtyDayChallengeState> load({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _scopedKey(username));
    if (raw == null || raw.isEmpty) {
      final state = ThirtyDayChallengeState.initial();
      await _save(prefs, state, username: username);
      return state;
    }

    try {
      return ThirtyDayChallengeState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      final state = ThirtyDayChallengeState.initial();
      await _save(prefs, state, username: username);
      return state;
    }
  }

  static Future<bool> hasSeenIntro({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedIntroKey(username)) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _scopedIntroKey(), true);
    await prefs.setBool(await _scopedStartedKey(), true);
    await prefs.setBool(await _scopedPausedKey(), false);
    activityRevision.value++;
  }

  static Future<bool> hasStarted({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedStartedKey(username)) ??
        prefs.getBool(await _scopedIntroKey(username)) ??
        false;
  }

  static Future<bool> isPaused({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedPausedKey(username)) ?? false;
  }

  static Future<bool> isHabitCenterPromotionDismissed({String? username}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _scopedHabitCenterPromotionKey(username)) ??
        false;
  }

  static Future<void> dismissHabitCenterPromotion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(await _scopedHabitCenterPromotionKey(), true);
  }

  static Future<Map<String, dynamic>?> exportBackup({String? username}) async {
    if (!await hasStarted(username: username)) return null;
    final state = await load(username: username);
    return {
      'state': state.toJson(),
      'intro_seen': await hasSeenIntro(username: username),
      'started': await hasStarted(username: username),
      'paused': await isPaused(username: username),
      'habit_center_promotion_dismissed':
          await isHabitCenterPromotionDismissed(username: username),
    };
  }

  static Future<int> importBackup(
    Map<String, dynamic> bundle, {
    String? username,
  }) async {
    final rawState = bundle['state'];
    if (rawState is! Map) {
      throw const FormatException('thirty_day_challenge.state 必须是对象');
    }
    final stateJson = Map<String, dynamic>.from(rawState);
    final rawTasks = stateJson['tasks'];
    if (rawTasks is! List ||
        rawTasks.isEmpty ||
        rawTasks.any((task) => task is! Map)) {
      throw const FormatException('thirty_day_challenge.state.tasks 格式无效');
    }
    final state = ThirtyDayChallengeState.fromJson(stateJson);
    if (state.tasks.length != rawTasks.length || bundle['started'] == false) {
      throw const FormatException('thirty_day_challenge 记录不完整');
    }

    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, state, username: username);
    await prefs.setBool(
      await _scopedIntroKey(username),
      bundle['intro_seen'] != false,
    );
    await prefs.setBool(await _scopedStartedKey(username), true);
    await prefs.setBool(
      await _scopedPausedKey(username),
      bundle['paused'] == true,
    );
    await prefs.setBool(
      await _scopedHabitCenterPromotionKey(username),
      bundle['habit_center_promotion_dismissed'] == true,
    );
    activityRevision.value++;
    return state.tasks.length;
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
    await _activateChallenge(prefs, state);
    return state;
  }

  /// 开启经典挑战，并保留其类型标记以便后续恢复正确的页面说明。
  static Future<ThirtyDayChallengeState> startBuiltInChallenge() async {
    final state = ThirtyDayChallengeState.initial();
    final prefs = await SharedPreferences.getInstance();
    await _activateChallenge(prefs, state);
    return state;
  }

  static Future<void> _activateChallenge(
    SharedPreferences prefs,
    ThirtyDayChallengeState state,
  ) async {
    await _save(prefs, state);
    await prefs.setBool(await _scopedIntroKey(), true);
    await prefs.setBool(await _scopedStartedKey(), true);
    await prefs.setBool(await _scopedPausedKey(), false);
    activityRevision.value++;
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

  static Future<String> _scopedKey([String? username]) async {
    final scope = username ?? await UserSessionStorage.getCurrentUsername();
    return StorageKeyScope.scoped(_storageKey, scope);
  }

  static Future<String> _scopedIntroKey([String? username]) async {
    return '${await _scopedKey(username)}_intro_seen';
  }

  static Future<String> _scopedStartedKey([String? username]) async {
    return '${await _scopedKey(username)}_started';
  }

  static Future<String> _scopedPausedKey([String? username]) async {
    return '${await _scopedKey(username)}_paused';
  }

  static Future<String> _scopedHabitCenterPromotionKey([
    String? username,
  ]) async {
    return '${await _scopedKey(username)}_habit_center_promotion_dismissed';
  }

  static Future<void> _save(
    SharedPreferences prefs,
    ThirtyDayChallengeState state, {
    String? username,
  }) async {
    await prefs.setString(
      await _scopedKey(username),
      jsonEncode(state.toJson()),
    );
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
