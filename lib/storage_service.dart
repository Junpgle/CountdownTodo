import 'dart:async';
import 'dart:convert';
import 'package:countdown_todo/services/pomodoro_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';

import 'services/api_service.dart';
import 'services/band_sync_service.dart';
import 'services/pomodoro_service.dart';
import 'services/database_helper.dart'; // 🚀 引入 Uni-Sync 新引擎
import 'services/sync_capability_service.dart';
import 'services/sync_oplog_policy.dart';
import 'services/todo_lww_service.dart';
import 'services/storage/app_settings_storage.dart';
import 'services/storage/countdown_storage.dart';
import 'services/storage/habit_storage.dart';
import 'services/storage/pomodoro_storage.dart';
import 'services/storage/storage_conflict_cleanup.dart';
import 'services/storage/user_session_storage.dart';
import 'features/habits/models/habit_checkin.dart';
import 'features/habits/models/habit_goal.dart';
import 'features/habits/models/habit_goal_rule.dart';

class StorageService {
  static final Set<String> recentlyResolvedUuids = {};
  static final Map<String, DateTime> recentlyResolvedTimes = {};

  static bool isRecentlyResolved(String uuid) {
    if (!recentlyResolvedUuids.contains(uuid)) return false;
    final time = recentlyResolvedTimes[uuid];
    if (time == null) return true;
    // 🛡️ [MemoryShield] 竞态阻断锁自动超时阈值定为 30 秒。
    // 超过该时间则认定之前的竞态场景早已结束，自动解锁，以防用户离线等极端同步失败情况下产生死锁。
    if (DateTime.now().difference(time).inSeconds > 30) {
      recentlyResolvedUuids.remove(uuid);
      recentlyResolvedTimes.remove(uuid);
      debugPrint(
          '🔓 [MemoryShield] Timeout auto-released recently resolved item: $uuid');
      return false;
    }
    return true;
  }

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get prefs async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  static String? _lastRecurrenceCheckDate;
  static final Map<String, bool> _recurrenceCheckCache = {};
  static final Set<String> _recurrenceDedupeTombstoneIds = {};

  // UUID v5 namespace dedicated to generated recurrence occurrences. The
  // series ID + local calendar day is the logical identity shared by every
  // device, so concurrent generation converges on one UUID.
  static const String _recurrenceOccurrenceNamespace =
      'f3d51c4a-6d54-5c2f-8be4-1c0b54f4038e';

  // ==========================================
  // 📌 固定日程 (Fixed Schedules)
  // ==========================================

  /// 固定日程使用独立 oplog 实体。旧服务端不声明能力时，
  /// 同步引擎会保留这些 oplog，不会误判为已上传。
  static Future<void> saveFixedSchedules(
    String username,
    List<FixedScheduleItem> items, {
    bool sync = true,
    bool isSyncSource = false,
  }) async {
    if (items.isEmpty) return;
    final deduped = <String, FixedScheduleItem>{};
    for (final item in items) {
      final existing = deduped[item.id];
      if (existing == null ||
          TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: item.updatedAt,
            incomingVersion: item.version,
            currentUpdatedAt: existing.updatedAt,
            currentVersion: existing.version,
          )) {
        deduped[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.database;
    final ids = deduped.keys.toList();
    final existingById = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      final existingRows = await db.query(
        'fixed_schedules',
        where: 'uuid IN ($placeholders)',
        whereArgs: ids,
      );
      for (final row in existingRows) {
        existingById[row['uuid'].toString()] = row;
      }
    }

    final batch = db.batch();
    var wroteAny = false;
    for (final item in deduped.values) {
      final data = item.toJson();
      final existing = existingById[item.id];
      final hasChanged = existing == null ||
          _hasSubstantialChange(existing, data, [
            'title',
            'date',
            'start_time',
            'end_time',
            'status',
            'source',
            'location',
            'remark',
            'reminder_minutes',
            'timezone',
            'recurrence',
            'custom_interval_days',
            'recurrence_series_id',
            'related_todo_ids',
            'external_source',
            'external_id',
            'team_uuid',
            'owner_user_id',
            'device_id',
            'is_deleted',
            'version',
            'created_at',
            'updated_at',
          ]);
      if (!hasChanged) continue;
      wroteAny = true;
      if (!isSyncSource) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'fixed_schedules',
          'target_uuid': item.id,
          'data_json': jsonEncode(data),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }
      batch.insert(
        'fixed_schedules',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    if (wroteAny) await batch.commit(noResult: true);
    if (sync && wroteAny) requestSync(username);
    triggerRefresh();
  }

  static Future<List<FixedScheduleItem>> getFixedSchedules(
    String username, {
    bool includeDeleted = false,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'fixed_schedules',
        where: includeDeleted ? null : 'is_deleted = 0',
        orderBy: 'date ASC, start_time ASC, updated_at DESC',
      );
      return maps.map(FixedScheduleItem.fromJson).toList();
    } catch (error) {
      debugPrint('⚠️ FixedSchedules SQL 引擎异常: $error');
      return const [];
    }
  }

  static Future<List<FixedScheduleItem>> getFixedSchedulesByDay(
    String username,
    DateTime day,
  ) async {
    final date = DateFormat('yyyy-MM-dd').format(day.toLocal());
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'fixed_schedules',
        where: 'is_deleted = 0 AND date = ?',
        whereArgs: [date],
        orderBy: 'start_time ASC, updated_at DESC',
      );
      return maps.map(FixedScheduleItem.fromJson).toList();
    } catch (error) {
      debugPrint('⚠️ FixedSchedules SQL 引擎异常: $error');
      return const [];
    }
  }

  static Future<void> deleteFixedSchedule(
    String username,
    FixedScheduleItem item,
  ) async {
    item.isDeleted = true;
    item.markAsChanged();
    await saveFixedSchedules(username, [item]);
  }

  // ==========================================
  // 🎯 习惯中心 (Habits) 兼容门面
  //
  // 业务实现位于 lib/features/habits/；此处仅保留门面方法，
  // 便于旧调用方与未来同步引擎统一接入。
  // ==========================================

  static Future<List<HabitGoal>> getHabitGoals() =>
      HabitStorage.getHabitGoals();

  static Future<void> saveHabitGoals(List<HabitGoal> items) =>
      HabitStorage.saveHabitGoals(items);

  static Future<List<HabitGoalRuleRevision>> getHabitRules({
    String? habitUuid,
  }) =>
      HabitStorage.getRuleRevisions(habitUuid: habitUuid);

  static Future<void> saveHabitRules(
    List<HabitGoalRuleRevision> items,
  ) =>
      HabitStorage.saveRuleRevisions(items);

  static Future<List<HabitCheckIn>> getHabitCheckIns({
    String? habitUuid,
    String? fromDate,
    String? toDate,
  }) =>
      HabitStorage.getCheckIns(
        habitUuid: habitUuid,
        fromDate: fromDate,
        toDate: toDate,
      );

  static Future<void> saveHabitCheckIns(List<HabitCheckIn> items) =>
      HabitStorage.saveCheckIns(items);

  // ==========================================
  // 📅 规划块 (Plan Blocks)
  // ==========================================

  static Future<void> savePlanBlocks(String username, List<TodoPlanBlock> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final Map<String, TodoPlanBlock> dedupeMap = {};
    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final dedupeList = dedupeMap.values.toList();
    final db = await DatabaseHelper.instance.database;

    // 🚀 批量获取现有数据，用于审计
    Map<String, Map<String, dynamic>> existingItemsMap = {};
    if (!isSyncSource && dedupeList.isNotEmpty) {
      final uuids = dedupeList.map((e) => "'${e.id}'").join(',');
      final List<Map<String, dynamic>> existing = await db
          .rawQuery('SELECT * FROM todo_plan_blocks WHERE uuid IN ($uuids)');
      for (var row in existing) {
        existingItemsMap[row['uuid']] = row;
      }
    }

    final batch = db.batch();
    for (var item in dedupeList) {
      bool hasChanged = true;
      final itemData = item.toDbJson();
      final oldData = existingItemsMap[item.id];
      if (oldData != null) {
        hasChanged = _hasSubstantialChange(oldData, itemData, [
          'todo_uuid',
          'title_snapshot',
          'start_time',
          'end_time',
          'planned_minutes',
          'status',
          'actual_focus_seconds',
          'pomodoro_record_ids',
          'source',
          'remark',
          'reminder_minutes',
          'pomodoro_minutes',
          'pomodoro_rounds',
          'calendar_event_id',
          'is_deleted',
          'version',
          'updated_at'
        ]);
      }

      if (!isSyncSource && hasChanged) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todo_plan_blocks',
          'target_uuid': item.id,
          'data_json': jsonEncode(itemData),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }

      if (hasChanged || oldData == null) {
        batch.insert('todo_plan_blocks', itemData,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    if (dedupeList.isNotEmpty) {
      await batch.commit(noResult: true);
    }

    if (sync) requestSync(username);
    triggerRefresh();
  }

  static Future<List<TodoPlanBlock>> getPlanBlocks(String username,
      {bool includeDeleted = false}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query('todo_plan_blocks',
          where: includeDeleted ? null : 'is_deleted = 0');

      if (maps.isNotEmpty) {
        if (maps.length > 50) {
          return await compute(_parsePlanBlockItemsIsolate, maps);
        }
        return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ PlanBlocks SQL 引擎异常: $e");
    }
    return [];
  }

  static List<TodoPlanBlock> _parsePlanBlockItemsIsolate(
      List<Map<String, dynamic>> maps) {
    return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
  }

  static Future<void> deletePlanBlockGlobally(
      String username, String idToDelete) async {
    final blocks = await getPlanBlocks(username, includeDeleted: true);
    final index = blocks.indexWhere((b) => b.id == idToDelete);
    if (index != -1) {
      blocks[index].isDeleted = true;
      blocks[index].markAsChanged();
      await savePlanBlocks(username, [blocks[index]], sync: true);
    }
  }

  static Future<List<TodoPlanBlock>> getPlanBlocksByTodo(
      String username, String todoId) async {
    final all = await getPlanBlocks(username);
    return all.where((b) => b.todoId == todoId).toList();
  }

  static Future<List<TodoPlanBlock>> getPlanBlocksByDay(
      String username, DateTime day) async {
    final startOfDay =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final endOfDay =
        DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;

    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'todo_plan_blocks',
        where: 'is_deleted = 0 AND start_time >= ? AND start_time < ?',
        whereArgs: [startOfDay, endOfDay],
        orderBy: 'start_time ASC',
      );

      if (maps.isNotEmpty) {
        if (maps.length > 50) {
          return await compute(_parsePlanBlockItemsIsolate, maps);
        }
        return maps.map((m) => TodoPlanBlock.fromJson(m)).toList();
      }
    } catch (e) {
      debugPrint("⚠️ PlanBlocks SQL 引擎异常: $e");
    }
    return [];
  }

  // --- 常量定义 ---
  static const String keyUsers = "users_data";
  static const String keyLeaderboard = "leaderboard_data";
  static const String keySettings = "quiz_settings";
  static const String keyCurrentUser = "current_login_user";
  static const String keyTodos = "user_todos";
  static const String keyTodoGroups = "user_todo_groups";
  static const String keyCountdowns = "user_countdowns";
  static const String keyScreenTimeCache = "screen_time_cache";
  static const String keyLastScreenTimeSync = "last_screen_time_sync";
  static const String keyScreenTimeHistory = "screen_time_history";
  static const String keyAppMappings = "app_category_mappings";
  static const String keyLastMappingsSync = "last_mappings_sync";
  static const String keyAuthToken = "auth_session_token";
  static const String keyDeviceId = "app_device_uuid";
  static const String keySyncInterval = "app_sync_interval";
  static const String keyThemeMode = "app_theme_mode";
  static const String keyThemeColorMode = "app_theme_color_mode";
  static const String keyCustomThemeColor = "app_custom_theme_color";
  static const String keyLastAutoSync = "last_auto_sync_time";
  static const String keySemesterProgressEnabled = "semester_progress_enabled";
  static const String keySemesterStart = "semester_start_date";
  static const String keySemesterEnd = "semester_end_date";
  static const String keySemesters = "semesters_list"; // 多学期列表
  static const String keyActiveSemester = "active_semester_id"; // 当前活跃学期
  static const String keyTimeLogs = "user_time_logs";
  static const String keyIgnoredScheduleConflicts =
      "ignored_schedule_conflicts";
  static const String keyConflictDetectionEnabled =
      "conflict_detection_enabled";
  static const String keyServerChoice = "app_server_choice";
  static const String keySystemStartupEnabled = "system_startup_enabled";
  static const String keyPrivacyAgreed = "privacy_policy_agreed";
  static const String keyPrivacyDate = "privacy_policy_date";
  static const String keyPrivacyCachedVersion = "privacy_policy_cached_version";
  static const String keyPrivacyCacheTime = "privacy_policy_cache_time";
  static const String privacyRawUrl =
      'https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/PRIVACY_POLICY.md';
  static const Duration privacyCacheDuration = Duration(hours: 1);

  static const String keyLocalScreenTime = "local_screen_time_pending_upload";

  static const String keyLlmRetryCount = "llm_retry_count";
  static const String keyPendingTodoConfirm = "pending_todo_confirm";
  static const String keyWallpaperProvider = "app_wallpaper_provider";
  static const String keyWallpaperImageFormat = "app_wallpaper_image_format";
  static const String keyWallpaperIndex = "app_wallpaper_index";
  static const String keyWallpaperMkt = "app_wallpaper_mkt";
  static const String keyWallpaperResolution = "app_wallpaper_resolution";
  static const String keyWallpaperCacheCleanupTime =
      "app_wallpaper_cache_cleanup_time";
  static const String keyWallpaperCustomPath = "app_wallpaper_custom_path";

  // Notification settings keys
  static const String keyNotifyLiveEnabled = "notify_live_activity_enabled";
  static const String keyNotifyNormalEnabled = "notify_normal_enabled";
  static const String keyNotifyCourseEnabled = "notify_course_enabled";
  static const String keyNotifyQuizEnabled = "notify_quiz_enabled";
  static const String keyNotifyTodoSummaryEnabled =
      "notify_todo_summary_enabled";
  static const String keyNotifyAppUpdatesEnabled = "notify_app_updates_enabled";
  static const String keyTodoFoldersInline = "todo_folders_inline";
  static const String keyTodoFolderDisplayMode = "todo_folder_display_mode";
  static const String keyNotifySpecialTodoEnabled =
      "notify_special_todo_enabled";
  static const String keyNotifyPomodoroEnabled = "notify_pomodoro_enabled";
  static const String keyNotifyTodoRecognizeEnabled =
      "notify_todo_recognize_enabled";
  static const String keyNotifyPomodoroEndEnabled =
      "notify_pomodoro_end_enabled";
  static const String keyNotifyTodoLiveEnabled = "notify_todo_live_enabled";
  static const String keyNotifyReminderEnabled = "notify_reminder_enabled";
  static const String keyCourseReminderMinutes = "course_reminder_minutes";
  static const String keyLastCourseImportUrl = "last_course_import_url";
  static const String keyCategoryReminderMinutes = "category_reminder_minutes";
  static const String keyWindowsScheduledReminders =
      "windows_scheduled_reminders";

  static bool _isSyncing = false;
  static Set<String> _pendingSyncOplogUuids = {}; // 🚀 同步前有待同步 oplog 的 UUID
  static Set<String> _forceFlushProtectedUuids =
      {}; // 🚀 force-flush 保护的 UUID，merge 时跳过
  static final Set<String> _attemptedRecurrenceSeriesRepairUploads = {};
  static bool _isCheckingRecurrence = false; // 🚀 递归锁，防止 getTodos 陷入重复任务检查死循环
  static ValueNotifier<String> themeNotifier = ValueNotifier('system');
  static ValueNotifier<String> themeColorModeNotifier =
      ValueNotifier('default');
  static ValueNotifier<Color?> customThemeColorNotifier = ValueNotifier(null);
  static ValueNotifier<Color?> appWallpaperColorNotifier = ValueNotifier(null);
  static final Map<String, Future<List<TodoItem>>> _inflightTodoRequests = {};
  static final ValueNotifier<Map<String, dynamic>> conflictScanNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'isScanning': false,
    'progress': 0,
    'current': 0,
    'total': 0,
    'message': '',
  });

  static final ValueNotifier<int> dataRefreshNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> wallpaperRefreshNotifier =
      ValueNotifier<int>(0);
  static Timer? _refreshDebouncer;
  static Timer? _syncDebouncer;
  static String? _queuedSyncUsername;
  static int _lastSyncRequestAt = 0;
  static const Duration _minSyncInterval = Duration(milliseconds: 3400);

  /// 🚀 优化：增加 100ms 防抖，防止背景同步或批量更新时产生高频重绘，减少主线程 GC 与帧丢弃
  static void triggerRefresh() {
    _refreshDebouncer?.cancel();
    _refreshDebouncer = Timer(const Duration(milliseconds: 100), () {
      dataRefreshNotifier.value++;
    });
  }

  static void triggerWallpaperRefresh() {
    wallpaperRefreshNotifier.value++;
  }

  static void setForceFlushProtectedUuids(Set<String> uuids) {
    _forceFlushProtectedUuids = uuids;
  }

  static Future<void> _updateOplogRowsByIds(
    Database db,
    Set<int> ids,
    Map<String, Object?> values,
  ) async {
    const chunkSize = 500;
    final orderedIds = ids.toList()..sort();
    for (var start = 0; start < orderedIds.length; start += chunkSize) {
      final end = start + chunkSize < orderedIds.length
          ? start + chunkSize
          : orderedIds.length;
      final chunk = orderedIds.sublist(start, end);
      if (chunk.isEmpty) continue;
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.update(
        'op_logs',
        values,
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  static void requestSync(String username) {
    if (username.isEmpty) return;
    _queuedSyncUsername = username;
    if (_syncDebouncer != null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastSyncRequestAt;
    final delayMs = _isSyncing
        ? _minSyncInterval.inMilliseconds
        : (_minSyncInterval.inMilliseconds - elapsed)
            .clamp(0, _minSyncInterval.inMilliseconds);

    _scheduleQueuedSync(Duration(milliseconds: delayMs));
  }

  static void _scheduleQueuedSync(Duration delay) {
    _syncDebouncer?.cancel();
    _syncDebouncer = Timer(delay, () {
      _syncDebouncer = null;
      if (_isSyncing) {
        _scheduleQueuedSync(_minSyncInterval);
        return;
      }

      final username = _queuedSyncUsername;
      _queuedSyncUsername = null;
      if (username == null || username.isEmpty) return;
      unawaited(syncData(username));
    });
  }

  static int _normalizedRecurrenceIndex(TodoItem item) {
    final int idx = item.recurrence.index;
    return idx >= 0 && idx < RecurrenceType.values.length ? idx : 0;
  }

  static int _normalizedCustomIntervalDays(TodoItem item) {
    final int? raw = item.customIntervalDays;
    if (item.recurrence == RecurrenceType.customDays) {
      return (raw != null && raw > 0) ? raw : 1;
    }
    return (raw != null && raw >= 0) ? raw : 0;
  }

  static int? _parseNullableInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  // --- 🚀 Uni-Sync 4.0: 忽略项管理 ---

  /// 将特定的远端项加入忽略列表，防止其再次被同步回来
  static Future<void> ignoreRemoteItem({
    required String table,
    required String uuid,
    String? teamUuid,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
        'ignored_remote_items',
        {
          'uuid': uuid,
          'team_uuid': teamUuid,
          'table_name': table,
          'ignored_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint("🚫 [忽略项] 已记录 $table.$uuid 至忽略表");
  }

  /// 移除忽略记录
  static Future<void> unignoreRemoteItem(String uuid) async {
    final db = await DatabaseHelper.instance.database;
    await db
        .delete('ignored_remote_items', where: 'uuid = ?', whereArgs: [uuid]);
  }

  /// 检查项是否被忽略
  static Future<bool> isItemIgnored(String uuid) async {
    final db = await DatabaseHelper.instance.database;
    final results = await db
        .query('ignored_remote_items', where: 'uuid = ?', whereArgs: [uuid]);
    return results.isNotEmpty;
  }

  static String _todoRequestKey(
    String username, {
    required bool includeDeleted,
    required int? limit,
  }) {
    return '$username|includeDeleted=$includeDeleted|limit=${limit ?? "all"}';
  }

  static List<TodoItem> _cloneTodoItems(List<TodoItem> items) {
    return items.map((item) => TodoItem.fromJson(item.toJson())).toList();
  }

  static Future<void> _clearTodoPrefsMirror(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("${keyTodos}_$username");
    await prefs.remove(keyTodos);
  }

  static String _scopedKey(String baseKey, String? username) {
    if (username == null || username.isEmpty) return baseKey;
    return "${baseKey}_$username";
  }

  // ==========================================
  // 🛡️ 设备信息与标识管理 (解决未知设备问题)
  // ==========================================

  /// 获取设备唯一 UUID (用于后端同步过滤)
  static Future<String> getDeviceFriendlyName() async =>
      UserSessionStorage.getDeviceFriendlyName();

  // ==========================================
  // 基础身份获取 (Auth Identity)
  // ==========================================
  static Future<String?> getCurrentUsername() =>
      UserSessionStorage.getCurrentUsername();

  static Future<bool> rollbackLocalItem(
      String table, int logId, String username) async {
    try {
      // 1. 执行 SQL 层的物理回滚
      final success = await DatabaseHelper.instance.rollbackFromLocalLog(logId);
      if (!success) return false;

      // 2. 🚀 关键：立即从 DB 重载该表的数据并刷新内存/Prefs 缓存
      if (table == 'todos') {
        final List<TodoItem> freshTodos =
            await DatabaseHelper.instance.getTodos();
        await saveTodos(username, freshTodos, sync: false, isSyncSource: true);
      } else if (table == 'countdowns') {
        final List<CountdownItem> freshCds =
            await DatabaseHelper.instance.getCountdowns();
        await saveCountdowns(username, freshCds,
            sync: false, isSyncSource: true);
      }

      // 3. 触发 UI 刷新信号
      triggerRefresh();
      return true;
    } catch (e) {
      debugPrint("❌ rollbackLocalItem error: $e");
      return false;
    }
  }

  static Future<String> getDeviceId() => UserSessionStorage.getDeviceId();

  // ==========================================
  // 基础配置与用户系统
  // ==========================================
  static Future<void> initTheme() async {
    final prefs = await StorageService.prefs;
    themeNotifier.value = prefs.getString(keyThemeMode) ?? 'system';
    themeColorModeNotifier.value =
        prefs.getString(keyThemeColorMode) ?? 'default';
    int? colorVal = prefs.getInt(keyCustomThemeColor);
    if (colorVal != null) {
      customThemeColorNotifier.value = Color(colorVal);
    }
  }

  static Future<bool> register(String username, String password) =>
      UserSessionStorage.register(username, password);

  static Future<bool> login(String username, String password) =>
      UserSessionStorage.login(username, password);

  static Future<void> saveLoginSession(String username, {String? token}) =>
      UserSessionStorage.saveLoginSession(username, token: token);

  static Future<String?> getLoginSession() =>
      UserSessionStorage.getLoginSession();

  static Future<void> clearLoginSession() =>
      UserSessionStorage.clearLoginSession();

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keySettings, jsonEncode(settings));
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(keySettings);
    if (jsonStr != null) return Map<String, dynamic>.from(jsonDecode(jsonStr));
    return {
      'operators': ['+', '-'],
      'min_num1': 0,
      'max_num1': 50,
      'min_num2': 0,
      'max_num2': 50,
      'max_result': 100,
    };
  }

  static Future<void> saveWindowsScheduledReminders(
      List<Map<String, dynamic>> reminders) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keyWindowsScheduledReminders, jsonEncode(reminders));
  }

  static Future<List<Map<String, dynamic>>>
      getWindowsScheduledReminders() async {
    final prefs = await StorageService.prefs;
    String? jsonStr = prefs.getString(keyWindowsScheduledReminders);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint("解析 Windows 预约提醒失败: $e");
      return [];
    }
  }

  static Future<void> savePomodoroTags(
          String username, List<Map<String, dynamic>> tags) =>
      PomodoroStorage.savePomodoroTags(username, tags);

  // ==========================================
  // 测验历史与排行榜
  // ==========================================
  static Future<void> saveHistory(
      String username, int score, int duration, String details) async {
    final prefs = await SharedPreferences.getInstance();
    String key = "history_$username";
    List<String> history = prefs.getStringList(key) ?? [];
    Map<String, dynamic> recordMap = {
      'date': DateTime.now().toIso8601String(),
      'score': score,
      'duration': duration,
      'details': details
    };
    history.insert(0, jsonEncode(recordMap));
    await prefs.setStringList(key, history);
  }

  static Future<List<String>> getHistory(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList("history_$username") ?? [];
    return rawList.map((item) {
      try {
        var map = jsonDecode(item);
        if (map is Map) {
          String timeStr = DateFormat('yyyy-MM-dd HH:mm:ss')
              .format(DateTime.parse(map['date']));
          return "时间: $timeStr\n得分: ${map['score']}\n用时: ${map['duration']}秒\n详情:\n${map['details']}\n-----------------";
        }
        return item;
      } catch (e) {
        return item;
      }
    }).toList();
  }

  static Future<Map<String, dynamic>> getMathStats(String username) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawList = prefs.getStringList("history_$username") ?? [];
    int totalQuestions = 0, totalCorrect = 0, bestTime = 999999, todayCount = 0;
    bool hasPerfectScore = false;
    DateTime now = DateTime.now();
    for (var item in rawList) {
      try {
        var map = jsonDecode(item);
        int score = map['score'], duration = map['duration'];
        if (map['date'] != null) {
          DateTime date = DateTime.parse(map['date']);
          if (date.year == now.year &&
              date.month == now.month &&
              date.day == now.day) {
            todayCount++;
          }
        }
        totalQuestions += 10;
        totalCorrect += (score ~/ 10);
        if (score == 100) {
          hasPerfectScore = true;
          if (duration < bestTime) bestTime = duration;
        }
      } catch (e) {
        RegExp scoreReg = RegExp(r"得分: (\d+)");
        var match = scoreReg.firstMatch(item);
        if (match != null) {
          int score = int.parse(match.group(1)!);
          totalQuestions += 10;
          totalCorrect += (score ~/ 10);
        }
      }
    }
    double accuracy =
        totalQuestions == 0 ? 0.0 : (totalCorrect / totalQuestions);
    return {
      'accuracy': accuracy,
      'bestTime': hasPerfectScore ? bestTime : null,
      'todayCount': todayCount
    };
  }

  static Future<void> updateLeaderboard(
      String username, int score, int duration) async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> list = [];
    String? jsonStr = prefs.getString(keyLeaderboard);
    if (jsonStr != null) list = jsonDecode(jsonStr);
    list.add({'username': username, 'score': score, 'time': duration});
    list.sort((a, b) {
      if (a['score'] != b['score']) return b['score'].compareTo(a['score']);
      return a['time'].compareTo(b['time']);
    });
    if (list.length > 10) list = list.sublist(0, 10);
    await prefs.setString(keyLeaderboard, jsonEncode(list));
    requestSync(username);
  }

  static Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(keyLeaderboard);
    if (jsonStr == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(jsonStr));
  }

  // ==========================================
  // 倒计时 (Countdowns)
  // ==========================================
  static Future<void> saveCountdowns(String username, List<CountdownItem> items,
          {bool sync = true, bool isSyncSource = false}) =>
      CountdownStorage.saveCountdowns(
        username,
        items,
        sync: sync,
        isSyncSource: isSyncSource,
        hasSubstantialChange: _hasSubstantialChange,
        recordLocalAudit: _recordLocalAuditOptimized,
        requestSync: requestSync,
        onCommitted: _inflightTodoRequests.clear,
      );

  static Future<void> _clearGhostConflictFlags(dynamic db) =>
      StorageConflictCleanup.clearGhostConflictFlags(db);

  static Future<List<CountdownItem>> getCountdowns(String username,
          {bool includeDeleted = false}) =>
      CountdownStorage.getCountdowns(
        username,
        includeDeleted: includeDeleted,
        saveMigratedCountdowns: saveCountdowns,
      );

  static Future<void> deleteCountdownGlobally(
      String username, String idToDelete) async {
    List<CountdownItem> localCds = await getCountdowns(username);
    int index = localCds.indexWhere((t) => t.id == idToDelete);
    if (index != -1) {
      localCds[index].isDeleted = true;
      try {
        localCds[index].markAsChanged();
      } catch (_) {
        localCds[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
        localCds[index].version += 1;
      }
      await saveCountdowns(username, localCds, sync: true);
    }
  }

  // ==========================================
  // 待办事项 (Todos)
  // ==========================================
  static Future<void> saveTodos(String username, List<TodoItem> items,
      {bool sync = true,
      bool isSyncSource = false,
      bool recomputeScheduleConflicts = true}) async {
    final Map<String, TodoItem> dedupeMap = {};

    // 🚀 核心优化：只有在非同步源保存时才清理，防止 saveTodos -> getTodos 循环触发
    if (sync && !isSyncSource) {
      _recurrenceCheckCache.clear();
    }

    for (var item in items) {
      if (item.recurrence != RecurrenceType.none &&
          (item.recurrenceSeriesId == null ||
              item.recurrenceSeriesId!.isEmpty)) {
        item.recurrenceSeriesId = item.id;
      }
      final existing = dedupeMap[item.id];
      if (existing == null ||
          TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: item.updatedAt,
            incomingVersion: item.version,
            currentUpdatedAt: existing.updatedAt,
            currentVersion: existing.version,
          )) {
        dedupeMap[item.id] = item;
      }
    }

    List<TodoItem> dedupeList = dedupeMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // SQL 已是主存储。超大 Todo 列表写回 SharedPreferences 会在 Android 上触发 OOM，
    // 因此这里仅清理旧镜像，不再持续维护整份 prefs 缓存。
    unawaited(_clearTodoPrefsMirror(username));

    final db = await DatabaseHelper.instance.database;

    // 🚀 核心优化：批量获取现有数据，用于审计对比，避免循环中重复查询 DB
    Map<String, Map<String, dynamic>> existingItemsMap = {};
    if (!isSyncSource && dedupeList.isNotEmpty) {
      final List<Map<String, dynamic>> existing =
          await DatabaseHelper.instance.getTodoMaps(
        includeDeleted: true,
        uuids: dedupeList.map((e) => e.id).toList(),
        includeConflictData: true,
      );
      for (var row in existing) {
        existingItemsMap[row['uuid']] = row;
      }
    }
    // 🚀 同步写入时，查询 force-flush 保护或有待同步 oplog 的待办的 is_completed，防止同步覆盖用户本地修改
    // 优先级：force-flush > pending oplog > normal sync
    Map<String, int> existingCompletionMap = {};
    if (isSyncSource && dedupeList.isNotEmpty) {
      // 同步请求返回后到真正落库前，UI 仍可能产生新的完成/取消完成操作。
      // 在写入边界再读一次 oplog，避免仅依赖请求结束时的内存快照。
      final allItemIds = dedupeList.map((item) => item.id).toList();
      const chunkSize = 500;
      for (var start = 0; start < allItemIds.length; start += chunkSize) {
        final end = start + chunkSize < allItemIds.length
            ? start + chunkSize
            : allItemIds.length;
        final chunk = allItemIds.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await db.query(
          'op_logs',
          columns: const ['target_uuid'],
          where:
              "is_synced = 0 AND target_table = 'todos' AND target_uuid IN ($placeholders)",
          whereArgs: chunk,
        );
        _pendingSyncOplogUuids.addAll(
          rows
              .map((row) => row['target_uuid']?.toString() ?? '')
              .where((uuid) => uuid.isNotEmpty),
        );
      }
    }
    if (isSyncSource &&
        dedupeList.isNotEmpty &&
        (_forceFlushProtectedUuids.isNotEmpty ||
            _pendingSyncOplogUuids.isNotEmpty)) {
      final localPrefs = await prefs;
      final int currentUserId = localPrefs.getInt('current_user_id') ?? 0;
      if (currentUserId > 0) {
        // 需要保护的 UUID = force-flush 的 + pending oplog 的
        final uuidsToPreserve = dedupeList
            .where((item) =>
                _forceFlushProtectedUuids.contains(item.id) ||
                _pendingSyncOplogUuids.contains(item.id))
            .map((item) => item.id)
            .toList();
        if (uuidsToPreserve.isNotEmpty) {
          final placeholders =
              List.filled(uuidsToPreserve.length, '?').join(',');
          final rows = await db.rawQuery(
            'SELECT t.uuid, CASE WHEN t.collab_type = 1 AND c.is_completed IS NOT NULL THEN c.is_completed ELSE t.is_completed END AS is_completed '
            'FROM todos t LEFT JOIN todo_completions c ON t.uuid = c.todo_uuid AND c.user_id = ? '
            'WHERE t.uuid IN ($placeholders)',
            [currentUserId, ...uuidsToPreserve],
          );
          for (var row in rows) {
            existingCompletionMap[row['uuid'] as String] =
                (row['is_completed'] as int?) ?? 0;
          }
          //debugPrint(
          //  '🧪 [SyncDiag][saveTodos-sync] preserving ${existingCompletionMap.length} protected completions (force-flush=${_forceFlushProtectedUuids.length}, pending-oplog=${_pendingSyncOplogUuids.length})');
        }
      }
    }

    // 🚀 Batch 极速批量写入
    final batch = db.batch();
    for (var item in dedupeList) {
      bool hasChanged = true;
      final oldData = existingItemsMap[item.id];

      if (oldData != null) {
        // 检测是否有实质性变更，如果没有则跳过审计和 Oplog
        hasChanged = _hasSubstantialChange(oldData, item.toJson(), [
          'content',
          'title',
          'remark',
          'is_completed',
          'is_deleted',
          'due_date',
          'group_id',
          'recurrence',
          'recurrence_series_id',
          'is_all_day',
          'reminder_minutes',
          'has_conflict',
          'conflict_data',
          'image_path',
          'original_text',
          'version',
          'updated_at',
        ]);
      }

      if (!isSyncSource && hasChanged) {
        final syncPayload = _stripClientOnlyConflictForSync(item.toJson());
        if (item.isDeleted && _recurrenceDedupeTombstoneIds.contains(item.id)) {
          syncPayload['_recurrence_delete_reason'] = 'dedupe';
        }
        // 记录审计日志 (传入已有的 oldData 避免再次查询)
        unawaited(_recordLocalAuditOptimized(
            'todos', item.id, item.toJson(), item.teamUuid, oldData));

        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todos',
          'target_uuid': item.id,
          'data_json': jsonEncode(syncPayload),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
        //if (!isSyncSource) {
        //debugPrint(
        //    '🧪 [SyncDiag][oplog] CREATE UUID=${item.id} isDone=${item.isDone} is_completed=${item.isDone ? 1 : 0} collabType=${item.collabType}');
        //}
      }

      if (hasChanged || oldData == null) {
        // 🚀 同步写入时，如果有待同步 oplog，保留 DB 中的 is_completed，
        // 防止 syncData 的 saveTodos 覆盖用户本地修改（force-flush 写入的值）
        final int isCompleted;
        if (isSyncSource && existingCompletionMap.containsKey(item.id)) {
          isCompleted = existingCompletionMap[item.id]!;
          /*debugPrint(
              '🧪 [SyncDiag][saveTodos-sync] PRESERVED UUID=${item.id} isCompleted=$isCompleted');
              */
        } else {
          isCompleted = item.isDone ? 1 : 0;
          if (isSyncSource) {
            /*debugPrint(
                '🧪 [SyncDiag][saveTodos-sync] OVERWRITE UUID=${item.id} isCompleted=$isCompleted (from merge)');
          */
          }
        }
        batch.insert(
            'todos',
            {
              'uuid': item.id,
              'content': item.title,
              'remark': item.remark,
              'team_uuid': item.teamUuid,
              'team_name': item.teamName,
              'creator_id': item.creatorId,
              'creator_name': item.creatorName,
              'is_completed': isCompleted,
              'is_deleted': item.isDeleted ? 1 : 0,
              'version': item.version,
              'due_date': item.dueDate?.millisecondsSinceEpoch ?? 0,
              'group_id': item.groupId,
              'created_date': item.createdDate ?? item.createdAt,
              'created_at': item.createdAt,
              'updated_at': item.updatedAt,
              'collab_type': item.collabType,
              'recurrence': _normalizedRecurrenceIndex(item),
              'recurrence_series_id': item.recurrenceSeriesId,
              'custom_interval_days': _normalizedCustomIntervalDays(item),
              'recurrence_end_date':
                  item.recurrenceEndDate?.millisecondsSinceEpoch ?? 0,
              'reminder_minutes': item.reminderMinutes ?? -1,
              'is_all_day': item.isAllDay ? 1 : 0,
              'has_conflict': item.hasConflict ? 1 : 0,
              'image_path': item.imagePath,
              'original_text': item.originalText,
              'conflict_data': item.serverVersionData != null
                  ? jsonEncode(item.serverVersionData)
                  : null,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    if (dedupeList.isNotEmpty) {
      await batch.commit(noResult: true);
      _inflightTodoRequests.clear();

      // 🚀 针对各自独立团队待办（collabType == 1），同步写入 todo_completions
      if (!isSyncSource) {
        try {
          final localPrefs = await prefs;
          final int userId = localPrefs.getInt('current_user_id') ?? 0;
          if (userId > 0) {
            final compBatch = db.batch();
            for (var item in dedupeList) {
              if (item.collabType == 1) {
                compBatch.insert(
                    'todo_completions',
                    {
                      'todo_uuid': item.id,
                      'user_id': userId,
                      'is_completed': item.isDone ? 1 : 0,
                      'updated_at': DateTime.now().millisecondsSinceEpoch,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace);
              }
            }
            await compBatch.commit(noResult: true);
          }
        } catch (e) {
          debugPrint("⚠️ StorageService: 写入本地 todo_completions 状态失败: $e");
        }
      }
    }

    if (recomputeScheduleConflicts) {
      await _refreshTodoScheduleConflicts(username);
    }

    if (sync) requestSync(username);
    Future.microtask(() => _syncTodosToBand(dedupeList));
    triggerRefresh();
  }

  static bool _hasSubstantialChange(Map<String, dynamic> before,
      Map<String, dynamic> after, List<String> fields) {
    for (var field in fields) {
      var valA = after[field];
      var valB = before[field];

      // 归一化处理
      bool isAEmpty = valA == null ||
          valA == 0 ||
          valA == "" ||
          valA == false ||
          (field == 'reminder_minutes' && valA == -1);
      bool isBEmpty = valB == null ||
          valB == 0 ||
          valB == "" ||
          valB == false ||
          (field == 'reminder_minutes' && valB == -1);

      if (isAEmpty && isBEmpty) continue;
      if (isAEmpty || isBEmpty) return true;
      if (valA != valB) return true;
    }
    return false;
  }

  static Future<void> _refreshTodoScheduleConflicts(String username) async {
    try {
      final allTodos = await getTodos(username, includeDeleted: true);
      if (!await getConflictDetectionEnabled()) {
        if (_clearLocalTodoScheduleConflicts(allTodos)) {
          await saveTodos(
            username,
            allTodos,
            sync: false,
            isSyncSource: true,
            recomputeScheduleConflicts: false,
          );
        }
        return;
      }
      final ignoredKeys = await _getIgnoredScheduleConflictKeys(username);
      if (_recomputeLocalTodoScheduleConflicts(allTodos,
          ignoredScheduleConflictKeys: ignoredKeys)) {
        await saveTodos(
          username,
          allTodos,
          sync: false,
          isSyncSource: true,
          recomputeScheduleConflicts: false,
        );
      }
    } catch (e) {
      debugPrint('refreshTodoScheduleConflicts error: $e');
    }
  }

  static Future<Map<String, int>> scanAllTodoConflicts(String username) async {
    final allTodos = await getTodos(username, includeDeleted: true);
    if (!await getConflictDetectionEnabled()) {
      final changed = _clearLocalTodoScheduleConflicts(allTodos);
      try {
        if (changed) {
          await saveTodos(
            username,
            allTodos,
            sync: false,
            isSyncSource: true,
            recomputeScheduleConflicts: false,
          );
        } else {
          triggerRefresh();
        }
      } finally {
        conflictScanNotifier.value = {
          'isScanning': false,
          'progress': 100,
          'current': allTodos.length,
          'total': allTodos.length,
          'message': '冲突检测已关闭',
        };
      }
      return {
        'total': 0,
        'personal_personal': 0,
        'personal_team': 0,
        'team_team': 0,
      };
    }
    final ignoredKeys = await _getIgnoredScheduleConflictKeys(username);
    final changed = _recomputeLocalTodoScheduleConflicts(
      allTodos,
      ignoredScheduleConflictKeys: ignoredKeys,
      onProgress: (current, total, message) {
        final progress = total <= 0 ? 0 : ((current / total) * 100).round();
        conflictScanNotifier.value = {
          'isScanning': true,
          'progress': progress.clamp(0, 100),
          'current': current,
          'total': total,
          'message': message,
        };
      },
    );

    try {
      if (changed) {
        await saveTodos(
          username,
          allTodos,
          sync: false,
          isSyncSource: true,
          recomputeScheduleConflicts: false,
        );
      } else {
        triggerRefresh();
      }
    } finally {
      conflictScanNotifier.value = {
        'isScanning': false,
        'progress': 100,
        'current': allTodos.length,
        'total': allTodos.length,
        'message': '扫描完成',
      };
    }

    int total = 0;
    int personalPersonal = 0;
    int personalTeam = 0;
    int teamTeam = 0;

    for (final todo in allTodos) {
      if (todo.isDeleted) continue;
      if (!todo.hasConflict) continue;
      final data = todo.serverVersionData;
      if (!_isLocalScheduleConflict(data)) continue;
      total++;
      switch (data?['relation_type']) {
        case 'personal_personal':
          personalPersonal++;
          break;
        case 'personal_team':
          personalTeam++;
          break;
        case 'team_team':
          teamTeam++;
          break;
      }
    }

    return {
      'total': total,
      'personal_personal': personalPersonal,
      'personal_team': personalTeam,
      'team_team': teamTeam,
    };
  }

  static Future<void> clearLocalTodoScheduleConflicts(String username) async {
    final allTodos = await getTodos(username, includeDeleted: true);
    if (!_clearLocalTodoScheduleConflicts(allTodos)) return;
    await saveTodos(
      username,
      allTodos,
      sync: false,
      isSyncSource: true,
      recomputeScheduleConflicts: false,
    );
  }

  static Future<void> ignoreLocalScheduleConflict(
      String username, TodoItem item) async {
    final data = item.serverVersionData;
    if (!_isLocalScheduleConflict(data)) return;

    final ignoredKeys = await _getIgnoredScheduleConflictKeys(username);
    final startMs =
        _parseMillis(data?['start_time']) ?? item.createdDate ?? item.createdAt;
    final endMs =
        _parseMillis(data?['end_time']) ?? item.dueDate?.millisecondsSinceEpoch;
    if (startMs <= 0 || endMs == null || endMs <= 0) return;

    final peers = data?['conflict_with'];
    if (peers is List) {
      for (final peer in peers) {
        if (peer is! Map) continue;
        final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
        final peerStart = _parseMillis(peer['start_time']);
        final peerEnd = _parseMillis(peer['end_time']);
        if (peerId.isEmpty || peerStart == null || peerEnd == null) continue;
        ignoredKeys.add(_scheduleConflictPairKey(
          item.id,
          startMs,
          endMs,
          peerId,
          peerStart,
          peerEnd,
        ));
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _scopedKey(keyIgnoredScheduleConflicts, username),
      ignoredKeys.toList()..sort(),
    );

    final allTodos = await getTodos(username, includeDeleted: true);
    var changed = false;
    for (final todo in allTodos) {
      final conflictData = todo.serverVersionData;
      if (!_isLocalScheduleConflict(conflictData)) continue;

      if (todo.id == item.id) {
        todo.hasConflict = false;
        todo.serverVersionData = null;
        changed = true;
        continue;
      }

      final peers = conflictData?['conflict_with'];
      if (peers is! List) continue;
      final containsIgnoredItem = peers.any((peer) {
        if (peer is! Map) return false;
        final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
        return peerId == item.id;
      });
      if (containsIgnoredItem) {
        todo.hasConflict = false;
        todo.serverVersionData = null;
        changed = true;
      }
    }

    if (changed) {
      _recomputeLocalTodoScheduleConflicts(
        allTodos,
        ignoredScheduleConflictKeys: ignoredKeys,
      );
      await saveTodos(
        username,
        allTodos,
        sync: false,
        isSyncSource: true,
        recomputeScheduleConflicts: false,
      );
    }
  }

  static Future<Set<String>> _getIgnoredScheduleConflictKeys(
      String username) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(
              _scopedKey(keyIgnoredScheduleConflicts, username),
            ) ??
            const <String>[])
        .toSet();
  }

  static Future<void> _recordLocalAuditOptimized(
      String table,
      String uuid,
      Map<String, dynamic> afterData,
      String? teamUuid,
      Map<String, dynamic>? existingData) async {
    try {
      if (existingData == null) {
        await DatabaseHelper.instance.insertLocalAuditLog(
          userId: ApiService.currentUserId,
          targetTable: table,
          targetUuid: uuid,
          opType: 'INSERT',
          beforeData: null,
          afterData: afterData,
          teamUuid: teamUuid,
          operatorName: '本人(离线)',
        );
        return;
      }

      // 已经在外部做过实质性变更检测了，此处直接记录
      await DatabaseHelper.instance.insertLocalAuditLog(
        userId: ApiService.currentUserId,
        targetTable: table,
        targetUuid: uuid,
        opType: 'UPDATE',
        beforeData: existingData,
        afterData: afterData,
        teamUuid: teamUuid,
        operatorName: '本人(离线)',
      );
    } catch (e) {
      debugPrint("⚠️ 记录本地审计失败: $e");
    }
  }

  /// 🚀 Uni-Sync 4.0: 辅助方法 - 记录本地审计快照
  static Future<void> _recordLocalAudit(String table, String uuid,
      Map<String, dynamic> afterData, String? teamUuid) async {
    try {
      final db = await DatabaseHelper.instance.database;
      // 1. 获取旧数据快照
      final List<Map<String, dynamic>> existing =
          await db.query(table, where: 'uuid = ?', whereArgs: [uuid]);
      if (existing.isEmpty) {
        // 新增操作，直接记录
        await DatabaseHelper.instance.insertLocalAuditLog(
          userId: ApiService.currentUserId,
          targetTable: table,
          targetUuid: uuid,
          opType: 'INSERT',
          beforeData: null,
          afterData: afterData,
          teamUuid: teamUuid,
          operatorName: '本人(离线)',
        );
        return;
      }

      Map<String, dynamic> beforeData =
          Map<String, dynamic>.from(existing.first);

      // 🚀 核心优化：实质性变更检测
      // 排除掉 version, updated_at 等会自动变动的字段，只对比业务字段
      bool hasSubstantialChange = false;
      final businessFields = [
        'content',
        'title',
        'remark',
        'is_completed',
        'is_deleted',
        'due_date',
        'target_time',
        'group_id',
        'category_id',
        'recurrence',
        'recurrence_series_id',
        'is_all_day',
        'reminder_minutes',
        'recurrence_end_date',
        'custom_interval_days'
      ];

      for (var field in businessFields) {
        if (afterData.containsKey(field) || beforeData.containsKey(field)) {
          var valA = afterData[field];
          var valB = beforeData[field];

          // 🚀 核心修复：全面的值归一化处理
          // 处理 null 和 0/""/"false" 的等价性
          // 特别处理 reminder_minutes: -1 和 null 的等价性
          bool isAEmpty = valA == null ||
              valA == 0 ||
              valA == "" ||
              valA == false ||
              (field == 'reminder_minutes' && valA == -1);
          bool isBEmpty = valB == null ||
              valB == 0 ||
              valB == "" ||
              valB == false ||
              (field == 'reminder_minutes' && valB == -1);

          if (isAEmpty && isBEmpty) continue; // 两个都是"空"，认为相同
          if (isAEmpty || isBEmpty) {
            // 一个是空，一个不是空，判断为有变更（除非都是0的情况）
            if ((valA == 0 || valB == 0) && (valA ?? valB) == 0) continue;
            hasSubstantialChange = true;
            break;
          }

          // 两个都不是"空"，直接比较
          if (valA != valB) {
            hasSubstantialChange = true;
            break;
          }
        }
      }

      if (!hasSubstantialChange) return; // 没有实质性变化，不记录日志

      Map<String, dynamic> enrichedAfter = Map<String, dynamic>.from(afterData);

      // 🚀 核心优化：本地名称解析 - 让离线历史也显示人类可读的名称
      Future<String?> lookupName(String targetTable, String? targetUuid) async {
        if (targetUuid == null || targetUuid.isEmpty) return null;
        try {
          final List<Map<String, dynamic>> res = await db.query(targetTable,
              columns: ['name'], where: 'uuid = ?', whereArgs: [targetUuid]);
          return res.isNotEmpty ? res.first['name'] as String? : null;
        } catch (_) {
          return null;
        }
      }

      if (beforeData['group_id'] != null) {
        beforeData['group_name'] =
            await lookupName('todo_groups', beforeData['group_id']);
      }
      if (beforeData['team_uuid'] != null) {
        beforeData['team_name'] =
            await lookupName('teams', beforeData['team_uuid']);
      }
      if (enrichedAfter['group_id'] != null) {
        enrichedAfter['group_name'] =
            await lookupName('todo_groups', enrichedAfter['group_id']);
      }
      if (enrichedAfter['team_uuid'] != null) {
        enrichedAfter['team_name'] =
            await lookupName('teams', enrichedAfter['team_uuid']);
      }

      // 2. 存入本地审计表
      await DatabaseHelper.instance.insertLocalAuditLog(
        userId: ApiService.currentUserId,
        targetTable: table,
        targetUuid: uuid,
        opType: 'UPDATE',
        beforeData: beforeData,
        afterData: enrichedAfter,
        teamUuid: teamUuid,
        operatorName: '本人(离线)',
      );
    } catch (e) {
      debugPrint("⚠️ 记录本地审计失败: $e");
    }
  }

  static Future<void> _syncTodosToBand(List<TodoItem> items) async {
    if (!BandSyncService.isInitialized || !BandSyncService.isConnected) return;
    try {
      final activeTodos = items.where((t) => !t.isDeleted).map((t) {
        final data = t.toJson();
        data.remove('image_path');
        data.remove('imagePath');
        data.remove('original_text');
        data.remove('originalText');
        data.remove('conflict_data');
        return data;
      }).toList();
      await BandSyncService.syncTodos(activeTodos);
    } catch (_) {}
  }

  /// 🚀 Uni-Sync 4.0 增强：原子化更新单条待办，避免全量读写性能开销
  static Future<void> updateSingleTodo(String username, TodoItem item,
      {bool sync = true}) async {
    if (item.recurrence != RecurrenceType.none &&
        (item.recurrenceSeriesId == null || item.recurrenceSeriesId!.isEmpty)) {
      item.recurrenceSeriesId = item.id;
    }
    // 1. 记录本地审计日志 (必须在更新前，因为需要获取旧快照)
    await _recordLocalAudit('todos', item.id, item.toJson(), item.teamUuid);

    final db = await DatabaseHelper.instance.database;

    // 2. 同步更新 SQLite
    await db.insert(
        'todos',
        {
          'uuid': item.id,
          'content': item.title,
          'remark': item.remark,
          'team_uuid': item.teamUuid,
          'team_name': item.teamName,
          'creator_id': item.creatorId,
          'creator_name': item.creatorName,
          'is_completed': item.isDone ? 1 : 0,
          'is_deleted': item.isDeleted ? 1 : 0,
          'version': item.version,
          'updated_at': item.updatedAt,
          'created_at': item.createdAt,
          // 🚀 核心防御：0 兜底
          'due_date': item.dueDate?.millisecondsSinceEpoch ?? 0,
          'group_id': item.groupId,
          'created_date': item.createdDate,
          'collab_type': item.collabType,
          'recurrence': _normalizedRecurrenceIndex(item),
          'recurrence_series_id': item.recurrenceSeriesId,
          'custom_interval_days': _normalizedCustomIntervalDays(item),
          // 🚀 核心防御：0 兜底
          'recurrence_end_date':
              item.recurrenceEndDate?.millisecondsSinceEpoch ?? 0,
          'reminder_minutes': item.reminderMinutes ?? -1,
          'image_path': item.imagePath,
          'original_text': item.originalText,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    // 2.1 针对各自独立团队待办（collabType == 1），同步在本地 todo_completions 表中为当前用户写入/更新完成状态
    if (item.collabType == 1) {
      try {
        final localPrefs = await prefs;
        final int userId = localPrefs.getInt('current_user_id') ?? 0;
        if (userId > 0) {
          await db.insert(
              'todo_completions',
              {
                'todo_uuid': item.id,
                'user_id': userId,
                'is_completed': item.isDone ? 1 : 0,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } catch (e) {
        debugPrint("⚠️ StorageService: 写入本地 todo_completions 状态失败: $e");
      }
    }

    // 3. 补齐 Oplog，确保离线更新能被同步
    await db.insert('op_logs', {
      'op_type': 'UPSERT',
      'target_table': 'todos',
      'target_uuid': item.id,
      'data_json': jsonEncode(_stripClientOnlyConflictForSync(item.toJson())),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });

    // 不再维护超大的 SharedPreferences Todo 镜像，避免 Android 插件层 OOM
    await _clearTodoPrefsMirror(username);

    if (sync) requestSync(username);
    triggerRefresh(); // 🚀 触发 UI 刷新
  }

  /// 🚀 Uni-Sync 4.0: 物理删除单条待办 (用于彻底删除)
  static Future<void> permanentlyDeleteTodo(
      String username, String uuid) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('todos', where: 'uuid = ?', whereArgs: [uuid]);

    await _clearTodoPrefsMirror(username);

    // 记录删除操作到 Oplog (物理删除也需要同步给其它端)
    await db.insert('op_logs', {
      'op_type': 'DELETE',
      'target_table': 'todos',
      'target_uuid': uuid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });

    triggerRefresh();
  }

  /// 🚀 Uni-Sync 4.0: 清空待办回收站 (物理删除所有标记为已删除的项)
  static Future<void> clearTodoRecycleBin(String username) async {
    final db = await DatabaseHelper.instance.database;

    // 1. 获取所有待删除的 UUID，用于记录 Oplog
    final List<Map<String, dynamic>> deletedItems =
        await db.query('todos', columns: ['uuid'], where: 'is_deleted = 1');

    final batch = db.batch();
    for (var item in deletedItems) {
      final uuid = item['uuid']?.toString();
      if (uuid == null) continue;
      batch.delete('todos', where: 'uuid = ?', whereArgs: [uuid]);
      batch.insert('op_logs', {
        'op_type': 'DELETE',
        'target_table': 'todos',
        'target_uuid': uuid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    await batch.commit(noResult: true);

    await _clearTodoPrefsMirror(username);

    triggerRefresh();
  }

  static bool _isHistoricalTodo(TodoItem todo, DateTime today) {
    if (!todo.isDone || todo.isDeleted) return false;

    if (todo.dueDate != null) {
      final due = todo.dueDate!;
      final dueDay = DateTime(due.year, due.month, due.day);
      return dueDay.isBefore(today);
    }

    final created = DateTime.fromMillisecondsSinceEpoch(
      todo.createdDate ?? todo.createdAt,
      isUtc: true,
    ).toLocal();
    final createdDay = DateTime(created.year, created.month, created.day);
    return createdDay.isBefore(today);
  }

  static Future<int> clearHistoricalTodos(String username) async {
    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final allTodos = await getTodos(username, includeDeleted: true);
    final historicalIds = allTodos
        .where((todo) => _isHistoricalTodo(todo, today))
        .map((todo) => todo.id)
        .toList();

    if (historicalIds.isEmpty) return 0;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final uuid in historicalIds) {
      batch.delete('todo_completions',
          where: 'todo_uuid = ?', whereArgs: [uuid]);
      batch.delete('todos', where: 'uuid = ?', whereArgs: [uuid]);
      batch.insert('op_logs', {
        'op_type': 'DELETE',
        'target_table': 'todos',
        'target_uuid': uuid,
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    await batch.commit(noResult: true);

    await _clearTodoPrefsMirror(username);
    triggerRefresh();
    requestSync(username);
    return historicalIds.length;
  }

  /// 🚀 Uni-Sync 4.0: 物理删除单条倒计时 (彻底删除)
  static Future<void> permanentlyDeleteCountdown(
      String username, String uuid) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('countdowns', where: 'uuid = ?', whereArgs: [uuid]);

    // 同步清理 Prefs 缓存
    final prefs = await SharedPreferences.getInstance();
    List<String> list = prefs.getStringList("${keyCountdowns}_$username") ?? [];
    list.removeWhere((jsonStr) {
      try {
        final map = jsonDecode(jsonStr);
        return map['id'] == uuid || map['uuid'] == uuid;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList("${keyCountdowns}_$username", list);

    // 记录删除操作到 Oplog
    await db.insert('op_logs', {
      'op_type': 'DELETE',
      'target_table': 'countdowns',
      'target_uuid': uuid,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'sync_error': '',
    });

    triggerRefresh();
  }

  static Future<List<TodoItem>> getTodos(String username,
      {bool includeDeleted = false, int? limit}) async {
    final requestKey = _todoRequestKey(
      username,
      includeDeleted: includeDeleted,
      limit: limit,
    );
    final inflight = _inflightTodoRequests[requestKey];
    if (inflight != null) {
      debugPrint("🔁 getTodos 复用进行中请求: $requestKey");
      final shared = await inflight;
      return _cloneTodoItems(shared);
    }

    final future = _getTodosInternal(
      username,
      includeDeleted: includeDeleted,
      limit: limit,
    );
    _inflightTodoRequests[requestKey] = future;

    try {
      final result = await future;
      return _cloneTodoItems(result);
    } finally {
      if (identical(_inflightTodoRequests[requestKey], future)) {
        _inflightTodoRequests.remove(requestKey);
      }
    }
  }

  static Future<List<TodoItem>> _getTodosInternal(String username,
      {bool includeDeleted = false, int? limit}) async {
    final prefs = await StorageService.prefs;
    final startedAt = DateTime.now();
    // 🚀 Uni-Sync 安全方案：双轨读取 + 逃生通道
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await _clearGhostConflictFlags(db);

      final migrationKey = "migration_marker_${username}_v4";
      bool alreadyMigrated = prefs.getBool(migrationKey) ?? false;

      if (alreadyMigrated) {
        await _clearTodoPrefsMirror(username);
      }

      // 🚀 核心补丁：清理先前版本迁移后遗留的超大数据 (解决 170MB+ 内存占用与启动卡顿)
      final String cleanupKey = "cleanup_done_${username}_v4_repair";
      if (alreadyMigrated && !(prefs.getBool(cleanupKey) ?? false)) {
        await prefs.remove("${keyTodos}_$username");
        await prefs.remove(keyTodos);
        await prefs.setBool(cleanupKey, true);
        debugPrint("🗑️ Todos 残留数据修复清理完成。");
      }

      if (!alreadyMigrated) {
        List<String> legacyJsonList =
            prefs.getStringList("${keyTodos}_$username") ?? [];
        if (legacyJsonList.isEmpty && username.isNotEmpty) {
          legacyJsonList = prefs.getStringList(keyTodos) ?? [];
        }

        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 发现未迁移老数据，正在执行增量迁移...");
          List<TodoItem> legacyItems = [];
          for (var e in legacyJsonList) {
            try {
              legacyItems.add(TodoItem.fromJson(jsonDecode(e)));
            } catch (_) {}
          }
          // 本地存储迁移不是用户修改，不生成 oplog，避免用迁移时间和云端制造冲突。
          await saveTodos(username, legacyItems,
              sync: false, isSyncSource: true);
          // 🚀 迁移成功后，必须物理清除 SharedPreferences 中的巨大 JSON 块
          // 否则 Android 的原生 SharedPreferences 会一直将此 170MB+ 的数据留在内存中导致 OOM
          await prefs.remove("${keyTodos}_$username");
          await prefs.remove(keyTodos);
          debugPrint("✅ 老数据增量迁移完成并已物理清理。");
        }
        await prefs.setBool(migrationKey, true);
      }

      List<Map<String, dynamic>> maps = await dbHelper.getTodoMaps(
        includeDeleted: includeDeleted,
        limit: limit,
        includeConflictData: true,
      );
      if (limit != null && maps.isNotEmpty) {
        final activeSeriesIds = maps
            .where((map) => (_parseNullableInt(map['recurrence']) ?? 0) != 0)
            .map((map) => map['recurrence_series_id']?.toString().trim())
            .whereType<String>()
            .where((seriesId) => seriesId.isNotEmpty)
            .toSet();
        if (activeSeriesIds.isNotEmpty) {
          final seriesMaps = await dbHelper.getTodoMaps(
            includeDeleted: includeDeleted,
            recurrenceSeriesIds: activeSeriesIds,
            includeConflictData: true,
          );
          final mapsById = <String, Map<String, dynamic>>{
            for (final map in maps) map['uuid'].toString(): map,
          };
          for (final map in seriesMaps) {
            mapsById[map['uuid'].toString()] = map;
          }
          maps = mapsById.values.toList();
        }
      }
      if (maps.isNotEmpty) {
        List<TodoItem> todos;
        // 🚀 性能优化：当待办数量较多时，使用 Isolate 解析，减少主线程解析耗时导致的 UI 卡顿
        if (maps.length > 50) {
          todos = await compute(_parseTodoItemsIsolate, maps);
        } else {
          todos = maps
              .map((m) => TodoItem(
                    id: m['uuid'],
                    title: m['content'] ?? '',
                    remark: m['remark'],
                    isDone: m['is_completed'] == 1,
                    isDeleted: m['is_deleted'] == 1,
                    version: m['version'] ?? 1,
                    updatedAt: m['updated_at'] ??
                        DateTime.now().millisecondsSinceEpoch,
                    createdAt: m['created_at'] ??
                        DateTime.now().millisecondsSinceEpoch,
                    createdDate: m['created_date'] != null
                        ? int.tryParse(m['created_date'].toString())
                        : null,
                    dueDate: (m['due_date'] != null &&
                            m['due_date'].toString() != '0' &&
                            m['due_date'].toString() != 'null' &&
                            m['due_date'].toString().isNotEmpty)
                        ? DateTime.fromMillisecondsSinceEpoch(
                            int.tryParse(m['due_date'].toString()) ?? 0)
                        : null,
                    teamUuid: m['team_uuid'],
                    teamName: m['team_name'],
                    creatorId: m['creator_id'],
                    creatorName: m['creator_name'],
                    groupId: m['group_id'],
                    collabType: m['collab_type'] ?? 0,
                    recurrence: RecurrenceType.values[
                        (_parseNullableInt(m['recurrence']) ?? 0)
                            .clamp(0, RecurrenceType.values.length - 1)],
                    recurrenceSeriesId: m['recurrence_series_id']?.toString(),
                    customIntervalDays:
                        _parseNullableInt(m['custom_interval_days']),
                    recurrenceEndDate: (m['recurrence_end_date'] != null &&
                            m['recurrence_end_date'].toString() != '0')
                        ? DateTime.fromMillisecondsSinceEpoch(
                            int.tryParse(m['recurrence_end_date'].toString()) ??
                                0)
                        : null,
                    reminderMinutes: (m['reminder_minutes'] != null &&
                            m['reminder_minutes'].toString() != '-1')
                        ? int.tryParse(m['reminder_minutes'].toString())
                        : null,
                    imagePath: m['image_path']?.toString(),
                    originalText: m['original_text']?.toString(),
                    isAllDay: m['is_all_day'] == 1 || m['is_all_day'] == true,
                    hasConflict:
                        m['has_conflict'] == 1 || m['has_conflict'] == true,
                    serverVersionData: m['conflict_data'] != null
                        ? (m['conflict_data'] is String
                            ? Map<String, dynamic>.from(
                                jsonDecode(m['conflict_data']))
                            : Map<String, dynamic>.from(m['conflict_data']))
                        : null,
                  ))
              .toList();
        }
        final handledTodos = await _handleRecurrenceLogic(username, todos);
        //debugPrint(
        //    "📦 getTodos(SQL) 完成: count=${handledTodos.length}, includeDeleted=$includeDeleted, limit=$limit, cost=${DateTime.now().difference(startedAt).inMilliseconds}ms");
        if (!includeDeleted) {
          return handledTodos.where((todo) => !todo.isDeleted).toList();
        }
        return handledTodos;
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("⚠️ SQL 引擎异常，启动逃生通道: $e");
    }

    // 🚀 逃生通道：兜底读取 Prefs
    List<String> list = prefs.getStringList("${keyTodos}_$username") ?? [];
    List<TodoItem> legacyTodos;

    if (list.length > 50) {
      legacyTodos = await compute(_parseTodoJsonItemsIsolate, list);
    } else {
      legacyTodos = [];
      for (var e in list) {
        try {
          legacyTodos.add(TodoItem.fromJson(jsonDecode(e)));
        } catch (_) {}
      }
    }
    final handledLegacyTodos =
        await _handleRecurrenceLogic(username, legacyTodos);
    Iterable<TodoItem> filtered = handledLegacyTodos;
    if (!includeDeleted) {
      filtered = filtered.where((todo) => !todo.isDeleted);
    }
    if (limit != null && limit >= 0) {
      filtered = filtered.take(limit);
    }
    final result = filtered.toList();
    debugPrint(
        "📦 getTodos(Prefs Fallback) 完成: count=${result.length}, includeDeleted=$includeDeleted, limit=$limit, cost=${DateTime.now().difference(startedAt).inMilliseconds}ms");
    return result;
  }

  /// 🚀 Isolate 专用：静态待办解析方法
  static List<TodoItem> _parseTodoItemsIsolate(
      List<Map<String, dynamic>> maps) {
    return maps
        .map((m) => TodoItem(
              id: m['uuid'],
              title: m['content'] ?? '',
              remark: m['remark'],
              isDone: m['is_completed'] == 1,
              isDeleted: m['is_deleted'] == 1,
              version: m['version'] ?? 1,
              updatedAt:
                  m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
              createdAt:
                  m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
              createdDate: m['created_date'] != null
                  ? int.tryParse(m['created_date'].toString())
                  : null,
              dueDate: (m['due_date'] != null &&
                      m['due_date'].toString() != '0' &&
                      m['due_date'].toString() != 'null' &&
                      m['due_date'].toString().isNotEmpty)
                  ? DateTime.fromMillisecondsSinceEpoch(
                      int.tryParse(m['due_date'].toString()) ?? 0)
                  : null,
              teamUuid: m['team_uuid'],
              teamName: m['team_name'],
              creatorId: m['creator_id'],
              creatorName: m['creator_name'],
              groupId: m['group_id'],
              collabType: m['collab_type'] ?? 0,
              recurrence: RecurrenceType.values[
                  (_parseNullableInt(m['recurrence']) ?? 0)
                      .clamp(0, RecurrenceType.values.length - 1)],
              recurrenceSeriesId: m['recurrence_series_id']?.toString(),
              customIntervalDays: _parseNullableInt(m['custom_interval_days']),
              recurrenceEndDate: (m['recurrence_end_date'] != null &&
                      m['recurrence_end_date'].toString() != '0')
                  ? DateTime.fromMillisecondsSinceEpoch(
                      int.tryParse(m['recurrence_end_date'].toString()) ?? 0)
                  : null,
              reminderMinutes: (m['reminder_minutes'] != null &&
                      m['reminder_minutes'].toString() != '-1')
                  ? int.tryParse(m['reminder_minutes'].toString())
                  : null,
              imagePath: m['image_path']?.toString(),
              originalText: m['original_text']?.toString(),
              isAllDay: m['is_all_day'] == 1 || m['is_all_day'] == true,
              hasConflict: m['has_conflict'] == 1 || m['has_conflict'] == true,
              serverVersionData: m['conflict_data'] != null
                  ? (m['conflict_data'] is String
                      ? Map<String, dynamic>.from(
                          jsonDecode(m['conflict_data']))
                      : Map<String, dynamic>.from(m['conflict_data']))
                  : null,
            ))
        .toList();
  }

  static List<TodoItem> _parseTodoJsonItemsIsolate(List<String> jsonList) {
    return jsonList
        .map((e) {
          try {
            return TodoItem.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<TodoItem>()
        .toList();
  }

  /// 🚀 Uni-Sync 4.0: 当被移出团队时，彻底清理本地缓存的相关数据
  static Future<void> clearTeamItems(String teamUuid) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 软删除 (标记 isDeleted，通过同步传播到服务器)
    await db.rawUpdate(
        "UPDATE todos SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE todo_groups SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE countdowns SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE time_logs SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE courses SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);
    await db.rawUpdate(
        "UPDATE fixed_schedules SET is_deleted = 1, version = version + 1, updated_at = ? WHERE team_uuid = ? AND is_deleted = 0",
        [now, teamUuid]);

    await db.delete(
      'todo_completions',
      where: 'todo_uuid IN (SELECT uuid FROM todos WHERE team_uuid = ?)',
      whereArgs: [teamUuid],
    );

    // 🚀 关键：为软删除的项创建 op_log，使同步引擎能将删除传播到服务端
    final deletedTodos = await db.query('todos',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
    for (var row in deletedTodos) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'todos',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedGroups = await db.query('todo_groups',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
    for (var row in deletedGroups) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'todo_groups',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedCountdowns = await db.query('countdowns',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
    for (var row in deletedCountdowns) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'countdowns',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }
    final deletedTimeLogs = await db.query('time_logs',
        columns: ['uuid', 'version', 'updated_at'],
        where: 'team_uuid = ? AND is_deleted = 1 AND updated_at = ?',
        whereArgs: [teamUuid, now]);
    for (var row in deletedTimeLogs) {
      await db.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': 'time_logs',
        'target_uuid': row['uuid'],
        'data_json': jsonEncode({
          'uuid': row['uuid'],
          'is_deleted': true,
          'version': row['version'],
          'updated_at': row['updated_at'],
        }),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }

    // 2. 🚀 关键：同步清理 SharedPreferences 缓存，防止主页残余
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(keyCurrentUser) ?? "";
    if (username.isNotEmpty) {
      Future<void> cleanCache(String key) async {
        List<String> list = prefs.getStringList("${key}_$username") ?? [];
        if (list.isEmpty) return;
        int originalLen = list.length;
        list.removeWhere((jsonStr) {
          try {
            final map = jsonDecode(jsonStr);
            return map['team_uuid'] == teamUuid || map['teamUuid'] == teamUuid;
          } catch (_) {
            return false;
          }
        });
        if (list.length != originalLen) {
          await prefs.setStringList("${key}_$username", list);
        }
      }

      await cleanCache(keyTodos);
      await cleanCache(keyTodoGroups);
      await cleanCache(keyCountdowns);
      await cleanCache(keyTimeLogs);
      // 🚀 补充清理：课程表与番茄记录缓存 (Key 映射已在 Service 中定义)
      await cleanCache('course_schedule_json');
      await cleanCache('pomodoro_records');
    }

    debugPrint("🧹 已清理团队 $teamUuid 的本地数据 (SQL + Cache)");
    triggerRefresh(); // 🚀 触发 UI 刷新
  }

  static Future<List<TodoItem>> _handleRecurrenceLogic(
      String username, List<TodoItem> todos) async {
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';

    if (_lastRecurrenceCheckDate != todayKey) {
      _lastRecurrenceCheckDate = todayKey;
      _recurrenceCheckCache.clear();
    }

    final cacheKey = 'recurrence_instances_v4_$username';
    if (_recurrenceCheckCache.containsKey(cacheKey) || _isCheckingRecurrence) {
      return todos;
    }

    _isCheckingRecurrence = true;

    try {
      bool needSave = false;
      if (_deduplicatePersistedRecurrenceOccurrences(todos)) {
        needSave = true;
      }
      final List<TodoItem> generatedOccurrences = [];
      final Set<String> generatedRecurrenceConflictKeys = {};
      final processedSeriesIds = <String>{};
      for (final todo in List<TodoItem>.from(todos)) {
        if (todo.isDeleted || todo.recurrence == RecurrenceType.none) continue;

        final hasSeriesId = todo.recurrenceSeriesId != null &&
            todo.recurrenceSeriesId!.isNotEmpty;
        final seriesId = hasSeriesId ? todo.recurrenceSeriesId! : todo.id;
        todo.recurrenceSeriesId = seriesId;
        if (!processedSeriesIds.add(seriesId)) continue;

        final DateTime baseLocal = _getRecurrenceBaseDate(todo);
        final DateTime baseDay =
            DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
        final DateTime todayDay = DateTime(today.year, today.month, today.day);
        final rollOffsets = _recurrenceRollOffsets(todo, baseDay, todayDay);
        final recurrence = todo.recurrence;
        final recurrenceEndDay = todo.recurrenceEndDate == null
            ? null
            : DateTime(
                todo.recurrenceEndDate!.year,
                todo.recurrenceEndDate!.month,
                todo.recurrenceEndDate!.day,
              );
        final keepSeriesActive =
            recurrenceEndDay == null || !todayDay.isAfter(recurrenceEndDay);
        final seriesChain = <TodoItem>[todo];
        var activeOccurrence = todo;
        var todoChanged = !hasSeriesId;

        for (var i = 0; i < rollOffsets.length; i++) {
          final result = _getOrCreateRecurrenceOccurrence(
            source: todo,
            rollByDays: rollOffsets[i],
            seriesId: seriesId,
            todos: todos,
            generatedOccurrences: generatedOccurrences,
          );
          final occurrence = result.occurrence;
          final targetRecurrence =
              i == rollOffsets.length - 1 && keepSeriesActive
                  ? recurrence
                  : RecurrenceType.none;
          if (occurrence.recurrence != targetRecurrence) {
            occurrence.recurrence = targetRecurrence;
            if (!result.isNew) occurrence.markAsChanged();
            needSave = true;
          }
          if (result.didChange) needSave = true;
          seriesChain.add(occurrence);
          activeOccurrence = occurrence;
        }

        final repairedPastOccurrences = _repairMissingPastRecurrenceOccurrences(
          ruleSource: todo,
          copySource: activeOccurrence,
          seriesId: seriesId,
          throughStartMs:
              activeOccurrence.createdDate ?? activeOccurrence.createdAt,
          todos: todos,
          generatedOccurrences: generatedOccurrences,
        );
        if (repairedPastOccurrences.isNotEmpty) {
          seriesChain.addAll(repairedPastOccurrences);
          needSave = true;
        }

        if (rollOffsets.isNotEmpty) {
          // 原实例保留自己的完成状态，当前日期对应实例接管循环锚点。
          todo.recurrence = RecurrenceType.none;
          todoChanged = true;
        }

        if (todoChanged) {
          todo.markAsChanged();
          needSave = true;
        }

        if (activeOccurrence.recurrence != RecurrenceType.none) {
          final activeBase = _getRecurrenceBaseDate(activeOccurrence);
          final futureOffsets = _futureRecurrenceRollOffsets(
            activeOccurrence,
            activeBase,
          );
          for (final offset in futureOffsets) {
            final result = _getOrCreateRecurrenceOccurrence(
              source: activeOccurrence,
              rollByDays: offset,
              seriesId: seriesId,
              todos: todos,
              generatedOccurrences: generatedOccurrences,
            );
            final occurrence = result.occurrence;
            if (occurrence.recurrence != RecurrenceType.none) {
              occurrence.recurrence = RecurrenceType.none;
              if (!result.isNew) occurrence.markAsChanged();
              needSave = true;
            }
            if (result.didChange) needSave = true;
            seriesChain.add(occurrence);
          }
        }

        final uniqueSeriesChain = <String, TodoItem>{
          for (final occurrence in seriesChain) occurrence.id: occurrence,
        }.values.toList();
        for (var i = 0; i < uniqueSeriesChain.length; i++) {
          for (var j = i + 1; j < uniqueSeriesChain.length; j++) {
            final conflictKey = _overlappingRecurrencePairKey(
              uniqueSeriesChain[i],
              uniqueSeriesChain[j],
            );
            if (conflictKey != null) {
              generatedRecurrenceConflictKeys.add(conflictKey);
            }
          }
        }
      }

      if (needSave) {
        todos.addAll(generatedOccurrences);
        if (generatedRecurrenceConflictKeys.isNotEmpty) {
          final ignoredKeys = await _getIgnoredScheduleConflictKeys(username)
            ..addAll(generatedRecurrenceConflictKeys);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(
            _scopedKey(keyIgnoredScheduleConflicts, username),
            ignoredKeys.toList()..sort(),
          );
        }
        debugPrint("🚀 [Recurrence] 发现重复任务需要滚动，正在保存...");
        await saveTodos(username, todos, sync: true);
      }
      _recurrenceCheckCache[cacheKey] = true;
      _isCheckingRecurrence = false;
      return todos;
    } catch (e) {
      debugPrint("❌ [Recurrence] 逻辑异常: $e");
      _isCheckingRecurrence = false;
      return todos;
    }
  }

  static DateTime _getRecurrenceBaseDate(TodoItem todo) {
    if (todo.createdDate != null) {
      return DateTime.fromMillisecondsSinceEpoch(todo.createdDate!, isUtc: true)
          .toLocal();
    }
    return todo.dueDate ??
        DateTime.fromMillisecondsSinceEpoch(todo.createdAt, isUtc: true)
            .toLocal();
  }

  static List<int> _recurrenceRollOffsets(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) {
    var targetDay = todayDay;
    if (todo.recurrenceEndDate != null) {
      final end = todo.recurrenceEndDate!;
      final endDay = DateTime(end.year, end.month, end.day);
      if (endDay.isBefore(targetDay)) targetDay = endDay;
    }
    if (!targetDay.isAfter(baseDay)) return const [];

    final offsets = <int>[];
    final diffDays = targetDay.difference(baseDay).inDays;
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        for (var day = 1; day <= diffDays; day++) {
          offsets.add(day);
        }
      case RecurrenceType.customDays:
        final interval = todo.customIntervalDays ?? 0;
        if (interval > 0) {
          for (var day = interval; day <= diffDays; day += interval) {
            offsets.add(day);
          }
        }
      case RecurrenceType.weekdays:
        for (var day = 1; day <= diffDays; day++) {
          final candidate = DateTime(
            baseDay.year,
            baseDay.month,
            baseDay.day + day,
          );
          if (candidate.weekday != DateTime.saturday &&
              candidate.weekday != DateTime.sunday) {
            offsets.add(day);
          }
        }
      case RecurrenceType.weekly:
        for (var day = 7; day <= diffDays; day += 7) {
          offsets.add(day);
        }
      case RecurrenceType.monthly:
        for (var month = 1;; month++) {
          final monthStart = DateTime(baseDay.year, baseDay.month + month);
          final lastDay =
              DateTime(monthStart.year, monthStart.month + 1, 0).day;
          final candidate = DateTime(
            monthStart.year,
            monthStart.month,
            baseDay.day.clamp(1, lastDay),
          );
          if (candidate.isAfter(targetDay)) break;
          offsets.add(candidate.difference(baseDay).inDays);
        }
      case RecurrenceType.yearly:
        for (var year = 1;; year++) {
          final targetYear = baseDay.year + year;
          final lastDay = DateTime(targetYear, baseDay.month + 1, 0).day;
          final candidate = DateTime(
            targetYear,
            baseDay.month,
            baseDay.day.clamp(1, lastDay),
          );
          if (candidate.isAfter(targetDay)) break;
          offsets.add(candidate.difference(baseDay).inDays);
        }
      case RecurrenceType.none:
        break;
    }

    // 防止长期未启动后一次性生成过量记录，同时优先保留最近周期。
    const maxBackfilledOccurrences = 90;
    if (offsets.length <= maxBackfilledOccurrences) return offsets;
    return offsets.sublist(offsets.length - maxBackfilledOccurrences);
  }

  @visibleForTesting
  static List<int> recurrenceRollOffsetsForTest(
    TodoItem todo,
    DateTime baseDay,
    DateTime todayDay,
  ) =>
      _recurrenceRollOffsets(todo, baseDay, todayDay);

  @visibleForTesting
  static List<TodoItem> futureRecurrenceOccurrencesForTest(
    TodoItem source,
    List<TodoItem> existing,
  ) {
    final generated = <TodoItem>[];
    final seriesId = source.recurrenceSeriesId ?? source.id;
    source.recurrenceSeriesId = seriesId;
    final base = _getRecurrenceBaseDate(source);
    for (final offset in _futureRecurrenceRollOffsets(source, base)) {
      final result = _getOrCreateRecurrenceOccurrence(
        source: source,
        rollByDays: offset,
        seriesId: seriesId,
        todos: existing,
        generatedOccurrences: generated,
      );
      result.occurrence.recurrence = RecurrenceType.none;
    }
    return generated;
  }

  @visibleForTesting
  static List<TodoItem> repairMissingPastRecurrenceOccurrencesForTest(
    TodoItem active,
    List<TodoItem> existing,
  ) {
    final generated = <TodoItem>[];
    final seriesId = active.recurrenceSeriesId ?? active.id;
    active.recurrenceSeriesId = seriesId;
    return _repairMissingPastRecurrenceOccurrences(
      ruleSource: active,
      copySource: active,
      seriesId: seriesId,
      throughStartMs: active.createdDate ?? active.createdAt,
      todos: existing,
      generatedOccurrences: generated,
    );
  }

  @visibleForTesting
  static String recurrenceOccurrenceIdForTest(
    String seriesId,
    int startMs,
  ) =>
      _recurrenceOccurrenceId(seriesId, startMs);

  @visibleForTesting
  static bool deduplicatePersistedRecurrenceOccurrencesForTest(
    List<TodoItem> todos,
  ) =>
      _deduplicatePersistedRecurrenceOccurrences(todos);

  /// 手动将多个循环系列归并到用户指定的主系列。
  ///
  /// 所有实例保留原 UUID，因此规划、番茄钟和时间日志的绑定
  /// 不会丢失。同日重复实例会使用现有规则去重。
  static Future<int> mergeRecurrenceSeries(
    String username, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) async {
    final todos = await getTodos(username, includeDeleted: true);
    final changedIds = _mergeRecurrenceSeries(
      todos,
      targetSeriesId: targetSeriesId,
      seriesIds: seriesIds,
    );
    if (changedIds.isEmpty) return 0;

    final changedItems =
        todos.where((todo) => changedIds.contains(todo.id)).toList();
    await saveTodos(
      username,
      changedItems,
      sync: true,
      recomputeScheduleConflicts: false,
    );
    await _refreshTodoScheduleConflicts(username);
    triggerRefresh();
    return changedItems.length;
  }

  @visibleForTesting
  static Set<String> mergeRecurrenceSeriesForTest(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) =>
      _mergeRecurrenceSeries(
        todos,
        targetSeriesId: targetSeriesId,
        seriesIds: seriesIds,
      );

  static Set<String> _mergeRecurrenceSeries(
    List<TodoItem> todos, {
    required String targetSeriesId,
    required Set<String> seriesIds,
  }) {
    final selectedSeriesIds = <String>{...seriesIds, targetSeriesId}
      ..removeWhere((seriesId) => seriesId.trim().isEmpty);
    final participating = todos
        .where((todo) =>
            todo.recurrenceSeriesId != null &&
            selectedSeriesIds.contains(todo.recurrenceSeriesId))
        .toList();
    final activeSeriesIds = participating
        .where((todo) => !todo.isDeleted)
        .map((todo) => todo.recurrenceSeriesId)
        .whereType<String>()
        .toSet();
    if (activeSeriesIds.length < 2 ||
        !activeSeriesIds.contains(targetSeriesId)) {
      return <String>{};
    }

    TodoItem? canonicalActive;
    final activeRules = participating
        .where(
            (todo) => !todo.isDeleted && todo.recurrence != RecurrenceType.none)
        .toList()
      ..sort((a, b) {
        final startCompare = (b.createdDate ?? b.createdAt)
            .compareTo(a.createdDate ?? a.createdAt);
        if (startCompare != 0) return startCompare;
        return b.version.compareTo(a.version);
      });
    for (final todo in activeRules) {
      if (todo.recurrenceSeriesId == targetSeriesId) {
        canonicalActive = todo;
        break;
      }
    }
    canonicalActive ??= activeRules.isEmpty ? null : activeRules.first;

    final versionsBefore = {
      for (final todo in participating) todo.id: todo.version,
    };
    final fieldChangedIds = <String>{};

    // 系列被拆分并多次去重后，完成状态可能只保留在源系列中已经删除的
    // 重复实例上。合并时按发生日期取完成状态并集，再写回该日仍可见的
    // 实例；目标系列中早已删除的旧状态不参与，避免覆盖用户后续的取消完成。
    final completedDays = participating
        .where((todo) =>
            todo.isDone &&
            (!todo.isDeleted || todo.recurrenceSeriesId != targetSeriesId))
        .map((todo) => _recurrenceLocalDayKey(
              todo.createdDate ?? todo.createdAt,
            ))
        .toSet();
    for (final todo in participating) {
      if (todo.isDeleted || todo.isDone) continue;
      final dayKey = _recurrenceLocalDayKey(
        todo.createdDate ?? todo.createdAt,
      );
      if (!completedDays.contains(dayKey)) continue;
      todo.isDone = true;
      fieldChangedIds.add(todo.id);
    }

    for (final todo in participating) {
      if (todo.recurrenceSeriesId != targetSeriesId) {
        todo.recurrenceSeriesId = targetSeriesId;
        fieldChangedIds.add(todo.id);
      }
      if (todo.recurrence != RecurrenceType.none &&
          todo.id != canonicalActive?.id) {
        todo.recurrence = RecurrenceType.none;
        fieldChangedIds.add(todo.id);
      }
    }

    _deduplicatePersistedRecurrenceOccurrences(participating);
    final changedIds = <String>{};
    for (final todo in participating) {
      if (todo.version != versionsBefore[todo.id]) {
        changedIds.add(todo.id);
      }
    }
    for (final todo in participating) {
      if (!fieldChangedIds.contains(todo.id)) continue;
      if (todo.version == versionsBefore[todo.id]) {
        todo.markAsChanged();
      }
      changedIds.add(todo.id);
    }
    return changedIds;
  }

  static List<int> _futureRecurrenceRollOffsets(
    TodoItem todo,
    DateTime baseLocal,
  ) {
    final baseDay = DateTime(baseLocal.year, baseLocal.month, baseLocal.day);
    final recurrenceEnd = todo.recurrenceEndDate;
    if (recurrenceEnd != null) {
      final endDay =
          DateTime(recurrenceEnd.year, recurrenceEnd.month, recurrenceEnd.day);
      return _recurrenceRollOffsets(todo, baseDay, endDay);
    }

    final offsets = <int>[];
    var cursor = baseLocal;
    for (var i = 0; i < 2; i++) {
      final next = _nextRecurrenceDate(cursor, todo);
      if (next == null || !next.isAfter(cursor)) break;
      offsets.add(
          DateTime(next.year, next.month, next.day).difference(baseDay).inDays);
      cursor = next;
    }
    return offsets;
  }

  static DateTime? _nextRecurrenceDate(DateTime current, TodoItem todo) {
    switch (todo.recurrence) {
      case RecurrenceType.daily:
        return DateTime(current.year, current.month, current.day + 1,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.customDays:
        final days = todo.customIntervalDays ?? 0;
        if (days <= 0) return null;
        return DateTime(current.year, current.month, current.day + days,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.weekly:
        return DateTime(current.year, current.month, current.day + 7,
            current.hour, current.minute, current.second, current.millisecond);
      case RecurrenceType.weekdays:
        var next = DateTime(current.year, current.month, current.day + 1,
            current.hour, current.minute, current.second, current.millisecond);
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = DateTime(next.year, next.month, next.day + 1, next.hour,
              next.minute, next.second, next.millisecond);
        }
        return next;
      case RecurrenceType.monthly:
        final targetMonth = DateTime(current.year, current.month + 1);
        final lastDay =
            DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
        return DateTime(
          targetMonth.year,
          targetMonth.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.yearly:
        final lastDay = DateTime(current.year + 1, current.month + 1, 0).day;
        return DateTime(
          current.year + 1,
          current.month,
          current.day.clamp(1, lastDay),
          current.hour,
          current.minute,
          current.second,
          current.millisecond,
        );
      case RecurrenceType.none:
        return null;
    }
  }

  static ({TodoItem occurrence, bool isNew, bool didChange})
      _getOrCreateRecurrenceOccurrence({
    required TodoItem source,
    required int rollByDays,
    required String seriesId,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
  }) {
    final candidate = _copyForNextRecurrence(source);
    candidate.recurrenceSeriesId = seriesId;
    _rollRecurrenceDateByDays(candidate, rollByDays);
    final candidateStart = candidate.createdDate ?? candidate.createdAt;
    final candidateDayKey = _recurrenceLocalDayKey(candidateStart);
    candidate.id = _recurrenceOccurrenceId(seriesId, candidateStart);

    final matches = <TodoItem>[];
    for (final existing in todos.followedBy(generatedOccurrences)) {
      if (existing.recurrenceSeriesId != seriesId ||
          _recurrenceLocalDayKey(
                existing.createdDate ?? existing.createdAt,
              ) !=
              candidateDayKey) {
        continue;
      }
      matches.add(existing);
    }

    final liveMatches = matches.where((todo) => !todo.isDeleted).toList();
    if (liveMatches.isNotEmpty) {
      liveMatches.sort(_compareRecurrenceOccurrenceIdentity);
      return (
        occurrence: liveMatches.first,
        isNew: false,
        didChange: false,
      );
    }

    final deletedDeterministic =
        matches.where((todo) => todo.id == candidate.id).firstOrNull;
    if (deletedDeterministic != null) {
      _copyRecurrenceOccurrenceData(candidate, deletedDeterministic);
      deletedDeterministic.isDeleted = false;
      deletedDeterministic.markAsChanged();
      _recurrenceDedupeTombstoneIds.remove(deletedDeterministic.id);
      return (
        occurrence: deletedDeterministic,
        isNew: false,
        didChange: true,
      );
    }

    generatedOccurrences.add(candidate);
    return (occurrence: candidate, isNew: true, didChange: true);
  }

  static String _recurrenceLocalDayKey(int startMs) {
    final start =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
    final month = start.month.toString().padLeft(2, '0');
    final day = start.day.toString().padLeft(2, '0');
    return '${start.year}-$month-$day';
  }

  static String _recurrenceOccurrenceId(String seriesId, int startMs) {
    final dayKey = _recurrenceLocalDayKey(startMs);
    return const Uuid().v5(
      _recurrenceOccurrenceNamespace,
      'countdown-todo/recurrence-occurrence/v1/$seriesId/$dayKey',
    );
  }

  static List<TodoItem> _repairMissingPastRecurrenceOccurrences({
    required TodoItem ruleSource,
    required TodoItem copySource,
    required String seriesId,
    required int throughStartMs,
    required List<TodoItem> todos,
    required List<TodoItem> generatedOccurrences,
  }) {
    final knownByDay = <String, DateTime>{};
    for (final occurrence in todos.followedBy(generatedOccurrences)) {
      if (occurrence.isDeleted || occurrence.recurrenceSeriesId != seriesId) {
        continue;
      }
      final startMs = occurrence.createdDate ?? occurrence.createdAt;
      if (startMs > throughStartMs) continue;
      final start =
          DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
      final day = DateTime(start.year, start.month, start.day);
      knownByDay['${day.year}-${day.month}-${day.day}'] = day;
    }

    final knownDays = knownByDay.values.toList()..sort();
    if (knownDays.length < 2) return const [];

    final copyBase = _getRecurrenceBaseDate(copySource);
    final copyBaseDay = DateTime(copyBase.year, copyBase.month, copyBase.day);
    final repaired = <TodoItem>[];
    for (var index = 0; index < knownDays.length - 1; index++) {
      final previousDay = knownDays[index];
      final nextKnownDay = knownDays[index + 1];
      final candidateOffsets = _recurrenceRollOffsets(
        ruleSource,
        previousDay,
        nextKnownDay,
      );
      for (final candidateOffset in candidateOffsets) {
        final candidateDay = DateTime(
          previousDay.year,
          previousDay.month,
          previousDay.day + candidateOffset,
        );
        if (!candidateDay.isBefore(nextKnownDay)) continue;

        final rollByDays = DateTime.utc(
          candidateDay.year,
          candidateDay.month,
          candidateDay.day,
        )
            .difference(DateTime.utc(
              copyBaseDay.year,
              copyBaseDay.month,
              copyBaseDay.day,
            ))
            .inDays;
        final result = _getOrCreateRecurrenceOccurrence(
          source: copySource,
          rollByDays: rollByDays,
          seriesId: seriesId,
          todos: todos,
          generatedOccurrences: generatedOccurrences,
        );
        if (!result.didChange) continue;
        result.occurrence.recurrence = RecurrenceType.none;
        repaired.add(result.occurrence);
      }
    }
    return repaired;
  }

  static bool _deduplicatePersistedRecurrenceOccurrences(List<TodoItem> todos,
      {Set<String>? changedIds}) {
    final occurrencesBySeriesDay = <String, List<TodoItem>>{};
    for (final todo in todos) {
      final seriesId = todo.recurrenceSeriesId;
      if (seriesId == null || seriesId.isEmpty) continue;
      final startMs = todo.createdDate ?? todo.createdAt;
      final key = '$seriesId|${_recurrenceLocalDayKey(startMs)}';
      occurrencesBySeriesDay.putIfAbsent(key, () => []).add(todo);
    }

    var changed = false;
    for (final occurrences in occurrencesBySeriesDay.values) {
      if (occurrences.length <= 1) continue;
      final liveOccurrences =
          occurrences.where((todo) => !todo.isDeleted).toList();
      if (liveOccurrences.isEmpty) continue;

      // Identity must not depend on mutable LWW fields. Every device will
      // eventually select the same oldest physical occurrence, even if it
      // initially saw only a subset of the duplicates.
      occurrences.sort(_compareRecurrenceOccurrenceIdentity);
      final canonical = occurrences.first;
      liveOccurrences.sort((a, b) {
        final versionOrder = b.version.compareTo(a.version);
        if (versionOrder != 0) return versionOrder;
        final updatedAtOrder = b.updatedAt.compareTo(a.updatedAt);
        if (updatedAtOrder != 0) return updatedAtOrder;
        return a.id.compareTo(b.id);
      });
      final dataWinner = liveOccurrences.first;
      final completionWinner = dataWinner;
      final activeOccurrences = liveOccurrences
          .where((todo) => todo.recurrence != RecurrenceType.none)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final mergedRecurrence = activeOccurrences.isEmpty
          ? RecurrenceType.none
          : activeOccurrences.first.recurrence;

      var canonicalChanged = false;
      if (!identical(canonical, dataWinner)) {
        canonicalChanged =
            _copyRecurrenceOccurrenceData(dataWinner, canonical) ||
                canonicalChanged;
      }
      if (canonical.isDeleted) {
        canonical.isDeleted = false;
        canonicalChanged = true;
      }
      if (canonical.isDone != completionWinner.isDone) {
        canonical.isDone = completionWinner.isDone;
        canonicalChanged = true;
      }
      if (canonical.recurrence != mergedRecurrence) {
        canonical.recurrence = mergedRecurrence;
        canonicalChanged = true;
      }
      if (canonicalChanged) {
        canonical.version = canonical.version < dataWinner.version
            ? dataWinner.version
            : canonical.version;
        canonical.updatedAt = canonical.updatedAt < dataWinner.updatedAt
            ? dataWinner.updatedAt
            : canonical.updatedAt;
        canonical.markAsChanged();
        _recurrenceDedupeTombstoneIds.remove(canonical.id);
        changedIds?.add(canonical.id);
        changed = true;
      }

      for (final duplicate in occurrences) {
        if (identical(duplicate, canonical)) continue;
        if (duplicate.isDeleted &&
            duplicate.recurrence == RecurrenceType.none) {
          continue;
        }
        duplicate.isDeleted = true;
        duplicate.recurrence = RecurrenceType.none;
        duplicate.markAsChanged();
        _recurrenceDedupeTombstoneIds.add(duplicate.id);
        changedIds?.add(duplicate.id);
        changed = true;
      }
    }
    return changed;
  }

  static int _compareRecurrenceOccurrenceIdentity(TodoItem a, TodoItem b) {
    final createdAtComparison = a.createdAt.compareTo(b.createdAt);
    if (createdAtComparison != 0) return createdAtComparison;
    return a.id.compareTo(b.id);
  }

  static bool _copyRecurrenceOccurrenceData(
    TodoItem source,
    TodoItem target,
  ) {
    var changed = false;

    void assign<T>(T current, T next, void Function(T) setter) {
      if (current == next) return;
      setter(next);
      changed = true;
    }

    assign(target.title, source.title, (value) => target.title = value);
    assign(target.createdDate, source.createdDate,
        (value) => target.createdDate = value);
    assign(target.dueDate, source.dueDate, (value) => target.dueDate = value);
    assign(target.recurrenceSeriesId, source.recurrenceSeriesId,
        (value) => target.recurrenceSeriesId = value);
    assign(target.customIntervalDays, source.customIntervalDays,
        (value) => target.customIntervalDays = value);
    assign(target.recurrenceEndDate, source.recurrenceEndDate,
        (value) => target.recurrenceEndDate = value);
    assign(target.remark, source.remark, (value) => target.remark = value);
    assign(target.imagePath, source.imagePath,
        (value) => target.imagePath = value);
    assign(target.originalText, source.originalText,
        (value) => target.originalText = value);
    assign(target.groupId, source.groupId, (value) => target.groupId = value);
    assign(target.reminderMinutes, source.reminderMinutes,
        (value) => target.reminderMinutes = value);
    assign(
        target.teamUuid, source.teamUuid, (value) => target.teamUuid = value);
    assign(target.creatorId, source.creatorId,
        (value) => target.creatorId = value);
    assign(target.creatorName, source.creatorName,
        (value) => target.creatorName = value);
    assign(
        target.teamName, source.teamName, (value) => target.teamName = value);
    assign(target.collabType, source.collabType,
        (value) => target.collabType = value);
    assign(
        target.isAllDay, source.isAllDay, (value) => target.isAllDay = value);
    assign(target.categoryId, source.categoryId,
        (value) => target.categoryId = value);
    return changed;
  }

  static String? _overlappingRecurrencePairKey(
      TodoItem previous, TodoItem next) {
    final previousStart = previous.createdDate ?? previous.createdAt;
    final previousEnd = previous.dueDate?.millisecondsSinceEpoch;
    final nextStart = next.createdDate ?? next.createdAt;
    final nextEnd = next.dueDate?.millisecondsSinceEpoch;
    if (previousEnd == null || nextEnd == null) return null;
    if (previousStart >= nextEnd || nextStart >= previousEnd) return null;
    return _scheduleConflictPairKey(
      previous.id,
      previousStart,
      previousEnd,
      next.id,
      nextStart,
      nextEnd,
    );
  }

  static TodoItem _copyForNextRecurrence(TodoItem source) {
    return TodoItem(
      title: source.title,
      createdDate: source.createdDate,
      recurrence: source.recurrence,
      recurrenceSeriesId: source.recurrenceSeriesId ?? source.id,
      customIntervalDays: source.customIntervalDays,
      recurrenceEndDate: source.recurrenceEndDate,
      dueDate: source.dueDate,
      remark: source.remark,
      imagePath: source.imagePath,
      originalText: source.originalText,
      groupId: source.groupId,
      reminderMinutes: source.reminderMinutes,
      teamUuid: source.teamUuid,
      creatorId: source.creatorId,
      creatorName: source.creatorName,
      teamName: source.teamName,
      collabType: source.collabType,
      isAllDay: source.isAllDay,
      categoryId: source.categoryId,
    );
  }

  static void _rollRecurrenceDateByDays(TodoItem todo, int days) {
    if (todo.dueDate != null) {
      final originalDueDate = todo.dueDate!;
      todo.dueDate = DateTime(
        originalDueDate.year,
        originalDueDate.month,
        originalDueDate.day + days,
        originalDueDate.hour,
        originalDueDate.minute,
        originalDueDate.second,
        originalDueDate.millisecond,
        originalDueDate.microsecond,
      );
    }
    if (todo.createdDate != null) {
      final originalCreatedDate =
          DateTime.fromMillisecondsSinceEpoch(todo.createdDate!, isUtc: true)
              .toLocal();
      todo.createdDate = DateTime(
        originalCreatedDate.year,
        originalCreatedDate.month,
        originalCreatedDate.day + days,
        originalCreatedDate.hour,
        originalCreatedDate.minute,
        originalCreatedDate.second,
        originalCreatedDate.millisecond,
      ).millisecondsSinceEpoch;
    }
  }

  static Future<bool> deleteTodoGlobally(
      String username, String idToDelete) async {
    List<TodoItem> localTodos = await getTodos(username);
    int index = localTodos.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localTodos[index].isDeleted = true;

    try {
      localTodos[index].markAsChanged();
    } catch (_) {
      localTodos[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
      localTodos[index].version += 1;
    }

    await saveTodos(username, localTodos, sync: true);
    return true;
  }

  // ==========================================
  // 📁 待办组 (Todo Groups)
  // ==========================================
  static Future<void> saveTodoGroups(String username, List<TodoGroup> items,
      {bool sync = true, bool isSyncSource = false}) async {
    final Map<String, TodoGroup> dedupeMap = {};

    for (var item in items) {
      if (!dedupeMap.containsKey(item.id) ||
          item.updatedAt > dedupeMap[item.id]!.updatedAt) {
        dedupeMap[item.id] = item;
      }
    }

    final db = await DatabaseHelper.instance.database;
    final existingRows = await db.query('todo_groups');
    final existingItemsMap = <String, Map<String, dynamic>>{
      for (final row in existingRows) row['uuid'].toString(): row,
    };
    final batch = db.batch();
    for (var item in dedupeMap.values) {
      bool hasChanged = true;
      final oldData = existingItemsMap[item.id];
      if (oldData != null) {
        hasChanged = _hasSubstantialChange(oldData, item.toJson(), [
          'name',
          'is_expanded',
          'is_deleted',
          'team_uuid',
          'version',
          'updated_at',
          'has_conflict',
          'conflict_data',
        ]);
      }

      if (!isSyncSource && hasChanged) {
        batch.insert('op_logs', {
          'op_type': 'UPSERT',
          'target_table': 'todo_groups',
          'target_uuid': item.id,
          'data_json': jsonEncode(item.toJson()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'is_synced': 0,
          'sync_error': '',
        });
      }

      if (hasChanged || oldData == null) {
        batch.insert(
            'todo_groups',
            {
              'uuid': item.id,
              'team_uuid': item.teamUuid,
              'team_name': item.teamName,
              'creator_id': item.creatorId,
              'creator_name': item.creatorName,
              'name': item.name,
              'is_expanded': item.isExpanded ? 1 : 0,
              'is_deleted': item.isDeleted ? 1 : 0,
              'version': item.version,
              'updated_at': item.updatedAt,
              'created_at': item.createdAt,
              'has_conflict': item.hasConflict ? 1 : 0,
              'conflict_data': item.conflictData != null
                  ? jsonEncode(item.conflictData)
                  : null
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
    _inflightTodoRequests.clear();

    unawaited(_clearTodoGroupPrefsMirror(username));
    if (sync) requestSync(username);
  }

  static Future<void> _clearTodoGroupPrefsMirror(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("${keyTodoGroups}_$username");
    await prefs.remove(keyTodoGroups);
  }

  static Future<List<TodoGroup>> getTodoGroups(String username,
      {bool includeDeleted = false}) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      await _clearGhostConflictFlags(db);
      final prefs = await SharedPreferences.getInstance();

      // 1. 迁移检查
      final List<Map<String, dynamic>> sqliteCount =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM todo_groups');
      if (sqliteCount.first['cnt'] == 0) {
        List<String> legacyJsonList =
            prefs.getStringList("${keyTodoGroups}_$username") ?? [];

        // 🚀 核心修复：增加一次性迁移保护
        if (legacyJsonList.isEmpty && username.isNotEmpty) {
          final String markerKey = "${keyTodoGroups}_${username}_migrated";
          if (!(prefs.getBool(markerKey) ?? false)) {
            legacyJsonList = prefs.getStringList(keyTodoGroups) ?? [];
            if (legacyJsonList.isNotEmpty) {
              await prefs.setBool(markerKey, true);
            }
          }
        }

        if (legacyJsonList.isNotEmpty) {
          debugPrint("🚀 自动迁移待办组数据至 SQLite...");
          List<TodoGroup> legacyData = legacyJsonList
              .map((e) => TodoGroup.fromJson(jsonDecode(e)))
              .toList();
          await saveTodoGroups(username, legacyData,
              sync: false, isSyncSource: true);
        }
      }

      // 2. 从 SQL 读取 (排除逻辑删除)
      final List<Map<String, dynamic>> maps = await db.query('todo_groups',
          where: includeDeleted ? null : 'is_deleted = 0');
      if (maps.isNotEmpty) {
        return maps
            .map((m) => TodoGroup(
                  id: m['uuid'],
                  name: m['name'] ?? '',
                  isExpanded: m['is_expanded'] == 1,
                  isDeleted: m['is_deleted'] == 1,
                  version: m['version'] ?? 1,
                  updatedAt:
                      m['updated_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  createdAt:
                      m['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
                  teamUuid: m['team_uuid'],
                  teamName: m['team_name'],
                  creatorId: m['creator_id'],
                  creatorName: m['creator_name'],
                  hasConflict: m['has_conflict'] == 1,
                  conflictData: m['conflict_data'] != null
                      ? jsonDecode(m['conflict_data'])
                      : null,
                ))
            .toList();
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("⚠️ TodoGroups SQL 引擎异常: $e");
    }

    // 逃生通道
    final prefs = await StorageService.prefs;
    List<String> list = prefs.getStringList("${keyTodoGroups}_$username") ?? [];
    List<TodoGroup> result = [];

    for (var e in list) {
      try {
        result.add(TodoGroup.fromJson(jsonDecode(e)));
      } catch (err) {
        debugPrint("Parse TodoGroup Error: $err");
      }
    }
    return result;
  }

  static Future<void> deleteTodoGroupGlobally(
      String username, String idToDelete) async {
    List<TodoGroup> localGroups = await getTodoGroups(username);
    int index = localGroups.indexWhere((t) => t.id == idToDelete);

    if (index != -1) {
      localGroups[index].isDeleted = true;
      localGroups[index].markAsChanged();
      await saveTodoGroups(username, localGroups, sync: true);
    }

    // 同时将组内的待办恢复为未分组状态
    List<TodoItem> allTodos = await getTodos(username);
    bool todoChanged = false;
    for (var t in allTodos) {
      if (t.groupId == idToDelete) {
        t.groupId = null;
        t.markAsChanged();
        todoChanged = true;
      }
    }
    if (todoChanged) {
      await saveTodos(username, allTodos, sync: true);
    }
  }

  // ==========================================
  // 时间日志 (Time Logs)
  // ==========================================
  static Future<void> saveTimeLogs(String username, List<TimeLogItem> items,
          {bool sync = true}) =>
      PomodoroStorage.saveTimeLogs(
        username,
        items,
        sync: sync,
        requestSync: requestSync,
      );

  static Future<List<TimeLogItem>> getTimeLogs(String username, {int? limit}) =>
      PomodoroStorage.getTimeLogs(
        username,
        limit: limit,
        saveMigratedTimeLogs: saveTimeLogs,
      );

  static Future<bool> deleteTimeLogGlobally(
      String username, String idToDelete) async {
    List<TimeLogItem> localLogs = await getTimeLogs(username);
    int index = localLogs.indexWhere((t) => t.id == idToDelete);

    if (index == -1) return false;

    localLogs[index].isDeleted = true;
    localLogs[index].markAsChanged();

    await saveTimeLogs(username, localLogs, sync: true);
    return true;
  }

  // ==========================================
  // 屏幕时间与应用映射
  // ==========================================
  static Future<void> saveLocalScreenTime(Map<dynamic, dynamic> stats) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = _scopedKey(keyLocalScreenTime, username);
    await prefs.setString(key, jsonEncode(stats));
  }

  static Future<Map<String, dynamic>?> getLocalScreenTimePackage() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = _scopedKey(keyLocalScreenTime, username);
    String? s = prefs.getString(key);
    // 兼容旧版全局 key 的历史数据
    s ??= prefs.getString(keyLocalScreenTime);
    return s != null ? jsonDecode(s) as Map<String, dynamic> : null;
  }

  static Future<Map<String, dynamic>> getLocalScreenTimeMap() async {
    return await getLocalScreenTimePackage() ?? {};
  }

  static Future<List<dynamic>> getLocalScreenTime() async {
    final map = await getLocalScreenTimeMap();
    return map['apps'] as List<dynamic>? ?? [];
  }

  static Future<void> saveScreenTimeCache(List<dynamic> stats) async {
    if (stats.isEmpty) return;

    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final historyKey = _scopedKey(keyScreenTimeHistory, username);
    final cacheKey = _scopedKey(keyScreenTimeCache, username);
    final syncKey = _scopedKey(keyLastScreenTimeSync, username);
    final now = DateTime.now();
    final String today = DateFormat('yyyy-MM-dd').format(now);

    // 1. 获取已有的历史记录
    String? histStr = prefs.getString(historyKey);
    histStr ??= prefs.getString(keyScreenTimeHistory);
    Map<String, dynamic> history = {};
    if (histStr != null) {
      try {
        history = jsonDecode(histStr);
      } catch (e) {
        debugPrint("解析历史记录失败: $e");
      }
    }

    // 2. 更新历史记录
    // 即使 stats 里混入了旧数据，我们也只将其视为“今日最新快照”存储在 today 键下
    // 如果你想更严格，可以在此处对 stats 进行过滤，确保 e['date'] == today
    history[today] = stats;

    // 3. 维护 14 天滑动窗口 (删除最旧的记录)
    if (history.length > 14) {
      var sortedKeys = history.keys.toList()..sort();
      while (history.length > 14) {
        history.remove(sortedKeys.removeAt(0));
      }
    }

    // 4. 原子化写入本地存储
    // 🚀 核心优化：逐步弃用 Prefs 存储历史记录，迁移至 SQL
    try {
      await saveScreenTimeHistoryToSql(today, stats);
      // 如果写入 SQL 成功，可以尝试清理一下 Prefs 里的旧数据（如果它太大了）
      if (histStr != null && histStr.length > 1024 * 500) {
        // > 500KB
        await prefs.remove(historyKey);
        debugPrint("🗑️ 已清理过大的 ScreenTime Prefs 历史记录");
      }
    } catch (e) {
      await prefs.setString(historyKey, jsonEncode(history));
    }

    // 5. 更新“当前视图快照” (keyScreenTimeCache)
    // 🚀 核心修复：只有当最新更新日期确实是今天时，才更新首页显示的 Cache
    // 这样如果凌晨同步了旧数据，首页不会被错误覆盖
    await prefs.setString(cacheKey, jsonEncode(stats));

    // 更新最后同步成功的时间戳（记录到毫秒）
    await prefs.setInt(syncKey, now.millisecondsSinceEpoch);
  }

  /// 🚀 将屏幕时间持久化到 SQLite
  static Future<void> saveScreenTimeHistoryToSql(
      String date, List<dynamic> stats) async {
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;
    final batch = db.batch();

    // 覆盖写：先删除该日期的旧记录
    batch.delete('screen_time', where: 'record_date = ?', whereArgs: [date]);

    for (var stat in stats) {
      batch.insert('screen_time', {
        'record_date': date,
        'package_name': stat['package_name']?.toString() ?? '',
        'app_name': stat['app_name']?.toString() ?? '',
        'device_name': stat['device_name']?.toString() ?? '',
        'category': stat['category']?.toString() ?? '未分类',
        'duration':
            (stat['duration'] is num) ? (stat['duration'] as num).toInt() : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<List<dynamic>> getScreenTimeCache() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final cacheKey = _scopedKey(keyScreenTimeCache, username);
    final syncKey = _scopedKey(keyLastScreenTimeSync, username);

    // 检查缓存是否是今天的
    int? lastSyncMs = prefs.getInt(syncKey);
    lastSyncMs ??= prefs.getInt(keyLastScreenTimeSync);
    if (lastSyncMs != null) {
      DateTime lastSyncDate =
          DateTime.fromMillisecondsSinceEpoch(lastSyncMs).toLocal();
      DateTime now = DateTime.now();

      // 如果缓存日期不是今天，说明缓存已过期，返回空列表触发新的同步
      if (lastSyncDate.year != now.year ||
          lastSyncDate.month != now.month ||
          lastSyncDate.day != now.day) {
        debugPrint("缓存已过期 (日期不匹配)，清理过期数据");
        await prefs.remove(cacheKey);
        return [];
      }
    }

    String? jsonStr = prefs.getString(cacheKey);
    jsonStr ??= prefs.getString(keyScreenTimeCache);
    if (jsonStr != null) {
      try {
        return jsonDecode(jsonStr);
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  static Future<Map<String, List<dynamic>>> getScreenTimeHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    final String historyKey = _scopedKey(keyScreenTimeHistory, username);
    final dbHelper = DatabaseHelper.instance;

    try {
      // 1. 迁移检查 (一次性从 Prefs 搬运到 SQL)
      final String migrationKey = "migrated_screentime_$username";
      if (!(prefs.getBool(migrationKey) ?? false)) {
        String? jsonStr = prefs.getString(historyKey) ??
            prefs.getString(keyScreenTimeHistory);
        if (jsonStr != null && jsonStr.isNotEmpty) {
          debugPrint("🚀 发现 ScreenTime 历史记录，正在执行 SQL 迁移...");
          try {
            Map<String, dynamic> history = jsonDecode(jsonStr);
            for (var entry in history.entries) {
              if (entry.value is List) {
                await saveScreenTimeHistoryToSql(
                    entry.key, entry.value as List);
              }
            }
            await prefs.remove(historyKey);
            await prefs.remove(keyScreenTimeHistory);
            debugPrint("✅ ScreenTime 迁移完成并已清理 Prefs");
          } catch (e) {
            debugPrint("⚠️ ScreenTime 迁移解析失败: $e");
          }
        }
        await prefs.setBool(migrationKey, true);
      }

      final db = await dbHelper.database;
      // 2. 从 SQL 读取所有记录并按日期分组
      final List<Map<String, dynamic>> maps = await db.query(
        'screen_time',
        orderBy: 'record_date DESC',
      );

      Map<String, List<dynamic>> result = {};
      for (var m in maps) {
        String date = m['record_date']?.toString() ?? '';
        if (date.isEmpty) continue;
        result.putIfAbsent(date, () => []);
        result[date]!.add({
          'package_name': m['package_name'],
          'app_name': m['app_name'],
          'device_name': m['device_name'],
          'category': m['category'],
          'duration': m['duration'],
        });
      }
      final int userId = prefs.getInt('current_user_id') ?? 0;
      if (userId > 0) {
        final datesNeedingDeviceNames = result.entries
            .where((entry) => entry.value.any((item) {
                  final deviceName = item['device_name']?.toString() ?? '';
                  return deviceName.isEmpty;
                }))
            .map((entry) => entry.key)
            .toList();

        for (final date in datesNeedingDeviceNames) {
          try {
            final cloudStats = await ApiService.fetchScreenTime(userId, date);
            if (cloudStats.isNotEmpty) {
              await saveScreenTimeHistoryToSql(date, cloudStats);
              result[date] = cloudStats;
            }
          } catch (e) {
            debugPrint("⚠️ ScreenTime History 云端补齐失败($date): $e");
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint("⚠️ ScreenTime History SQL 异常: $e");
      String? jsonStr =
          prefs.getString(historyKey) ?? prefs.getString(keyScreenTimeHistory);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          Map<String, dynamic> raw = jsonDecode(jsonStr);
          return raw
              .map((key, value) => MapEntry(key, List<dynamic>.from(value)));
        } catch (_) {}
      }
    }
    return {};
  }

  static Future<void> updateLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    await prefs.setInt(_scopedKey(keyLastScreenTimeSync, username),
        DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastScreenTimeSync() async {
    final prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString(keyCurrentUser);
    int? timestamp = prefs.getInt(_scopedKey(keyLastScreenTimeSync, username));
    timestamp ??= prefs.getInt(keyLastScreenTimeSync);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    }
    return null;
  }

  static Future<void> syncAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    int? lastSync = prefs.getInt(keyLastMappingsSync);
    DateTime now = DateTime.now();
    if (lastSync != null) {
      DateTime lastDate =
          DateTime.fromMillisecondsSinceEpoch(lastSync, isUtc: true).toLocal();
      if (now.difference(lastDate).inDays < 7) return;
    }
    List<dynamic> mappings = await ApiService.fetchAppMappings();
    if (mappings.isNotEmpty) {
      Map<String, String> lookupMap = {};
      for (var item in mappings) {
        String pkg = item['package_name'] ?? '';
        String mapped = item['mapped_name'] ?? '';
        String cat = item['category'] ?? '未分类';
        if (pkg.isNotEmpty) lookupMap[pkg] = cat;
        if (mapped.isNotEmpty) lookupMap[mapped] = cat;
      }
      await prefs.setString(keyAppMappings, jsonEncode(lookupMap));
      await prefs.setInt(keyLastMappingsSync, now.millisecondsSinceEpoch);
    }
  }

  static Future<Map<String, String>> getAppMappings() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString(keyAppMappings);
    if (jsonStr != null) {
      try {
        return Map<String, String>.from(jsonDecode(jsonStr));
      } catch (_) {}
    }
    return {};
  }

  // ==========================================
  // 🚀 核心：增量同步算法 (包含屏幕时间推送)
  // ==========================================

  static Future<void> resetSyncTime(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_sync_time_aliyun_$username');
    await prefs.remove('last_sync_time_cf_$username');
    await prefs.remove('last_sync_time_$username'); // 兼容旧版本
  }

  static Future<Map<String, dynamic>> syncData(
    String username, {
    bool syncTodos = true,
    bool syncCountdowns = true,
    bool forceFullSync = false,
    bool uploadAllLocal = false,
    BuildContext? context,
    bool syncTimeLogs = true,
    bool syncPomodoro = true,
    bool syncPlanBlocks = true,
    bool syncFixedSchedules = true,
    bool syncHabits = true,
  }) async {
    final bool shouldUploadAllLocal = uploadAllLocal || forceFullSync;
    // 1. 状态锁：防止重复进入
    if (!syncTodos &&
        !syncCountdowns &&
        !syncTimeLogs &&
        !syncPomodoro &&
        !syncPlanBlocks &&
        !syncFixedSchedules &&
        !syncHabits) {
      return {'success': false, 'hasChanges': false};
    }
    if (_isSyncing) {
      return {'success': false, 'hasChanges': false, 'error': '同步进行中，请稍后重试'};
    }
    _isSyncing = true;
    bool hasChanges = false;
    List<ConflictInfo> conflicts = [];
    final Set<String> updatedTodoIds = <String>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      int? userId = prefs.getInt('current_user_id');
      if (userId == null) throw Exception("用户未登录");

      // 2. 环境信息准备
      final String deviceId =
          await UserSessionStorage.getDeviceIdForUser(username);
      final String friendlyName =
          await UserSessionStorage.getDeviceFriendlyName();
      final String serverKey =
          ApiService.baseUrl == ApiService.aliyunProdUrl ? "aliyun" : "cf";
      final fixedScheduleServerScope = base64Url
          .encode(utf8.encode(ApiService.effectiveBaseUrl))
          .replaceAll('=', '');
      final fixedScheduleBootstrapKey =
          'fixed_schedule_sync_v1_${fixedScheduleServerScope}_$username';
      final fixedScheduleSyncInitialized =
          prefs.getBool(fixedScheduleBootstrapKey) == true;
      final habitBootstrapKey =
          'habit_sync_v1_${fixedScheduleServerScope}_$username';
      final habitSyncInitialized = prefs.getBool(habitBootstrapKey) == true;
      int lastSyncTime = forceFullSync
          ? 0
          : (prefs.getInt('last_sync_time_${serverKey}_$username') ?? 0);
      _lastSyncRequestAt = DateTime.now().millisecondsSinceEpoch;

      // 3. 🛡️ 核心修复：基于 op_logs 识别脏数据，并进行 UUID 去重处理（防止 1000+ 冗余同步）
      final db = await DatabaseHelper.instance.database;
      List<Map<String, dynamic>> dirtyTodos = [];
      List<Map<String, dynamic>> dirtyGroups = [];
      List<Map<String, dynamic>> dirtyCountdowns = [];
      List<Map<String, dynamic>> dirtyTimeLogs = [];
      List<Map<String, dynamic>> dirtyPlanBlocks = [];
      List<Map<String, dynamic>> dirtyFixedSchedules = [];
      List<Map<String, dynamic>> dirtyHabitGoals = [];
      List<Map<String, dynamic>> dirtyHabitRules = [];
      List<Map<String, dynamic>> dirtyHabitCheckIns = [];
      List<TodoItem> allLocalTodos =
          await getTodos(username, includeDeleted: true);
      List<TodoGroup> allLocalGroups =
          await getTodoGroups(username, includeDeleted: true);
      List<CountdownItem> allLocalCountdowns =
          await getCountdowns(username, includeDeleted: true);
      List<TimeLogItem> allLocalTimeLogs = await getTimeLogs(username);
      List<TodoPlanBlock> allLocalPlanBlocks =
          await getPlanBlocks(username, includeDeleted: true);
      List<FixedScheduleItem> allLocalFixedSchedules =
          await getFixedSchedules(username, includeDeleted: true);
      final List<HabitGoal> allLocalHabitGoals =
          await HabitStorage.getHabitGoals(includeDeleted: true);
      final List<HabitGoalRuleRevision> allLocalHabitRules =
          await HabitStorage.getRuleRevisions();
      final List<HabitCheckIn> allLocalHabitCheckIns =
          await HabitStorage.getCheckIns(includeDeleted: true);
      final autoResolvedMigrationConflicts =
          _clearResolvedRecurrenceMigrationConflicts(allLocalTodos);
      if (autoResolvedMigrationConflicts.isNotEmpty) {
        await saveTodos(
          username,
          autoResolvedMigrationConflicts,
          sync: true,
          recomputeScheduleConflicts: false,
        );
        hasChanges = true;
        debugPrint(
            '🧹 [同步修复] 已自动消解 ${autoResolvedMigrationConflicts.length} 条仅由循环系列迁移产生的版本冲突');
      }
      final repairedLocalSeriesIds =
          await _repairLocalRecurrenceSeriesAliasesFromHistory(
        db,
        allLocalTodos,
      );
      if (repairedLocalSeriesIds.isNotEmpty) {
        final versionsBeforeDedupe = {
          for (final todo in allLocalTodos) todo.id: todo.version,
        };
        final deletedBeforeDedupe = {
          for (final todo in allLocalTodos)
            if (todo.isDeleted) todo.id,
        };
        _deduplicatePersistedRecurrenceOccurrences(allLocalTodos);
        repairedLocalSeriesIds.addAll(allLocalTodos
            .where((todo) =>
                todo.isDeleted && !deletedBeforeDedupe.contains(todo.id))
            .map((todo) => todo.id));

        final repairedItems = allLocalTodos
            .where((todo) => repairedLocalSeriesIds.contains(todo.id))
            .toList();
        for (final todo in repairedItems) {
          // 去重分支已经提升过版本，只为单纯归并系列的实例补一次变更。
          if (todo.version == versionsBeforeDedupe[todo.id]) {
            todo.markAsChanged();
          }
        }
        await saveTodos(
          username,
          repairedItems,
          sync: true,
          recomputeScheduleConflicts: false,
        );
        hasChanges = true;
        debugPrint(
            '🧷 [同步修复] 根据本机同步历史将 ${repairedItems.length} 个被拆分的循环实例归回原系列');
      }
      final localTodosById = {for (final item in allLocalTodos) item.id: item};
      final localGroupsById = {
        for (final item in allLocalGroups) item.id: item
      };
      final localCountdownsById = {
        for (final item in allLocalCountdowns) item.id: item
      };
      if (!forceFullSync &&
          ((syncCountdowns && allLocalCountdowns.isEmpty) ||
              (syncTimeLogs && allLocalTimeLogs.isEmpty))) {
        debugPrint('🔄 本地倒数日/时间日志为空，自动降级为全量拉取以修复空库');
        lastSyncTime = 0;
      }

      // 按时间戳升序排列，这样 Map 的 putIfAbsent/赋值逻辑会自然保留最后一次更新
      final List<Map<String, dynamic>> pendingOps = await db.query('op_logs',
          where: 'is_synced = 0', orderBy: 'timestamp ASC');
      final requestOplogSnapshot = pendingOps
          .map(SyncOplogEntry.fromRow)
          .whereType<SyncOplogEntry>()
          .toList(growable: false);
      // 🚀 记录有待同步 oplog 的 待办 UUID，防止 saveTodos(isSyncSource=true) 覆盖用户修改
      _pendingSyncOplogUuids = pendingOps
          .where((op) => op['target_table'] == 'todos')
          .map((op) => op['target_uuid']?.toString() ?? '')
          .where((uuid) => uuid.isNotEmpty)
          .toSet();
      final pendingByTable = <String, int>{};
      for (final op in pendingOps) {
        final t = (op['target_table'] ?? 'unknown').toString();
        pendingByTable[t] = (pendingByTable[t] ?? 0) + 1;
      }
      /*debugPrint(
          '🧪 [SyncDiag][PendingOps] total=${pendingOps.length} byTable=$pendingByTable');*/

      final Map<String, Map<String, dynamic>> dedupTodos = {};
      final Map<String, Map<String, dynamic>> dedupGroups = {};
      final Map<String, Map<String, dynamic>> dedupCountdowns = {};
      final Map<String, Map<String, dynamic>> dedupPlanBlocks = {};
      final Map<String, Map<String, dynamic>> dedupFixedSchedules = {};
      final Map<String, Map<String, dynamic>> dedupHabitGoals = {};
      final Map<String, Map<String, dynamic>> dedupHabitRules = {};
      final Map<String, Map<String, dynamic>> dedupHabitCheckIns = {};
      final List<int> consumedConflictOpIds = [];

      for (var op in pendingOps) {
        final table = op['target_table'];
        final uuid = op['target_uuid']?.toString();
        final dataJson = op['data_json'];
        final opId = (op['id'] as num?)?.toInt();

        if (dataJson == null || uuid == null) continue;
        final data = jsonDecode(dataJson.toString());

        if (table == 'todos') {
          data.remove('image_path');
          data.remove('imagePath');
          // 🚀 已失败的冲突 op_log 不再重新发送（避免无限循环）
          if (op['sync_error'] == 'server_conflict') {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          final localTodo = localTodosById[uuid];
          final hasLocalVersionConflict = localTodo != null &&
              localTodo.hasConflict &&
              _hasVersionConflict(localTodo.serverVersionData);
          if (_payloadHasVersionConflict(data) || hasLocalVersionConflict) {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupTodos[uuid] = _stripClientOnlyConflictForSync(data);
        } else if (table == 'todo_groups') {
          if (op['sync_error'] == 'server_conflict') {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          if (_payloadHasConflict(data) ||
              (localGroupsById[uuid]?.hasConflict ?? false)) {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupGroups[uuid] = data;
        } else if (table == 'countdowns') {
          if (op['sync_error'] == 'server_conflict') {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          if (_payloadHasConflict(data) ||
              (localCountdownsById[uuid]?.hasConflict ?? false)) {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupCountdowns[uuid] = data;
        } else if (table == 'todo_plan_blocks' && syncPlanBlocks) {
          dedupPlanBlocks[uuid] = data;
        } else if (table == 'fixed_schedules' && syncFixedSchedules) {
          dedupFixedSchedules[uuid] = data;
        } else if (table == 'habit_goals' && syncHabits) {
          if (op['sync_error'] == 'server_conflict') {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          if (_payloadHasConflict(data) ||
              (allLocalHabitGoals
                  .any((g) => g.uuid == uuid && g.hasConflict))) {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupHabitGoals[uuid] = data;
        } else if (table == 'habit_goal_rule_revisions' && syncHabits) {
          if (op['sync_error'] == 'server_conflict') {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          if (_payloadHasConflict(data) ||
              (allLocalHabitRules
                  .any((r) => r.uuid == uuid && r.hasConflict))) {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupHabitRules[uuid] = data;
        } else if (table == 'habit_checkins' && syncHabits) {
          if (op['sync_error'] == 'server_conflict') {
            if (opId != null) consumedConflictOpIds.add(opId);
            continue;
          }
          dedupHabitCheckIns[uuid] = data;
        }
      }

      if (consumedConflictOpIds.isNotEmpty) {
        final placeholders =
            List.filled(consumedConflictOpIds.length, '?').join(',');
        await db.update(
          'op_logs',
          {'is_synced': 1, 'sync_error': ''},
          where: 'id IN ($placeholders)',
          whereArgs: consumedConflictOpIds,
        );
        /*debugPrint(
            '🧪 [SyncDiag][PendingOps] consumed conflict ops=${consumedConflictOpIds.length}');*/
      }

      dirtyTodos = dedupTodos.values.toList();
      dirtyGroups = dedupGroups.values.toList();
      dirtyCountdowns = dedupCountdowns.values.toList();
      dirtyPlanBlocks = dedupPlanBlocks.values.toList();
      dirtyFixedSchedules = dedupFixedSchedules.values.toList();
      dirtyHabitGoals = dedupHabitGoals.values.toList();
      dirtyHabitRules = dedupHabitRules.values.toList();
      dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();

      // 兜底：除 op_logs 外，再按 updatedAt 增量补采，避免日志遗漏导致改删/新增不同步
      if (syncTodos) {
        for (final item in allLocalTodos) {
          if (item.updatedAt > lastSyncTime) {
            if (item.hasConflict &&
                _hasVersionConflict(item.serverVersionData)) {
              continue;
            }
            final data = item.toJson();
            data.remove('image_path');
            data.remove('imagePath');
            if (item.isDeleted &&
                _recurrenceDedupeTombstoneIds.contains(item.id)) {
              data['_recurrence_delete_reason'] = 'dedupe';
            }
            dedupTodos[item.id] = _stripClientOnlyConflictForSync(data);
          }
        }
        dirtyTodos = dedupTodos.values.toList();
      }
      if (syncCountdowns) {
        for (final item in allLocalCountdowns) {
          if (item.updatedAt > lastSyncTime) {
            if (item.hasConflict) continue;
            dedupCountdowns[item.id] = item.toJson();
          }
        }
        dirtyCountdowns = dedupCountdowns.values.toList();
      }
      for (final item in allLocalGroups) {
        if (item.updatedAt > lastSyncTime) {
          if (item.hasConflict) continue;
          dedupGroups[item.id] = item.toJson();
        }
      }
      dirtyGroups = dedupGroups.values.toList();

      // 兜底：规划块除 op_logs 外，再按 updatedAt 增量补采一遍，避免个别日志遗漏导致改删不同步
      if (syncPlanBlocks) {
        for (final item in allLocalPlanBlocks) {
          if (item.updatedAt > lastSyncTime) {
            dedupPlanBlocks[item.id] = item.toJson();
          }
        }
        dirtyPlanBlocks = dedupPlanBlocks.values.toList();
      }

      // 首次与支持 fixed_schedules v1 的服务端握手前，全量携带本地固定
      // 日程，确保“本地纵向切片”时期创建的数据不会因旧水位线而漏传。
      if (syncFixedSchedules) {
        for (final item in allLocalFixedSchedules) {
          if (!fixedScheduleSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupFixedSchedules[item.id] = item.toJson();
          }
        }
        dirtyFixedSchedules = dedupFixedSchedules.values.toList();
      }

      // 习惯：与固定日程一致的引导策略。首次与支持 habits v1 的服务端
      // 握手前全量携带本地习惯数据，避免 PR5 之前（未写 oplog）创建的
      // 习惯因旧水位线而漏传。
      if (syncHabits) {
        for (final item in allLocalHabitGoals) {
          if (!habitSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupHabitGoals[item.uuid] = item.toJson();
          }
        }
        for (final item in allLocalHabitRules) {
          if (!habitSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupHabitRules[item.uuid] = item.toJson();
          }
        }
        for (final item in allLocalHabitCheckIns) {
          if (!habitSyncInitialized || item.updatedAt > lastSyncTime) {
            dedupHabitCheckIns[item.uuid] = item.toJson();
          }
        }
        dirtyHabitGoals = dedupHabitGoals.values.toList();
        dirtyHabitRules = dedupHabitRules.values.toList();
        dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
      }

      if (shouldUploadAllLocal) {
        for (final item in allLocalTodos) {
          if (item.hasConflict && _hasVersionConflict(item.serverVersionData)) {
            continue;
          }
          final data = _stripClientOnlyConflictForSync(item.toJson());
          data.remove('image_path');
          data.remove('imagePath');
          if (item.isDeleted &&
              _recurrenceDedupeTombstoneIds.contains(item.id)) {
            data['_recurrence_delete_reason'] = 'dedupe';
          }
          dedupTodos.putIfAbsent(item.id, () => data);
        }
        for (final item in allLocalGroups) {
          if (item.hasConflict) continue;
          final data = item.toJson();
          dedupGroups.putIfAbsent(item.id, () => data);
        }
        for (final item in allLocalCountdowns) {
          if (item.hasConflict) continue;
          final data = item.toJson();
          dedupCountdowns.putIfAbsent(item.id, () => data);
        }
        if (syncPlanBlocks) {
          for (final item in allLocalPlanBlocks) {
            final data = item.toJson();
            dedupPlanBlocks.putIfAbsent(item.id, () => data);
          }
        }
        if (syncFixedSchedules) {
          for (final item in allLocalFixedSchedules) {
            dedupFixedSchedules.putIfAbsent(item.id, item.toJson);
          }
        }
        if (syncHabits) {
          for (final item in allLocalHabitGoals) {
            dedupHabitGoals.putIfAbsent(item.uuid, item.toJson);
          }
          for (final item in allLocalHabitRules) {
            dedupHabitRules.putIfAbsent(item.uuid, item.toJson);
          }
          for (final item in allLocalHabitCheckIns) {
            dedupHabitCheckIns.putIfAbsent(item.uuid, item.toJson);
          }
        }
        dirtyTodos = dedupTodos.values.toList();
        dirtyGroups = dedupGroups.values.toList();
        dirtyCountdowns = dedupCountdowns.values.toList();
        dirtyPlanBlocks = dedupPlanBlocks.values.toList();
        dirtyFixedSchedules = dedupFixedSchedules.values.toList();
        dirtyHabitGoals = dedupHabitGoals.values.toList();
        dirtyHabitRules = dedupHabitRules.values.toList();
        dirtyHabitCheckIns = dedupHabitCheckIns.values.toList();
      }

      // TimeLogs 暂时保持原有逻辑 (直到迁移至 SQL)
      dirtyTimeLogs = allLocalTimeLogs
          .where((t) => t.updatedAt > lastSyncTime)
          .map((t) => t.toJson())
          .toList();

      // debugPrint('🔍 [同步判定] lastSyncTime: $lastSyncTime, 本地总任务数: ${allLocalTodos.length}');

      // 4. 读取本机待同步屏幕时间 (改为 Map 结构)
      Map<String, dynamic> localPackage = await getLocalScreenTimeMap();
      List<dynamic> localScreenStats = localPackage['apps'] ?? [];
      String? recordDate = localPackage['date']; // 🚀 从缓存中拿原始日期

      Map<String, dynamic>? screenPayload;
      if (localScreenStats.isNotEmpty) {
        try {
          // 如果没有记录日期（旧版本升级上来），退而求其次用今天
          final String finalDate =
              recordDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

          screenPayload = {
            'device_name': friendlyName,
            'record_date': finalDate,
            'apps': localScreenStats
                .whereType<Map>()
                .map((e) => {
                      'app_name': e['app_name']?.toString() ?? 'Unknown',
                      'duration': (e['duration'] is int) ? e['duration'] : 0,
                    })
                .toList(),
          };
          debugPrint(
              "🚀 准备同步本机屏幕时间 ($finalDate): ${localScreenStats.length} 条数据");
        } catch (se) {
          debugPrint("屏幕时间 payload 构造失败: $se");
        }
      } else {
        // null
      }

      // 5. 发起网络同步请求
      Future<Map<String, dynamic>> sendSyncRequest() {
        return ApiService.postDeltaSync(
          userId: userId,
          lastSyncTime: lastSyncTime,
          deviceId: deviceId,
          todosChanges: dirtyTodos,
          todoGroupsChanges: dirtyGroups,
          countdownsChanges: dirtyCountdowns,
          timeLogsChanges: dirtyTimeLogs,
          planBlocksChanges: dirtyPlanBlocks,
          fixedSchedulesChanges: dirtyFixedSchedules,
          fixedSchedulesFullSync: syncFixedSchedules &&
              (!fixedScheduleSyncInitialized || forceFullSync),
          habitGoalsChanges: dirtyHabitGoals,
          habitRuleChanges: dirtyHabitRules,
          habitCheckInChanges: dirtyHabitCheckIns,
          habitFullSync: syncHabits && (!habitSyncInitialized || forceFullSync),
          screenTime: screenPayload,
          forceFullSync: forceFullSync,
        );
      }

      Map<String, dynamic> response = await sendSyncRequest();
      bool hasPendingUpload() =>
          dirtyTodos.isNotEmpty ||
          dirtyGroups.isNotEmpty ||
          dirtyCountdowns.isNotEmpty ||
          dirtyTimeLogs.isNotEmpty ||
          dirtyPlanBlocks.isNotEmpty ||
          dirtyFixedSchedules.isNotEmpty ||
          dirtyHabitGoals.isNotEmpty ||
          dirtyHabitRules.isNotEmpty ||
          dirtyHabitCheckIns.isNotEmpty ||
          screenPayload != null;

      bool isDebounceIgnored(Map<String, dynamic> syncResponse) {
        if (!forceFullSync && !hasPendingUpload()) {
          return false;
        }
        final remotePayloadEmpty = (syncResponse['server_todos'] as List?)
                    ?.isEmpty ==
                true &&
            (syncResponse['server_todo_groups'] as List?)?.isEmpty == true &&
            (syncResponse['server_countdowns'] as List?)?.isEmpty == true &&
            (syncResponse['server_time_logs'] as List?)?.isEmpty == true &&
            (syncResponse['server_pomodoros'] as List?)?.isEmpty == true &&
            (syncResponse['server_tags'] as List?)?.isEmpty == true &&
            (syncResponse['server_plan_blocks'] as List?)?.isEmpty == true &&
            (syncResponse['server_fixed_schedules'] as List?)?.isEmpty ==
                true &&
            (syncResponse['server_habit_goals'] as List?)?.isEmpty == true &&
            (syncResponse['server_habit_goal_rules'] as List?)?.isEmpty ==
                true &&
            (syncResponse['server_habit_checkins'] as List?)?.isEmpty == true;
        final syncTimeUnchanged =
            (syncResponse['new_sync_time'] ?? -1) == lastSyncTime;
        return syncResponse['success'] == true &&
            syncTimeUnchanged &&
            remotePayloadEmpty &&
            (syncResponse['status'] == 'ignored' ||
                forceFullSync ||
                hasPendingUpload());
      }

      if (isDebounceIgnored(response)) {
        debugPrint('⏳ [同步] 命中服务端防抖空响应，3.2s 后自动重试一次');
        await Future.delayed(const Duration(milliseconds: 3200));
        response = await sendSyncRequest();
        if (isDebounceIgnored(response) && hasPendingUpload()) {
          throw Exception('同步被服务端防抖延迟，已保留本地待同步记录');
        }
      }

      final fixedSchedulesSupported =
          SyncCapabilityService.supportsFixedSchedules(
        response['sync_capabilities'],
      );
      final acknowledgeFixedScheduleOps =
          SyncCapabilityService.shouldAcknowledgeFixedScheduleOps(
        syncEnabled: syncFixedSchedules,
        rawCapabilities: response['sync_capabilities'],
      );
      final habitsSupported = SyncCapabilityService.supportsHabits(
        response['sync_capabilities'],
      );
      final acknowledgeHabitOps =
          SyncCapabilityService.shouldAcknowledgeHabitOps(
        syncEnabled: syncHabits,
        rawCapabilities: response['sync_capabilities'],
      );

      // 🚀 提取当前团队列表，用于孤立检测和合并防御
      final List<dynamic>? joinedTeamUuids = response['joined_team_uuids'];
      Set<String> currentTeams = joinedTeamUuids != null
          ? joinedTeamUuids.map((e) => e.toString()).toSet()
          : <String>{};

      // 🚀 补充：当 joinedTeamUuids 为 null 时，从本地 teams 表构建已知团队集合
      // 用于防复活守卫判断团队是否已解散
      if (joinedTeamUuids == null) {
        try {
          final localTeamRows = await db.query('teams', columns: ['uuid']);
          final localKnownTeams =
              localTeamRows.map((r) => r['uuid'].toString()).toSet();
          // 合并到 currentTeams 中，使孤立检测和防复活守卫也能受益
          currentTeams = localKnownTeams;
        } catch (_) {}
      }

      bool isOutsideJoinedTeam(String? teamUuid) {
        return joinedTeamUuids != null &&
            teamUuid != null &&
            teamUuid.isNotEmpty &&
            !currentTeams.contains(teamUuid);
      }

      void markLoadedTeamItemsDeleted(String teamUuid) {
        final cleanupTime = DateTime.now().millisecondsSinceEpoch;

        for (final item in allLocalTodos) {
          if (item.teamUuid == teamUuid && !item.isDeleted) {
            item.isDeleted = true;
            item.version += 1;
            item.updatedAt = cleanupTime;
          }
        }
        for (final item in allLocalGroups) {
          if (item.teamUuid == teamUuid && !item.isDeleted) {
            item.isDeleted = true;
            item.version += 1;
            item.updatedAt = cleanupTime;
          }
        }
        for (final item in allLocalCountdowns) {
          if (item.teamUuid == teamUuid && !item.isDeleted) {
            item.isDeleted = true;
            item.version += 1;
            item.updatedAt = cleanupTime;
          }
        }
        for (final item in allLocalTimeLogs) {
          if (item.teamUuid == teamUuid && !item.isDeleted) {
            item.isDeleted = true;
            item.version += 1;
            item.updatedAt = cleanupTime;
          }
        }
        for (final item in allLocalFixedSchedules) {
          if (item.teamUuid == teamUuid && !item.isDeleted) {
            item.isDeleted = true;
            item.version += 1;
            item.updatedAt = cleanupTime;
          }
        }
      }

      var inFlightTodoMutationUuids = <String>{};
      if (response['success'] == true) {
        // 仅标记“未冲突”的本地操作为已同步。阻塞冲突对应的 oplog 必须保留，
        // 否则本地完成/取消完成会被服务端旧状态覆盖后失去再次上传机会。
        final List<dynamic> rawConflicts =
            (response['conflicts'] as List?) ?? [];
        final Set<String> blockingConflictUuids = <String>{};
        for (final c in rawConflicts) {
          if (c is! Map) continue;
          final type = c['type']?.toString();
          if (type == 'schedule_conflict' || type == 'pomodoro') {
            continue;
          }
          final item = c['item'];
          if (item is! Map) continue;
          final uuid =
              (item['uuid'] ?? item['id'] ?? item['todo_uuid'])?.toString();
          if (uuid != null && uuid.isNotEmpty) {
            blockingConflictUuids.add(uuid);
          }
        }

        final oplogResolution = SyncOplogPolicy.resolveRequestSnapshot(
          requestSnapshot: requestOplogSnapshot,
          blockingConflictUuids: blockingConflictUuids,
          acknowledgeFixedScheduleOps: acknowledgeFixedScheduleOps,
          acknowledgeHabitOps: acknowledgeHabitOps,
        );
        await _updateOplogRowsByIds(
          db,
          oplogResolution.acknowledgedIds,
          {'is_synced': 1, 'sync_error': ''},
        );
        await _updateOplogRowsByIds(
          db,
          oplogResolution.blockedIds,
          {'is_synced': 0, 'sync_error': 'server_conflict'},
        );

        // 重新读取当前待同步日志。本次请求发出后新增的操作
        // 没有上传，不能被本次响应确认，也不能被旧的服务端快照覆盖。
        final currentPendingRows = await db.query(
          'op_logs',
          where: 'is_synced = 0',
          orderBy: 'timestamp ASC',
        );
        final currentPendingEntries = currentPendingRows
            .map(SyncOplogEntry.fromRow)
            .whereType<SyncOplogEntry>()
            .toList(growable: false);
        _pendingSyncOplogUuids =
            SyncOplogPolicy.todoUuids(currentPendingEntries);
        inFlightTodoMutationUuids =
            SyncOplogPolicy.todoUuidsCreatedAfterSnapshot(
          requestSnapshot: requestOplogSnapshot,
          currentPending: currentPendingEntries,
        );
        if (inFlightTodoMutationUuids.isNotEmpty) {
          // allLocalTodos 是请求发出前的快照。用当前 SQLite 值回基
          // 请求期间被修改的待办，使后续合并和全量落库都保留最新用户意图。
          final latestRows = await DatabaseHelper.instance.getTodoMaps(
            includeDeleted: true,
            uuids: inFlightTodoMutationUuids.toList(),
            includeConflictData: true,
          );
          final latestById = <String, TodoItem>{
            for (final row in latestRows)
              row['uuid'].toString(): TodoItem.fromJson(row),
          };
          for (var i = 0; i < allLocalTodos.length; i++) {
            final latest = latestById[allLocalTodos[i].id];
            if (latest != null) allLocalTodos[i] = latest;
          }
        }

        // 🚀 处理独立待办完成情况
        final List<dynamic>? indCompletions =
            response['independent_completions'];
        //debugPrint(
        //    '🧪 [SyncDiag][IndepCompletion] indCompletions=${indCompletions?.length ?? "null"}');
        if (indCompletions != null) {
          final batch = db.batch();
          var independentCompletionChanged = false;
          for (var ic in indCompletions) {
            if (ic is! Map) continue;
            final todoUuid = ic['todo_uuid']?.toString();
            if (todoUuid == null || todoUuid.isEmpty) continue;
            if (SyncOplogPolicy.shouldProtectTodoMerge(
              todoUuid,
              forceFlushUuids: _forceFlushProtectedUuids,
              inFlightMutationUuids: inFlightTodoMutationUuids,
            )) {
              continue;
            }
            final rawCompleted = ic['is_completed'];
            final isCompleted = rawCompleted == 1 ||
                rawCompleted == true ||
                rawCompleted?.toString() == '1' ||
                rawCompleted?.toString().toLowerCase() == 'true';
            final serverUpdatedAt =
                int.tryParse(ic['updated_at']?.toString() ?? '') ?? 0;
            final existing = await db.query(
              'todo_completions',
              where: 'todo_uuid = ? AND user_id = ?',
              whereArgs: [todoUuid, userId],
              limit: 1,
            );
            final localUpdatedAt = existing.isNotEmpty
                ? (existing.first['updated_at'] as num?)?.toInt() ?? 0
                : 0;
            // 🚀 时间戳比较修复：如果本地没有完成状态记录，判定为从未修改（localUpdatedAt=0），此时应接受服务端更新
            // 仅当本地有明确的更新时间且晚于服务端时，才跳过 DB 写入
            final hasLocalModification = localUpdatedAt > 0;
            if (hasLocalModification &&
                serverUpdatedAt > 0 &&
                serverUpdatedAt < localUpdatedAt) {
              // 本地有更新且晚于服务端，跳过 DB 写入，但仍需从 DB 读取正确值更新内存
              final localIsCompleted = existing.isNotEmpty
                  ? (existing.first['is_completed'] as int?) ?? 0
                  : 0;
              final localIdx =
                  allLocalTodos.indexWhere((todo) => todo.id == todoUuid);
              if (localIdx != -1 && allLocalTodos[localIdx].collabType == 1) {
                if (allLocalTodos[localIdx].isDone != (localIsCompleted == 1)) {
                  allLocalTodos[localIdx].isDone = localIsCompleted == 1;
                  independentCompletionChanged = true;
                  if (!allLocalTodos[localIdx].isDeleted) {
                    updatedTodoIds.add(todoUuid);
                  }
                }
              }
              //debugPrint(
              //    '🧪 [SyncDiag][IndepCompletion] SKIP_DB $todoUuid (server $serverUpdatedAt < local $localUpdatedAt), memory isDone=${localIsCompleted == 1}');
              continue;
            }
            //debugPrint(
            //    '🧪 [SyncDiag][IndepCompletion] WRITE $todoUuid isCompleted=$isCompleted (raw=$rawCompleted)');
            batch.insert(
                'todo_completions',
                {
                  'todo_uuid': todoUuid,
                  'user_id': userId,
                  'is_completed': isCompleted ? 1 : 0,
                  'updated_at': serverUpdatedAt > 0
                      ? serverUpdatedAt
                      : DateTime.now().millisecondsSinceEpoch,
                },
                conflictAlgorithm: ConflictAlgorithm.replace);
            final localIdx =
                allLocalTodos.indexWhere((todo) => todo.id == todoUuid);
            if (localIdx != -1 && allLocalTodos[localIdx].collabType == 1) {
              if (allLocalTodos[localIdx].isDone != isCompleted) {
                allLocalTodos[localIdx].isDone = isCompleted;
                independentCompletionChanged = true;
                if (!allLocalTodos[localIdx].isDeleted) {
                  updatedTodoIds.add(todoUuid);
                }
              }
            }
          }
          await batch.commit(noResult: true);
          if (independentCompletionChanged) {
            hasChanges = true;
          }
        }

        // 🚀 核心修复：清理本地孤立的团队数据 (处理离线被移出团队的情况)
        if (joinedTeamUuids != null) {
          // 获取本地所有存在的 team_uuid (联合查询：待办、倒计时、文件夹)
          final localTeamRows = await db.rawQuery('''
            SELECT DISTINCT team_uuid FROM todos
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM countdowns
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM todo_groups
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM time_logs
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM courses
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
            UNION
            SELECT DISTINCT team_uuid FROM fixed_schedules
            WHERE team_uuid IS NOT NULL AND TRIM(team_uuid) != '' AND is_deleted = 0
          ''');
          bool teamChanged = false;
          for (var row in localTeamRows) {
            String? tUuid = row['team_uuid']?.toString();
            if (tUuid != null && !currentTeams.contains(tUuid)) {
              debugPrint("🧹 发现孤立团队数据: $tUuid, 正在清理...");
              await clearTeamItems(tUuid);
              markLoadedTeamItemsDeleted(tUuid);
              hasChanges = true;
              teamChanged = true;
            }
          }

          // 🚀 核心优化：如果发现同步返回的团队列表与本地认知不符，或者刚刚清理了孤立团队，则提示 WS 重新订阅新频道
          if (teamChanged || currentTeams.length != localTeamRows.length) {
            debugPrint("👥 [协同] 团队列表发生变化，请求 WebSocket 刷新订阅...");
            // 利用 resumeSync 内部的逻辑可以触发重连与重新订阅
            Future.microtask(() => PomodoroSyncService.instance.resumeSync());
          }
        }
      } else {
        final errorMsg = response['message']?.toString() ?? '同步失败';

        // 🚀 记录同步失败的原因，方便用户查看
        await db.update('op_logs', {'sync_error': errorMsg},
            where: 'is_synced = 0');
        throw Exception(errorMsg);
      }

      // 解析服务器返回的实时冲突
      if (response['conflicts'] is List) {
        conflicts = (response['conflicts'] as List)
            .map((c) => ConflictInfo.fromJson(c as Map<String, dynamic>))
            .toList();
      }

      // 🛡️ 屏幕时间逻辑优化：上传成功后，务必清理“待上传”缓存
      if (screenPayload != null) {
        await prefs.remove(_scopedKey(keyLocalScreenTime, username));
        debugPrint("✅ 本机屏幕时间上传成功，已清理待上传缓存");
      }

      // 6. 🛡️ 数据合并逻辑 (LWW - Last Write Wins) — O(1) HashMap lookup

      // 🚀 核心修复：获取本地忽略表，防止”僵尸数据”复活
      final ignoredRows = await db.query('ignored_remote_items');
      final Set<String> ignoredUuids =
          ignoredRows.map((e) => e['uuid'].toString()).toSet();

      // 合并 Todos。旧版服务端没有持久化 recurrence_series_id；先利用本地
      // 已知关系或唯一、可验证的循环轨迹修复，再进入常规 LWW 合并。
      List<dynamic> serverTodos = response['server_todos'] ?? [];
      final remoteTodoEntries = <({Map<String, dynamic> raw, TodoItem item})>[];
      for (final raw in serverTodos) {
        final serverRaw =
            raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
        final sanitizedServerRaw = _stripClientOnlyConflictForSync(serverRaw);
        remoteTodoEntries.add((
          raw: serverRaw,
          item: TodoItem.fromJson(sanitizedServerRaw),
        ));
      }
      final repairedRemoteTodoIds = _repairMissingRemoteRecurrenceSeriesIds(
        remoteTodoEntries.map((entry) => entry.item).toList(),
        allLocalTodos,
      );

      // Snapshot items with conflicts before merge, to detect resolutions after merge
      final Set<String> preMergeConflictIds =
          allLocalTodos.where((t) => t.hasConflict).map((t) => t.id).toSet();

      final Map<String, int> todosIndexMap = {
        for (var i = 0; i < allLocalTodos.length; i++) allLocalTodos[i].id: i
      };
      for (final entry in remoteTodoEntries) {
        final serverRaw = entry.raw;
        final sItem = entry.item;
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] UUID: ${sItem.id} 已在本地忽略列表中');
          continue;
        }
        // 🚀 核心防御：非所属团队的数据处理（防止退出/被踢后数据回流）
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
          continue;
        }
        final serverDeviceId = serverRaw['device_id']?.toString();
        final bool isUpdatedByOtherDevice = serverDeviceId != null &&
            serverDeviceId.isNotEmpty &&
            serverDeviceId != deviceId;
        if (todosIndexMap.containsKey(sItem.id)) {
          final idx = todosIndexMap[sItem.id]!;
          final local = allLocalTodos[idx];
          final usesStrictRecurringLww =
              _isRecurringTodoForLww(local) || _isRecurringTodoForLww(sItem);
          final serverWinsStrictRecurringLww =
              TodoLwwService.shouldReplaceRecurringSnapshot(
            incomingUpdatedAt: sItem.updatedAt,
            incomingVersion: sItem.version,
            currentUpdatedAt: local.updatedAt,
            currentVersion: local.version,
            incomingHasConflict: sItem.hasConflict,
          );

          // 请求前强制落库或请求期间新增的本地修改均跳过本次
          // merge，防止用请求发出前的旧内存/服务端快照覆盖用户意图。
          if (SyncOplogPolicy.shouldProtectTodoMerge(
            sItem.id,
            forceFlushUuids: _forceFlushProtectedUuids,
            inFlightMutationUuids: inFlightTodoMutationUuids,
          )) {
            debugPrint(
                '🛡️ [merge] SKIP UUID=${sItem.id} (local mutation protected)');
            continue;
          }

          debugPrint(
              '🔄 [合并对比] UUID: ${sItem.id}, Server(V:${sItem.version}, D:${sItem.isDeleted}), Local(V:${local.version}, D:${local.isDeleted})');

          // 防回滚：本地已删除且更”新”时，拒绝服务端旧的未删除数据复活
          if (local.isDeleted &&
              !sItem.isDeleted &&
              local.updatedAt > sItem.updatedAt &&
              local.version >= sItem.version) {
            continue;
          }

          // 🚀 核心防护：本地已删除的团队待办，拒绝服务端未删除版本复活
          // 团队解散后，服务端可能因时序问题返回旧的未删除版本
          if (local.isDeleted &&
              !sItem.isDeleted &&
              local.teamUuid != null &&
              local.teamUuid!.isNotEmpty &&
              sItem.version <= local.version &&
              (!usesStrictRecurringLww || !serverWinsStrictRecurringLww)) {
            debugPrint(
                '🛡️ [防复活] UUID: ${sItem.id} 本地已删除(V:${local.version})，服务端未删除(V:${sItem.version})，拒绝复活');
            continue;
          }
          // 🚀 补充防护：已解散团队的已删除待办，无条件拒绝未删除版本复活
          // 通过 currentTeams 判断团队是否已解散（兼容 joinedTeamUuids 为 null 的情况）
          if (local.isDeleted &&
              !sItem.isDeleted &&
              local.teamUuid != null &&
              local.teamUuid!.isNotEmpty &&
              currentTeams.isNotEmpty &&
              !currentTeams.contains(local.teamUuid)) {
            debugPrint(
                '🛡️ [防复活-强拦截] UUID: ${sItem.id} 团队 ${local.teamUuid} 已解散(currentTeams=$currentTeams)，拒绝未删除版本复活');
            continue;
          }

          final mergeVersionCond = sItem.version > local.version;
          final mergeTimeCond =
              sItem.updatedAt > local.updatedAt && !sItem.hasConflict;
          if (sItem.hasConflict || local.hasConflict) {
            debugPrint(
                '🩺 [合并决策] UUID=${sItem.id} sV=${sItem.version} lV=${local.version} sU=${sItem.updatedAt} lU=${local.updatedAt} sConflict=${sItem.hasConflict} lConflict=${local.hasConflict} versionCond=$mergeVersionCond timeCond=$mergeTimeCond isDeleted=${sItem.isDeleted}');
          }
          final shouldReplaceTodo = usesStrictRecurringLww
              ? serverWinsStrictRecurringLww
              : sItem.isDeleted || mergeVersionCond || mergeTimeCond;
          if (shouldReplaceTodo) {
            _preserveLocalTodoSourceFields(local, sItem);
            allLocalTodos[idx] = sItem;
            if (!sItem.isDeleted && isUpdatedByOtherDevice) {
              updatedTodoIds.add(sItem.id);
            }
            hasChanges = true;
          } else if (sItem.groupId != local.groupId &&
              (usesStrictRecurringLww
                  ? serverWinsStrictRecurringLww
                  : sItem.updatedAt >= local.updatedAt)) {
            // Only accept group_id changes if server item is at least as new
            // as local item, preserving LWW semantics for folder assignments.
            allLocalTodos[idx].groupId = sItem.groupId;
            hasChanges = true;
          }

          // Handle conflict flag divergence separately from content merge.
          // Prevents overwriting a local resolution while still syncing conflict state.
          if (!sItem.isDeleted && todosIndexMap.containsKey(sItem.id)) {
            final idx2 = todosIndexMap[sItem.id]!;
            final localItem = allLocalTodos[idx2];
            // 服务端 isDataDifferent 已排除 collabType=1 的纯完成状态变化，
            // 若服务端标记了冲突，说明确有内容差异，客户端应尊重该标记。
            if (sItem.hasConflict && !localItem.hasConflict) {
              if (isRecentlyResolved(localItem.id)) {
                debugPrint(
                    '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved todo: ${localItem.id}');
              } else {
                // Server still has conflict but local was resolved — sync conflict metadata only
                localItem.hasConflict = true;
                localItem.serverVersionData = sItem.serverVersionData;
                hasChanges = true;
              }
            } else if (!sItem.hasConflict && localItem.hasConflict) {
              // Server cleared conflict (resolved from another device) — accept cleared state
              localItem.hasConflict = false;
              localItem.serverVersionData = null;
              recentlyResolvedUuids.remove(sItem.id);
              recentlyResolvedTimes.remove(sItem.id);
              hasChanges = true;
            }
          }
        } else {
          if (!sItem.isDeleted) {
            todosIndexMap[sItem.id] = allLocalTodos.length;
            allLocalTodos.add(sItem);
            if (isUpdatedByOtherDevice) {
              updatedTodoIds.add(sItem.id);
            }
            hasChanges = true;
          }
        }
      }

      // 合并 TodoGroups
      List<dynamic> serverGroups = response['server_todo_groups'] ?? [];
      final Map<String, int> groupsIndexMap = {
        for (var i = 0; i < allLocalGroups.length; i++) allLocalGroups[i].id: i
      };
      for (var raw in serverGroups) {
        TodoGroup sItem = TodoGroup.fromJson(raw);
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] 文件夹 UUID: ${sItem.id} 已忽略');
          continue;
        }
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] 文件夹 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
          continue;
        }
        if (groupsIndexMap.containsKey(sItem.id)) {
          final idx = groupsIndexMap[sItem.id]!;
          final localGroupForGuard = allLocalGroups[idx];
          // 🚀 核心防护：本地已删除的团队文件夹，拒绝服务端未删除版本复活
          if (localGroupForGuard.isDeleted &&
              !sItem.isDeleted &&
              localGroupForGuard.teamUuid != null &&
              localGroupForGuard.teamUuid!.isNotEmpty &&
              sItem.version <= localGroupForGuard.version) {
            debugPrint('🛡️ [防复活] 文件夹 UUID: ${sItem.id} 本地已删除，拒绝复活');
            continue;
          }
          // 🚀 补充防护：已解散团队的已删除文件夹，无条件拒绝未删除版本复活
          if (localGroupForGuard.isDeleted &&
              !sItem.isDeleted &&
              localGroupForGuard.teamUuid != null &&
              localGroupForGuard.teamUuid!.isNotEmpty &&
              currentTeams.isNotEmpty &&
              !currentTeams.contains(localGroupForGuard.teamUuid)) {
            debugPrint('🛡️ [防复活-强拦截] 文件夹 UUID: ${sItem.id} 团队已解散，拒绝未删除版本复活');
            continue;
          }
          if (sItem.isDeleted ||
              sItem.version > allLocalGroups[idx].version ||
              sItem.updatedAt > allLocalGroups[idx].updatedAt) {
            allLocalGroups[idx] = sItem;
            hasChanges = true;
          }

          // Handle conflict flag divergence separately from content merge.
          if (!sItem.isDeleted) {
            final localGroup = allLocalGroups[idx];
            if (sItem.hasConflict && !localGroup.hasConflict) {
              if (isRecentlyResolved(localGroup.id)) {
                debugPrint(
                    '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved group: ${localGroup.id}');
              } else {
                localGroup.hasConflict = true;
                localGroup.conflictData = sItem.conflictData;
                hasChanges = true;
              }
            } else if (!sItem.hasConflict && localGroup.hasConflict) {
              localGroup.hasConflict = false;
              localGroup.conflictData = null;
              recentlyResolvedUuids.remove(sItem.id);
              recentlyResolvedTimes.remove(sItem.id);
              hasChanges = true;
            }
          }
        } else {
          if (!sItem.isDeleted) {
            groupsIndexMap[sItem.id] = allLocalGroups.length;
            allLocalGroups.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 Countdowns
      List<dynamic> serverCountdowns = response['server_countdowns'] ?? [];
      final Map<String, int> countdownsIndexMap = {
        for (var i = 0; i < allLocalCountdowns.length; i++)
          allLocalCountdowns[i].id: i
      };
      for (var raw in serverCountdowns) {
        CountdownItem sItem = CountdownItem.fromJson(raw);
        if (ignoredUuids.contains(sItem.id)) {
          debugPrint('🚫 [合并跳过] 倒计时 UUID: ${sItem.id} 已忽略');
          continue;
        }
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] 倒计时 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
          continue;
        }
        if (countdownsIndexMap.containsKey(sItem.id)) {
          final idx = countdownsIndexMap[sItem.id]!;
          final localCountdownForGuard = allLocalCountdowns[idx];
          // 🚀 核心防护：本地已删除的团队倒计时，拒绝服务端未删除版本复活
          if (localCountdownForGuard.isDeleted &&
              !sItem.isDeleted &&
              localCountdownForGuard.teamUuid != null &&
              localCountdownForGuard.teamUuid!.isNotEmpty &&
              sItem.version <= localCountdownForGuard.version) {
            debugPrint('🛡️ [防复活] 倒计时 UUID: ${sItem.id} 本地已删除，拒绝复活');
            continue;
          }
          // 🚀 补充防护：已解散团队的已删除倒计时，无条件拒绝未删除版本复活
          if (localCountdownForGuard.isDeleted &&
              !sItem.isDeleted &&
              localCountdownForGuard.teamUuid != null &&
              localCountdownForGuard.teamUuid!.isNotEmpty &&
              currentTeams.isNotEmpty &&
              !currentTeams.contains(localCountdownForGuard.teamUuid)) {
            debugPrint('🛡️ [防复活-强拦截] 倒计时 UUID: ${sItem.id} 团队已解散，拒绝未删除版本复活');
            continue;
          }
          if (sItem.isDeleted ||
              sItem.version > allLocalCountdowns[idx].version ||
              (sItem.updatedAt > allLocalCountdowns[idx].updatedAt &&
                  !sItem.hasConflict)) {
            allLocalCountdowns[idx] = sItem;
            hasChanges = true;
          }

          // Handle conflict flag divergence separately from content merge.
          if (!sItem.isDeleted) {
            final localCountdown = allLocalCountdowns[idx];
            if (sItem.hasConflict && !localCountdown.hasConflict) {
              if (isRecentlyResolved(localCountdown.id)) {
                debugPrint(
                    '⏭️ [MemoryShield] Skipping conflict resurrection for recently resolved countdown: ${localCountdown.id}');
              } else {
                localCountdown.hasConflict = true;
                localCountdown.conflictData = sItem.conflictData;
                hasChanges = true;
              }
            } else if (!sItem.hasConflict && localCountdown.hasConflict) {
              localCountdown.hasConflict = false;
              localCountdown.conflictData = null;
              recentlyResolvedUuids.remove(sItem.id);
              recentlyResolvedTimes.remove(sItem.id);
              hasChanges = true;
            }
          }
        } else {
          if (!sItem.isDeleted) {
            countdownsIndexMap[sItem.id] = allLocalCountdowns.length;
            allLocalCountdowns.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 TimeLogs
      List<dynamic> serverTimeLogs = response['server_time_logs'] ?? [];
      final Map<String, int> timeLogsIndexMap = {
        for (var i = 0; i < allLocalTimeLogs.length; i++)
          allLocalTimeLogs[i].id: i
      };
      for (var raw in serverTimeLogs) {
        TimeLogItem sItem = TimeLogItem.fromJson(raw);
        if (isOutsideJoinedTeam(sItem.teamUuid)) {
          debugPrint(
              '🚫 [合并跳过] 时间日志 UUID: ${sItem.id} 团队 ${sItem.teamUuid} 已不在当前团队列表中');
          continue;
        }
        if (timeLogsIndexMap.containsKey(sItem.id)) {
          final idx = timeLogsIndexMap[sItem.id]!;
          if (sItem.isDeleted ||
              sItem.version > allLocalTimeLogs[idx].version ||
              sItem.updatedAt > allLocalTimeLogs[idx].updatedAt) {
            allLocalTimeLogs[idx] = sItem;
            hasChanges = true;
          }
        } else {
          if (!sItem.isDeleted) {
            timeLogsIndexMap[sItem.id] = allLocalTimeLogs.length;
            allLocalTimeLogs.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并 TodoPlanBlocks
      if (syncPlanBlocks) {
        List<dynamic> serverPlanBlocks = response['server_plan_blocks'] ?? [];
        final Map<String, int> planBlocksIndexMap = {
          for (var i = 0; i < allLocalPlanBlocks.length; i++)
            allLocalPlanBlocks[i].id: i
        };
        for (var raw in serverPlanBlocks) {
          TodoPlanBlock sItem =
              TodoPlanBlock.fromJson((raw as Map).cast<String, dynamic>());
          if (ignoredUuids.contains(sItem.id)) {
            debugPrint('🚫 [合并跳过] 规划块 UUID: ${sItem.id} 已忽略');
            continue;
          }
          if (planBlocksIndexMap.containsKey(sItem.id)) {
            final idx = planBlocksIndexMap[sItem.id]!;
            final local = allLocalPlanBlocks[idx];
            if (sItem.isDeleted ||
                sItem.version > local.version ||
                sItem.updatedAt > local.updatedAt) {
              allLocalPlanBlocks[idx] = sItem;
              hasChanges = true;
            }
          } else if (!sItem.isDeleted) {
            planBlocksIndexMap[sItem.id] = allLocalPlanBlocks.length;
            allLocalPlanBlocks.add(sItem);
            hasChanges = true;
          }
        }
      }

      // 合并通用固定日程。只在服务端显式声明 v1 能力时读取，
      // 避免旧服务端的空字段被误解为“云端已全部删除”。
      if (syncFixedSchedules && fixedSchedulesSupported) {
        final serverFixedSchedules =
            (response['server_fixed_schedules'] as List?) ?? const [];
        final fixedSchedulesIndexMap = <String, int>{
          for (var i = 0; i < allLocalFixedSchedules.length; i++)
            allLocalFixedSchedules[i].id: i,
        };
        for (final raw in serverFixedSchedules) {
          if (raw is! Map) continue;
          final serverItem = FixedScheduleItem.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (ignoredUuids.contains(serverItem.id) ||
              isOutsideJoinedTeam(serverItem.teamUuid)) {
            continue;
          }
          final localIndex = fixedSchedulesIndexMap[serverItem.id];
          if (localIndex == null) {
            if (!serverItem.isDeleted) {
              fixedSchedulesIndexMap[serverItem.id] =
                  allLocalFixedSchedules.length;
              allLocalFixedSchedules.add(serverItem);
              hasChanges = true;
            }
            continue;
          }
          final localItem = allLocalFixedSchedules[localIndex];
          if (TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: serverItem.updatedAt,
            incomingVersion: serverItem.version,
            currentUpdatedAt: localItem.updatedAt,
            currentVersion: localItem.version,
          )) {
            allLocalFixedSchedules[localIndex] = serverItem;
            hasChanges = true;
          }
        }
      }

      // 合并习惯数据。只在服务端显式声明 habits v1 能力时读取，
      // 避免旧服务端的空字段被误解为“云端已全部删除”。
      if (syncHabits && habitsSupported) {
        final serverHabitGoals =
            (response['server_habit_goals'] as List?) ?? const [];
        final habitGoalsIndexMap = <String, int>{
          for (var i = 0; i < allLocalHabitGoals.length; i++)
            allLocalHabitGoals[i].uuid: i,
        };
        for (final raw in serverHabitGoals) {
          if (raw is! Map) continue;
          final serverItem = HabitGoal.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (ignoredUuids.contains(serverItem.uuid)) continue;
          final localIndex = habitGoalsIndexMap[serverItem.uuid];
          if (localIndex == null) {
            if (!serverItem.isDeleted) {
              habitGoalsIndexMap[serverItem.uuid] = allLocalHabitGoals.length;
              allLocalHabitGoals.add(serverItem);
              hasChanges = true;
            }
            continue;
          }
          final localItem = allLocalHabitGoals[localIndex];
          // 冲突标记会推高服务端 updated_at；时间路径必须排除冲突项，
          // 避免用冲突快照覆盖本地更新的内容（与倒计时合并规则一致）。
          final serverWins = serverItem.version > localItem.version ||
              (serverItem.updatedAt > localItem.updatedAt &&
                  !serverItem.hasConflict);
          if (serverWins) {
            allLocalHabitGoals[localIndex] = serverItem;
            hasChanges = true;
          } else if (serverItem.hasConflict && !localItem.hasConflict) {
            // 服务端冲突标记与本地内容分开同步：不覆盖本地新内容，
            // 只让冲突状态保持一致，冲突收件箱可见。
            localItem.hasConflict = true;
            localItem.conflictData = serverItem.conflictData;
            hasChanges = true;
          } else if (!serverItem.hasConflict && localItem.hasConflict) {
            localItem.hasConflict = false;
            localItem.conflictData = null;
            hasChanges = true;
          }
        }

        final serverHabitRules =
            (response['server_habit_goal_rules'] as List?) ?? const [];
        final habitRulesIndexMap = <String, int>{
          for (var i = 0; i < allLocalHabitRules.length; i++)
            allLocalHabitRules[i].uuid: i,
        };
        for (final raw in serverHabitRules) {
          if (raw is! Map) continue;
          final serverItem = HabitGoalRuleRevision.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (ignoredUuids.contains(serverItem.uuid)) continue;
          final localIndex = habitRulesIndexMap[serverItem.uuid];
          if (localIndex == null) {
            if (!serverItem.isDeleted) {
              habitRulesIndexMap[serverItem.uuid] = allLocalHabitRules.length;
              allLocalHabitRules.add(serverItem);
              hasChanges = true;
            }
            continue;
          }
          final localItem = allLocalHabitRules[localIndex];
          // 与目标一致：冲突标记会推高服务端 updated_at，
          // 时间路径必须排除冲突项，避免冲突快照覆盖本地新内容。
          final serverWins = serverItem.version > localItem.version ||
              (serverItem.updatedAt > localItem.updatedAt &&
                  !serverItem.hasConflict);
          if (serverWins) {
            allLocalHabitRules[localIndex] = serverItem;
            hasChanges = true;
          } else if (serverItem.hasConflict && !localItem.hasConflict) {
            localItem.hasConflict = true;
            localItem.conflictData = serverItem.conflictData;
            hasChanges = true;
          } else if (!serverItem.hasConflict && localItem.hasConflict) {
            localItem.hasConflict = false;
            localItem.conflictData = null;
            hasChanges = true;
          }
        }

        // 打卡采用事件合并：不同 UUID 全部保留，同一 UUID 按 LWW 更新。
        final serverHabitCheckIns =
            (response['server_habit_checkins'] as List?) ?? const [];
        final habitCheckInsIndexMap = <String, int>{
          for (var i = 0; i < allLocalHabitCheckIns.length; i++)
            allLocalHabitCheckIns[i].uuid: i,
        };
        for (final raw in serverHabitCheckIns) {
          if (raw is! Map) continue;
          final serverItem = HabitCheckIn.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (ignoredUuids.contains(serverItem.uuid)) continue;
          final localIndex = habitCheckInsIndexMap[serverItem.uuid];
          if (localIndex == null) {
            if (!serverItem.isDeleted) {
              habitCheckInsIndexMap[serverItem.uuid] =
                  allLocalHabitCheckIns.length;
              allLocalHabitCheckIns.add(serverItem);
              hasChanges = true;
            }
            continue;
          }
          final localItem = allLocalHabitCheckIns[localIndex];
          if (TodoLwwService.isIncomingWinner(
            incomingUpdatedAt: serverItem.updatedAt,
            incomingVersion: serverItem.version,
            currentUpdatedAt: localItem.updatedAt,
            currentVersion: localItem.version,
          )) {
            allLocalHabitCheckIns[localIndex] = serverItem;
            hasChanges = true;
          }
        }
      }

      // 🚀 关键：将 conflicts 数组中的冲突也标记到本地数据上。
      // 服务器在标记 has_conflict=1 时可能不会同时更新 updated_at，
      // 导致该条目被 filterWithActualTime 过滤掉，不在 server_todos 中。
      // 这里从 conflicts 数组直接补标，确保 ConflictInboxScreen 能看到。
      final ignoredScheduleConflictKeys =
          await _getIgnoredScheduleConflictKeys(username);
      if (conflicts.isNotEmpty) {
        final conflictDetectionEnabled = await getConflictDetectionEnabled();
        for (final c in conflicts) {
          final itemId = (c.item['uuid'] ?? c.item['id'] ?? '').toString();
          if (itemId.isEmpty) continue;
          if (isRecentlyResolved(itemId)) {
            debugPrint(
                '⏭️ [MemoryShield] Skipping re-flag of recently resolved item in conflicts: $itemId');
            continue;
          }
          final serverVersion = c.conflictWith;
          if (c.type == 'schedule_conflict' &&
              todosIndexMap.containsKey(itemId)) {
            if (!conflictDetectionEnabled) continue;
            final todo = allLocalTodos[todosIndexMap[itemId]!];
            final peer = Map<String, dynamic>.from(serverVersion);
            if (_isSameRecurrenceSeriesPayload(todo, peer)) continue;
            final conflictKey = _scheduleConflictKeyFromPayload(todo, peer);
            if (conflictKey != null &&
                ignoredScheduleConflictKeys.contains(conflictKey)) {
              continue;
            }
            final data = {
              'uuid': todo.id,
              'id': todo.id,
              'content': todo.title,
              'team_uuid': todo.teamUuid,
              'schedule_scope':
                  (todo.teamUuid?.isNotEmpty ?? false) ? 'team' : 'personal',
              'relation_type': 'personal_personal',
              'conflict_kind': 'logic',
              'conflict_type': 'local_schedule_conflict',
              'source': 'server_detector',
              'start_time': todo.createdDate ?? todo.createdAt,
              'end_time': todo.dueDate?.millisecondsSinceEpoch,
              'conflict_with': [peer],
            };
            if (!todo.hasConflict ||
                jsonEncode(todo.serverVersionData) != jsonEncode(data)) {
              todo.hasConflict = true;
              todo.serverVersionData = data;
              hasChanges = true;
            }
            continue;
          }

          final serverVersionId =
              (serverVersion['uuid'] ?? serverVersion['id'] ?? '').toString();
          final bool isSameItemServerVersion = serverVersionId.isNotEmpty &&
              serverVersionId == itemId.toString();
          if (!isSameItemServerVersion) {
            debugPrint('⚠️ 跳过无可用云端快照的冲突标记: ${c.type} $itemId');
            continue;
          }

          if (todosIndexMap.containsKey(itemId)) {
            final todo = allLocalTodos[todosIndexMap[itemId]!];
            final serverConflictVer =
                (serverVersion['version'] as num?)?.toInt() ?? 0;
            // Skip if already resolved (hasConflict cleared) or version bumped above server
            if (!todo.hasConflict || todo.version > serverConflictVer) {
              debugPrint('⏭️ Skipping re-flag of resolved todo $itemId '
                  '(hasConflict=${todo.hasConflict}, localV=${todo.version}, serverV=$serverConflictVer)');
            } else {
              todo.hasConflict = true;
              todo.serverVersionData = serverVersion;
              hasChanges = true;
            }
          }
          if (countdownsIndexMap.containsKey(itemId)) {
            final countdown = allLocalCountdowns[countdownsIndexMap[itemId]!];
            final serverConflictVer =
                (serverVersion['version'] as num?)?.toInt() ?? 0;
            if (!countdown.hasConflict ||
                countdown.version > serverConflictVer) {
              // skip — already resolved
            } else {
              countdown.hasConflict = true;
              countdown.conflictData = serverVersion;
              hasChanges = true;
            }
          }
          if (groupsIndexMap.containsKey(itemId)) {
            final group = allLocalGroups[groupsIndexMap[itemId]!];
            final serverConflictVer =
                (serverVersion['version'] as num?)?.toInt() ?? 0;
            if (!group.hasConflict || group.version > serverConflictVer) {
              // skip — already resolved
            } else {
              group.hasConflict = true;
              group.conflictData = serverVersion;
              hasChanges = true;
            }
          }
          // TimeLogs don't have hasConflict field, skip
        }
      }

      // 合并 Pomodoro (Tags & Records)
      if (syncPomodoro) {
        try {
          // 顺序：拉取标签 -> 上传标签 -> 上传记录 -> 拉取记录
          await PomodoroService.syncTagsFromCloud();
          await PomodoroService.syncTagsToCloud();
          await PomodoroService.syncRecordsToCloud(
              forceFullSync: forceFullSync);
          bool pomodoroChanged = await PomodoroService.syncRecordsFromCloud(
              forceFullSync: forceFullSync);
          if (pomodoroChanged) hasChanges = true;
        } catch (pe) {
          debugPrint("Pomodoro sync error: $pe");
        }
      }

      // 7. 持久化数据
      // Compute IDs of items whose conflict was cleared in this sync cycle
      final Set<String> recentlyResolvedIds = preMergeConflictIds.where((id) {
        final idx = todosIndexMap[id];
        if (idx == null) return false;
        return !allLocalTodos[idx].hasConflict;
      }).toSet();
      final receivedRecurringTodos = remoteTodoEntries.any(
        (entry) => _isRecurringTodoForLww(entry.item),
      );
      final recurrenceDedupeChangedIds = <String>{};
      if (repairedRemoteTodoIds.isNotEmpty || receivedRecurringTodos) {
        if (_deduplicatePersistedRecurrenceOccurrences(
          allLocalTodos,
          changedIds: recurrenceDedupeChangedIds,
        )) {
          repairedRemoteTodoIds.addAll(recurrenceDedupeChangedIds);
          hasChanges = true;
        }
        // A sync-source save intentionally does not clear this cache. Remote
        // recurring snapshots are different: the just-downloaded tombstones
        // or occurrences can expose a series-day gap that must be repaired on
        // the next read instead of waiting until tomorrow.
        _recurrenceCheckCache.clear();
      }
      if (await getConflictDetectionEnabled()) {
        if (_recomputeLocalTodoScheduleConflicts(
          allLocalTodos,
          ignoredScheduleConflictKeys: ignoredScheduleConflictKeys,
          skipIds: recentlyResolvedIds,
        )) {
          hasChanges = true;
        }
      } else if (_clearLocalTodoScheduleConflicts(allLocalTodos)) {
        hasChanges = true;
      }

      if (hasChanges) {
        await saveTodos(username, allLocalTodos,
            sync: false, isSyncSource: true);
        await saveTodoGroups(username, allLocalGroups,
            sync: false, isSyncSource: true);
        await saveCountdowns(username, allLocalCountdowns,
            sync: false, isSyncSource: true);
        await saveTimeLogs(username, allLocalTimeLogs, sync: false);
        if (syncPlanBlocks) {
          await savePlanBlocks(username, allLocalPlanBlocks,
              sync: false, isSyncSource: true);
        }
        if (syncFixedSchedules && fixedSchedulesSupported) {
          await saveFixedSchedules(
            username,
            allLocalFixedSchedules,
            sync: false,
            isSyncSource: true,
          );
        }
        if (syncHabits && habitsSupported) {
          await HabitStorage.saveHabitGoals(
            allLocalHabitGoals,
            isSyncSource: true,
          );
          await HabitStorage.saveRuleRevisions(
            allLocalHabitRules,
            isSyncSource: true,
          );
          await HabitStorage.saveCheckIns(
            allLocalHabitCheckIns,
            isSyncSource: true,
          );
        }
        _pendingSyncOplogUuids.clear(); // 🚀 清除保护，防止跨同步周期的旧 UUID 干扰
        _forceFlushProtectedUuids.clear(); // 🚀 清除 force-flush 保护
      }

      // 将从旧云端响应中恢复出的系列关系作为一次真实本地修复重新上传。
      // 先完成同步源落库，再提升版本，确保 saveTodos 能生成待上传 oplog。
      if (repairedRemoteTodoIds.isNotEmpty) {
        final repairIdsToUpload = repairedRemoteTodoIds.where((id) =>
            recurrenceDedupeChangedIds.contains(id) ||
            !_attemptedRecurrenceSeriesRepairUploads.contains('$username|$id'));
        final repairedItems = allLocalTodos
            .where((todo) => repairIdsToUpload.contains(todo.id))
            .toList();
        for (final todo in repairedItems) {
          todo.markAsChanged();
        }
        if (repairedItems.isNotEmpty) {
          await saveTodos(
            username,
            repairedItems,
            sync: true,
            recomputeScheduleConflicts: false,
          );
          _attemptedRecurrenceSeriesRepairUploads.addAll(
            repairedItems.map((todo) => '$username|${todo.id}'),
          );
          hasChanges = true;
          debugPrint('🧩 [同步修复] 已恢复并排队回传 ${repairedItems.length} 个循环实例的系列关系');
        }
      }

      // 8. 更新同步水位线
      int newSyncTime =
          response['new_sync_time'] ?? DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt('last_sync_time_${serverKey}_$username', newSyncTime);
      if (syncFixedSchedules && fixedSchedulesSupported) {
        await prefs.setBool(fixedScheduleBootstrapKey, true);
      }
      if (syncHabits && habitsSupported) {
        await prefs.setBool(habitBootstrapKey, true);
      }

      // 如果屏幕时间同步成功，可以在这里刷新 UI 用的 Cache 数据（如果后端有返回最新的聚合数据）
      if (response['screen_time_results'] != null) {
        await saveScreenTimeCache(response['screen_time_results']);
      }

      // 9. 🚀 关键：如果数据发生了变动，触发全局刷新通知
      if (hasChanges) {
        triggerRefresh();
      }

      conflicts.removeWhere((conflict) {
        final itemId =
            (conflict.item['uuid'] ?? conflict.item['id'])?.toString();
        if (itemId == null || itemId.isEmpty) return false;
        TodoItem? local;
        for (final todo in allLocalTodos) {
          if (todo.id == itemId) {
            local = todo;
            break;
          }
        }
        return local != null && (local.isDeleted || !local.hasConflict);
      });

      // 10. 🛡️ 内存守卫：同步成功后，自动从锁定集合中清理掉在最新 conflicts 中不再包含的 ID
      final serverConflictIds = conflicts
          .map((c) => (c.item['uuid'] ?? c.item['id'] ?? '').toString())
          .toSet();
      recentlyResolvedUuids
          .removeWhere((id) => !serverConflictIds.contains(id));
      recentlyResolvedTimes
          .removeWhere((id, _) => !serverConflictIds.contains(id));
      if (recentlyResolvedUuids.isNotEmpty) {
        debugPrint(
            '🛡️ [MemoryShield] Remaining locked items in memory shield: $recentlyResolvedUuids');
      }

      return {
        'success': true,
        'hasChanges': hasChanges,
        'conflicts': conflicts,
        'updatedTodoIds': updatedTodoIds.toList(),
      };
    } catch (e) {
      debugPrint("syncData error: $e");
      return {'success': false, 'hasChanges': false, 'error': e.toString()};
    } finally {
      _isSyncing = false;
      // 🚀 无条件清除保护，防止跨越同步周期
      _pendingSyncOplogUuids.clear();
      _forceFlushProtectedUuids.clear();
    }
  }

  @visibleForTesting
  static bool recomputeLocalTodoScheduleConflictsForTest(
    List<TodoItem> todos,
  ) =>
      _recomputeLocalTodoScheduleConflicts(todos);

  static bool _recomputeLocalTodoScheduleConflicts(
    List<TodoItem> todos, {
    Set<String> ignoredScheduleConflictKeys = const <String>{},
    Set<String> skipIds = const <String>{},
    void Function(int current, int total, String message)? onProgress,
  }) {
    final buckets = <String, List<_TodoInterval>>{};
    final eligibleTodos = <TodoItem>[];

    for (final todo in todos) {
      final dueDate = todo.dueDate;
      final startMs = todo.createdDate ?? todo.createdAt;
      final endMs = dueDate?.millisecondsSinceEpoch ?? 0;

      if (todo.isDeleted || dueDate == null || todo.isDateOnly) {
        continue;
      }

      if (startMs <= 0 || endMs <= 0 || startMs >= endMs) continue;

      final startDay = _localDayKey(startMs);
      final endDay = _localDayKey(endMs);
      if (startDay != endDay) continue;
      eligibleTodos.add(todo);

      buckets.putIfAbsent(startDay, () => <_TodoInterval>[]).add(
            _TodoInterval(todo: todo, startMs: startMs, endMs: endMs),
          );
    }

    onProgress?.call(
      0,
      eligibleTodos.length,
      '正在分析 ${eligibleTodos.length} 条待办',
    );

    final conflictMap = <String, List<Map<String, dynamic>>>{};
    var processed = 0;
    for (final bucket in buckets.values) {
      bucket.sort((a, b) => a.startMs.compareTo(b.startMs));
      for (var i = 0; i < bucket.length; i++) {
        for (var j = i + 1; j < bucket.length; j++) {
          final a = bucket[i];
          final b = bucket[j];
          if (b.startMs >= a.endMs) break;
          if (a.startMs < b.endMs && b.startMs < a.endMs) {
            if (_isSameRecurrenceSeries(a.todo, b.todo)) continue;
            final conflictKey = _scheduleConflictPairKey(
              a.todo.id,
              a.startMs,
              a.endMs,
              b.todo.id,
              b.startMs,
              b.endMs,
            );
            if (ignoredScheduleConflictKeys.contains(conflictKey)) continue;
            conflictMap
                .putIfAbsent(a.todo.id, () => <Map<String, dynamic>>[])
                .add(_conflictPeerSummary(b));
            conflictMap
                .putIfAbsent(b.todo.id, () => <Map<String, dynamic>>[])
                .add(_conflictPeerSummary(a));
          }
        }
        processed++;
        onProgress?.call(
          processed,
          eligibleTodos.length,
          '正在扫描 ${bucket[i].todo.title}',
        );
      }
    }

    var changed = false;
    for (final todo in todos) {
      final existing = todo.serverVersionData;
      final isLocalScheduleConflict = _isLocalScheduleConflict(existing);
      if (todo.isDeleted) {
        if (isLocalScheduleConflict || todo.hasConflict) {
          todo.hasConflict = false;
          todo.serverVersionData = null;
          changed = true;
        }
        continue;
      }

      final peers = conflictMap[todo.id];

      // Skip re-flagging items whose conflict was just resolved in this sync cycle
      if (skipIds.contains(todo.id) && peers != null && peers.isNotEmpty) {
        continue;
      }

      if (peers != null && peers.isNotEmpty) {
        if (!_hasVersionConflict(existing)) {
          final bool isTeamTodo =
              todo.teamUuid != null && todo.teamUuid!.isNotEmpty;
          final relationType = _classifyScheduleRelation(
              todo, peers.cast<Map<String, dynamic>>());
          final data = {
            'uuid': todo.id,
            'id': todo.id,
            'content': todo.title,
            'team_uuid': todo.teamUuid,
            'schedule_scope': isTeamTodo ? 'team' : 'personal',
            'relation_type': relationType,
            'conflict_kind': 'logic',
            'conflict_type': 'local_schedule_conflict',
            'source': 'local_detector',
            'start_time': todo.createdDate ?? todo.createdAt,
            'end_time': todo.dueDate?.millisecondsSinceEpoch,
            'conflict_with': peers,
          };
          if (!todo.hasConflict || jsonEncode(existing) != jsonEncode(data)) {
            todo.hasConflict = true;
            todo.serverVersionData = data;
            changed = true;
          }
        } else if (!todo.hasConflict) {
          todo.hasConflict = true;
          changed = true;
        }
      } else if (isLocalScheduleConflict) {
        todo.hasConflict = false;
        todo.serverVersionData = null;
        changed = true;
      }
    }

    return changed;
  }

  static bool _clearLocalTodoScheduleConflicts(List<TodoItem> todos) {
    var changed = false;
    for (final todo in todos) {
      if (!_isLocalScheduleConflict(todo.serverVersionData)) continue;
      todo.hasConflict = false;
      todo.serverVersionData = null;
      changed = true;
    }
    return changed;
  }

  static String _scheduleConflictPairKey(
    String aId,
    int aStart,
    int aEnd,
    String bId,
    int bStart,
    int bEnd,
  ) {
    final left = '$aId@$aStart-$aEnd';
    final right = '$bId@$bStart-$bEnd';
    return left.compareTo(right) <= 0 ? '$left|$right' : '$right|$left';
  }

  static String? _scheduleConflictKeyFromPayload(
      TodoItem item, Map<String, dynamic> peer) {
    if (_isSameRecurrenceSeriesPayload(item, peer)) return null;
    final itemEnd = item.dueDate?.millisecondsSinceEpoch;
    final peerId = (peer['uuid'] ?? peer['id'] ?? '').toString();
    final peerStart = _parseMillis(peer['start_time'] ??
        peer['created_date'] ??
        peer['createdDate'] ??
        peer['created_at']);
    final peerEnd =
        _parseMillis(peer['end_time'] ?? peer['due_date'] ?? peer['dueDate']);
    if (itemEnd == null ||
        peerId.isEmpty ||
        peerStart == null ||
        peerEnd == null) {
      return null;
    }
    return _scheduleConflictPairKey(
      item.id,
      item.createdDate ?? item.createdAt,
      itemEnd,
      peerId,
      peerStart,
      peerEnd,
    );
  }

  static int? _parseMillis(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool _isSameRecurrenceSeries(TodoItem first, TodoItem second) {
    final firstSeries = first.recurrenceSeriesId;
    final secondSeries = second.recurrenceSeriesId;
    return firstSeries != null &&
        firstSeries.isNotEmpty &&
        secondSeries != null &&
        secondSeries.isNotEmpty &&
        firstSeries == secondSeries;
  }

  static bool _isRecurringTodoForLww(TodoItem todo) =>
      todo.recurrence != RecurrenceType.none ||
      (todo.recurrenceSeriesId?.trim().isNotEmpty ?? false);

  static bool _isSameRecurrenceSeriesPayload(
    TodoItem item,
    Map<String, dynamic> peer,
  ) {
    final itemSeries = item.recurrenceSeriesId;
    final peerSeries =
        (peer['recurrence_series_id'] ?? peer['recurrenceSeriesId'])
            ?.toString();
    return itemSeries != null &&
        itemSeries.isNotEmpty &&
        peerSeries != null &&
        peerSeries.isNotEmpty &&
        itemSeries == peerSeries;
  }

  static bool _hasVersionConflict(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    final type = data['conflict_type']?.toString();
    final kind = data['conflict_kind']?.toString();
    final source = data['source']?.toString();
    return type == 'version_conflict' ||
        kind == 'version' ||
        (type != 'local_schedule_conflict' && source != 'local_detector');
  }

  @visibleForTesting
  static List<TodoItem> clearResolvedRecurrenceMigrationConflictsForTest(
    List<TodoItem> todos,
  ) =>
      _clearResolvedRecurrenceMigrationConflicts(todos);

  /// 清理由 recurrence_series_id 迁移触发、但业务内容已经一致的版本冲突。
  /// 真正存在完成状态、时间或内容差异的冲突仍保留给用户处理。
  static List<TodoItem> _clearResolvedRecurrenceMigrationConflicts(
    List<TodoItem> todos,
  ) {
    final resolved = <TodoItem>[];
    for (final todo in todos) {
      if (!todo.hasConflict ||
          todo.recurrenceSeriesId?.isNotEmpty != true ||
          !_hasVersionConflict(todo.serverVersionData) ||
          _isLocalScheduleConflict(todo.serverVersionData)) {
        continue;
      }
      final server = todo.serverVersionData!;
      final serverUuid = (server['uuid'] ?? server['id'])?.toString();
      if (serverUuid != null &&
          serverUuid.isNotEmpty &&
          serverUuid != todo.id) {
        continue;
      }
      final serverSeriesId =
          (server['recurrence_series_id'] ?? server['recurrenceSeriesId'])
              ?.toString()
              .trim();
      if (serverSeriesId != null &&
          serverSeriesId.isNotEmpty &&
          serverSeriesId != todo.recurrenceSeriesId) {
        continue;
      }

      final local = todo.toJson();
      final fields = <String>[
        'content',
        if (todo.collabType == 0) 'is_completed',
        'is_deleted',
        'due_date',
        'created_date',
        'recurrence',
        'custom_interval_days',
        'recurrence_end_date',
        'remark',
        'group_id',
        'team_uuid',
        'category_id',
        'collab_type',
        'reminder_minutes',
        'is_all_day',
      ];
      if (_hasSubstantialChange(server, local, fields)) continue;

      todo.hasConflict = false;
      todo.serverVersionData = null;
      todo.markAsChanged();
      resolved.add(todo);
    }
    return resolved;
  }

  static bool _payloadHasConflict(Map<String, dynamic> data) {
    final raw = data['has_conflict'] ?? data['hasConflict'];
    return raw == 1 || raw == true || raw == '1' || raw == 'true';
  }

  static bool _payloadHasVersionConflict(Map<String, dynamic> data) {
    if (!_payloadHasConflict(data)) return false;
    final rawConflictData = data['conflict_data'] ??
        data['conflictData'] ??
        data['serverVersionData'];
    Map<String, dynamic>? conflictData;
    if (rawConflictData is String && rawConflictData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawConflictData);
        if (decoded is Map) {
          conflictData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        conflictData = null;
      }
    } else if (rawConflictData is Map) {
      conflictData = Map<String, dynamic>.from(rawConflictData);
    }
    return _hasVersionConflict(conflictData);
  }

  static bool _isLocalScheduleConflict(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    return data['conflict_type'] == 'local_schedule_conflict' ||
        data['source'] == 'local_detector';
  }

  static Map<String, dynamic> _stripClientOnlyConflictForSync(
      Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    final rawConflictData =
        result['conflict_data'] ?? result['serverVersionData'];
    Map<String, dynamic>? conflictData;
    if (rawConflictData is String && rawConflictData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawConflictData);
        if (decoded is Map) {
          conflictData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        conflictData = null;
      }
    } else if (rawConflictData is Map) {
      conflictData = Map<String, dynamic>.from(rawConflictData);
    }

    if (_isLocalScheduleConflict(conflictData)) {
      result['has_conflict'] = 0;
      result.remove('conflict_data');
      result.remove('serverVersionData');
    }
    return result;
  }

  static void _preserveLocalTodoSourceFields(
      TodoItem local, TodoItem incoming) {
    if (incoming.recurrenceSeriesId == null ||
        incoming.recurrenceSeriesId!.trim().isEmpty) {
      incoming.recurrenceSeriesId = local.recurrenceSeriesId;
    }
    if ((incoming.imagePath == null || incoming.imagePath!.isEmpty) &&
        local.imagePath != null &&
        local.imagePath!.isNotEmpty) {
      incoming.imagePath = local.imagePath;
    }
    if ((incoming.originalText == null || incoming.originalText!.isEmpty) &&
        local.originalText != null &&
        local.originalText!.isNotEmpty) {
      incoming.originalText = local.originalText;
    }
  }

  @visibleForTesting
  static Set<String> repairMissingRemoteRecurrenceSeriesIdsForTest(
    List<TodoItem> incoming,
    List<TodoItem> local,
  ) =>
      _repairMissingRemoteRecurrenceSeriesIds(incoming, local);

  /// 修复旧服务端丢失的循环系列 ID。
  ///
  /// 优先使用相同 UUID 的本地真值。新设备没有本地真值时，仅在同一计划签名
  /// 下恰好存在一个循环锚点，且实例日期确实符合该锚点的循环规则时才重建，
  /// 避免把同名但无关的待办误合并。
  static Set<String> _repairMissingRemoteRecurrenceSeriesIds(
    List<TodoItem> incoming,
    List<TodoItem> local,
  ) {
    final repairedIds = <String>{};
    final localById = {for (final todo in local) todo.id: todo};

    // 云端可能已被旧设备拆成非空的“子实例自建系列”。
    // 若该云端系列 ID 在本地明确是另一系列的成员，则本地
    // 稳定 UUID 关系比云端的错误非空值更可信。
    for (final todo in incoming) {
      final remoteSeriesId = todo.recurrenceSeriesId?.trim();
      final localSeriesId = localById[todo.id]?.recurrenceSeriesId?.trim();
      if (remoteSeriesId == null ||
          remoteSeriesId.isEmpty ||
          localSeriesId == null ||
          localSeriesId.isEmpty ||
          remoteSeriesId == localSeriesId) {
        continue;
      }
      final resolvedRemoteSeriesId =
          _resolveRecurrenceSeriesAlias(remoteSeriesId, localById);
      if (resolvedRemoteSeriesId == localSeriesId) {
        todo.recurrenceSeriesId = localSeriesId;
        repairedIds.add(todo.id);
      }
    }

    for (final todo in incoming) {
      if (!_isMissingRecurrenceSeriesId(todo)) continue;
      final localSeriesId = localById[todo.id]?.recurrenceSeriesId;
      if (localSeriesId != null && localSeriesId.trim().isNotEmpty) {
        todo.recurrenceSeriesId = localSeriesId;
        repairedIds.add(todo.id);
      }
    }

    // 增量响应可能只带当前锚点；把本机已经被旧同步拆散的实例也纳入候选，
    // 同 UUID 仍以本轮云端对象为准，避免产生两个活动锚点。
    final candidatesById = <String, TodoItem>{
      for (final todo in local) todo.id: todo,
      for (final todo in incoming) todo.id: todo,
    };
    final candidates = candidatesById.values.toList();

    final activeBySignature = <String, List<TodoItem>>{};
    for (final todo in candidates) {
      if (todo.isDeleted || todo.recurrence == RecurrenceType.none) continue;
      final signature = _remoteRecurrencePlanSignature(todo);
      if (signature == null) continue;
      activeBySignature.putIfAbsent(signature, () => []).add(todo);
    }

    for (final entry in activeBySignature.entries) {
      // 两个配置完全相同的活动循环无法从旧云端数据可靠区分。
      if (entry.value.length != 1) {
        for (final anchor in entry.value) {
          if (_isMissingRecurrenceSeriesId(anchor)) {
            anchor.recurrenceSeriesId = anchor.id;
            repairedIds.add(anchor.id);
          }
        }
        continue;
      }

      final anchor = entry.value.single;
      final matching = candidates.where((candidate) {
        if (candidate.isDeleted ||
            _remoteRecurrencePlanSignature(candidate) != entry.key) {
          return false;
        }
        final candidateSeriesId = candidate.recurrenceSeriesId;
        final anchorSeriesId = anchor.recurrenceSeriesId;
        if (candidateSeriesId != null &&
            candidateSeriesId.trim().isNotEmpty &&
            anchorSeriesId != null &&
            anchorSeriesId.trim().isNotEmpty &&
            candidateSeriesId != anchorSeriesId) {
          return false;
        }
        return _isRemoteOccurrenceOnRecurrence(anchor, candidate);
      }).toList()
        ..sort((a, b) => (a.createdDate ?? a.createdAt)
            .compareTo(b.createdDate ?? b.createdAt));

      final knownSeriesIds = matching
          .map((todo) => todo.recurrenceSeriesId?.trim())
          .whereType<String>()
          .where((seriesId) => seriesId.isNotEmpty)
          .toSet();
      if (knownSeriesIds.length > 1) continue;

      final seriesId = knownSeriesIds.isNotEmpty
          ? knownSeriesIds.first
          : (matching.isNotEmpty ? matching.first.id : anchor.id);
      for (final todo in matching.followedBy([anchor])) {
        if (!_isMissingRecurrenceSeriesId(todo)) continue;
        todo.recurrenceSeriesId = seriesId;
        repairedIds.add(todo.id);
      }
    }

    // 旧设备可能已经用“当时的活动实例 ID”建立了第二个系列。若该 ID
    // 本身如今明确属于另一个系列，则它只是旧链路留下的别名，统一指向
    // 当前的规范系列。这样编辑过时长的同日实例也能归队并由去重逻辑清理。
    for (var pass = 0; pass < 10; pass++) {
      var changed = false;
      for (final todo in candidates) {
        if (todo.isDeleted) continue;
        final seriesId = todo.recurrenceSeriesId;
        if (seriesId == null || seriesId.isEmpty) continue;
        final seriesAnchor = candidatesById[seriesId];
        final canonicalSeriesId = seriesAnchor?.recurrenceSeriesId;
        if (canonicalSeriesId == null ||
            canonicalSeriesId.isEmpty ||
            canonicalSeriesId == seriesId) {
          continue;
        }
        todo.recurrenceSeriesId = canonicalSeriesId;
        repairedIds.add(todo.id);
        changed = true;
      }
      if (!changed) break;
    }

    return repairedIds;
  }

  static String _resolveRecurrenceSeriesAlias(
    String seriesId,
    Map<String, TodoItem> todosById,
  ) {
    var current = seriesId;
    final visited = <String>{};
    while (visited.add(current)) {
      final next = todosById[current]?.recurrenceSeriesId?.trim();
      if (next == null || next.isEmpty || next == current) break;
      current = next;
    }
    return current;
  }

  @visibleForTesting
  static Set<String> repairLocalRecurrenceSeriesAliasesFromHistoryForTest(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  ) =>
      _repairLocalRecurrenceSeriesAliases(
        todos,
        historicalSeriesByTodoId,
      );

  /// 从本机 oplog 中恢复“某个子实例曾经属于哪个系列”。
  ///
  /// 只有当实例当前以自己 UUID 作为系列 ID，历史中只存在
  /// 一个不同的系列 ID，且旧归属记录不少于当前自立记录时才
  /// 建立别名。不依赖标题或时间猜测。
  static Future<Set<String>> _repairLocalRecurrenceSeriesAliasesFromHistory(
    Database db,
    List<TodoItem> todos,
  ) async {
    final relevantIds = todos
        .where((todo) => todo.recurrenceSeriesId?.isNotEmpty == true)
        .map((todo) => todo.id)
        .toList();
    if (relevantIds.isEmpty) return <String>{};

    final historicalSeriesByTodoId = <String, List<String>>{};
    const chunkSize = 300;
    for (var offset = 0; offset < relevantIds.length; offset += chunkSize) {
      final end = (offset + chunkSize < relevantIds.length)
          ? offset + chunkSize
          : relevantIds.length;
      final chunk = relevantIds.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'op_logs',
        columns: const ['target_uuid', 'data_json', 'timestamp'],
        where: 'target_table = ? AND target_uuid IN ($placeholders)',
        whereArgs: ['todos', ...chunk],
        orderBy: 'timestamp ASC',
      );
      for (final row in rows) {
        final targetUuid = row['target_uuid']?.toString();
        final rawData = row['data_json'];
        if (targetUuid == null || targetUuid.isEmpty || rawData == null) {
          continue;
        }
        try {
          final decoded = jsonDecode(rawData.toString());
          if (decoded is! Map) continue;
          final seriesId =
              (decoded['recurrence_series_id'] ?? decoded['recurrenceSeriesId'])
                  ?.toString()
                  .trim();
          if (seriesId == null || seriesId.isEmpty) continue;
          final history = historicalSeriesByTodoId.putIfAbsent(
            targetUuid,
            () => <String>[],
          );
          history.add(seriesId);
        } catch (_) {
          // 单条旧 oplog 损坏不应阻断整体同步。
        }
      }
    }
    return _repairLocalRecurrenceSeriesAliases(
      todos,
      historicalSeriesByTodoId,
    );
  }

  static Set<String> _repairLocalRecurrenceSeriesAliases(
    List<TodoItem> todos,
    Map<String, List<String>> historicalSeriesByTodoId,
  ) {
    final aliases = <String, String>{};
    for (final todo in todos) {
      final currentSeriesId = todo.recurrenceSeriesId?.trim();
      if (currentSeriesId == null ||
          currentSeriesId.isEmpty ||
          currentSeriesId != todo.id) {
        continue;
      }
      final history = (historicalSeriesByTodoId[todo.id] ?? const [])
          .map((seriesId) => seriesId.trim())
          .where((seriesId) => seriesId.isNotEmpty)
          .toList();
      final currentSeriesCount =
          history.where((seriesId) => seriesId == currentSeriesId).length;
      final previousSeriesCounts = <String, int>{};
      for (final seriesId in history) {
        if (seriesId == currentSeriesId) continue;
        previousSeriesCounts[seriesId] =
            (previousSeriesCounts[seriesId] ?? 0) + 1;
      }
      if (previousSeriesCounts.length == 1 &&
          previousSeriesCounts.values.single >= currentSeriesCount) {
        aliases[currentSeriesId] = previousSeriesCounts.keys.single;
      }
    }
    if (aliases.isEmpty) return <String>{};

    String resolve(String seriesId) {
      var current = seriesId;
      final visited = <String>{};
      while (visited.add(current)) {
        final next = aliases[current];
        if (next == null || next.isEmpty || next == current) break;
        current = next;
      }
      return current;
    }

    final repairedIds = <String>{};
    for (final todo in todos) {
      final currentSeriesId = todo.recurrenceSeriesId?.trim();
      if (currentSeriesId == null || currentSeriesId.isEmpty) continue;
      final canonicalSeriesId = resolve(currentSeriesId);
      if (canonicalSeriesId == currentSeriesId) continue;
      todo.recurrenceSeriesId = canonicalSeriesId;
      repairedIds.add(todo.id);
    }
    return repairedIds;
  }

  static bool _isMissingRecurrenceSeriesId(TodoItem todo) =>
      todo.recurrenceSeriesId == null ||
      todo.recurrenceSeriesId!.trim().isEmpty;

  static String? _remoteRecurrencePlanSignature(TodoItem todo) {
    final startMs = todo.createdDate;
    if (startMs == null || startMs <= 0) return null;
    final start =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
    final dueMs = todo.dueDate?.millisecondsSinceEpoch;
    final durationMs = dueMs == null ? null : dueMs - startMs;
    if (durationMs != null && durationMs < 0) return null;
    final recurrenceEnd = todo.recurrenceEndDate;
    final recurrenceEndKey = recurrenceEnd == null
        ? null
        : '${recurrenceEnd.year}-${recurrenceEnd.month}-${recurrenceEnd.day}';
    return jsonEncode([
      todo.title.trim(),
      todo.remark?.trim(),
      todo.groupId,
      todo.teamUuid,
      todo.categoryId,
      todo.collabType,
      todo.isAllDay,
      todo.reminderMinutes,
      todo.customIntervalDays,
      recurrenceEndKey,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      durationMs,
    ]);
  }

  static bool _isRemoteOccurrenceOnRecurrence(
    TodoItem ruleSource,
    TodoItem candidate,
  ) {
    final ruleStartMs = ruleSource.createdDate;
    final candidateStartMs = candidate.createdDate;
    if (ruleStartMs == null || candidateStartMs == null) return false;

    final ruleStart =
        DateTime.fromMillisecondsSinceEpoch(ruleStartMs, isUtc: true).toLocal();
    final candidateStart = DateTime.fromMillisecondsSinceEpoch(
      candidateStartMs,
      isUtc: true,
    ).toLocal();
    final ruleDay = DateTime(ruleStart.year, ruleStart.month, ruleStart.day);
    final candidateDay =
        DateTime(candidateStart.year, candidateStart.month, candidateStart.day);
    if (ruleSource.recurrence == RecurrenceType.weekdays &&
        (candidateDay.weekday == DateTime.saturday ||
            candidateDay.weekday == DateTime.sunday)) {
      return false;
    }
    final recurrenceEnd = ruleSource.recurrenceEndDate;
    if (recurrenceEnd != null) {
      final endDay = DateTime(
        recurrenceEnd.year,
        recurrenceEnd.month,
        recurrenceEnd.day,
      );
      if (candidateDay.isAfter(endDay)) return false;
    }
    if (candidateDay == ruleDay) return true;

    var cursor = candidateDay.isBefore(ruleDay) ? candidateStart : ruleStart;
    final target = candidateDay.isBefore(ruleDay) ? ruleDay : candidateDay;
    for (var i = 0; i < 500; i++) {
      final next = _nextRecurrenceDate(cursor, ruleSource);
      if (next == null || !next.isAfter(cursor)) return false;
      final nextDay = DateTime(next.year, next.month, next.day);
      if (nextDay == target) return true;
      if (nextDay.isAfter(target)) return false;
      cursor = next;
    }
    return false;
  }

  static Map<String, dynamic> _conflictPeerSummary(_TodoInterval interval) {
    return {
      'uuid': interval.todo.id,
      'id': interval.todo.id,
      'title': interval.todo.title,
      'content': interval.todo.title,
      'team_uuid': interval.todo.teamUuid,
      'recurrence_series_id': interval.todo.recurrenceSeriesId,
      'schedule_scope':
          (interval.todo.teamUuid != null && interval.todo.teamUuid!.isNotEmpty)
              ? 'team'
              : 'personal',
      'start_time': interval.startMs,
      'end_time': interval.endMs,
    };
  }

  static String _classifyScheduleRelation(
      TodoItem current, List<Map<String, dynamic>> peers) {
    final currentIsTeam =
        current.teamUuid != null && current.teamUuid!.isNotEmpty;
    final hasTeamPeer = peers.any((peer) {
      final teamUuid = peer['team_uuid']?.toString();
      return teamUuid != null && teamUuid.isNotEmpty;
    });
    final hasPersonalPeer = peers.any((peer) {
      final teamUuid = peer['team_uuid']?.toString();
      return teamUuid == null || teamUuid.isEmpty;
    });

    if ((currentIsTeam && hasPersonalPeer) || (!currentIsTeam && hasTeamPeer)) {
      return 'personal_team';
    }
    if (currentIsTeam) return 'team_team';
    return 'personal_personal';
  }

  static String _localDayKey(int ms) {
    return DateFormat('yyyy-MM-dd')
        .format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  static Future<bool> syncScreenTimeAlone(
      String username, String deviceName) async {
    final prefs = await SharedPreferences.getInstance();
    int? userId = prefs.getInt('current_user_id');
    if (userId == null) {
      debugPrint("syncScreenTimeAlone: user not logged in");
      return false;
    }

    try {
      final localPackage = await getLocalScreenTimeMap();
      final apps = localPackage['apps'] as List<dynamic>?;
      final date = localPackage['date'] as String?;

      if (apps == null || apps.isEmpty || date == null) {
        debugPrint("syncScreenTimeAlone: no data to upload");
        return false;
      }

      final formattedApps = apps
          .whereType<Map>()
          .map((e) => {
                'app_name': e['app_name']?.toString() ?? 'Unknown',
                'duration': (e['duration'] is int) ? e['duration'] : 0,
              })
          .toList();

      final success = await ApiService.uploadScreenTime(
        userId: userId,
        deviceName: deviceName,
        date: date,
        apps: formattedApps,
      );

      if (success) {
        await prefs.remove(_scopedKey(keyLocalScreenTime, username));
        return true;
      } else {
        debugPrint("syncScreenTimeAlone failed");
        return false;
      }
    } catch (e) {
      debugPrint("syncScreenTimeAlone error: $e");
      return false;
    }
  }

  // ==========================================
  // 偏好设置与状态管理
  // ==========================================
  static Future<void> saveAppSetting(String key, dynamic value) async {
    final prefs = await StorageService.prefs;
    String finalKey = key;

    // 🚀 全局设置例外列表 (不进行账户隔离的设置)
    const List<String> globalSettings = [
      keyThemeMode,
      keyServerChoice,
      keySystemStartupEnabled,
      keyDeviceId,
      'update_channel',
    ];

    if (!globalSettings.contains(key)) {
      final String? username = prefs.getString(keyCurrentUser);
      if (username != null && username.isNotEmpty) {
        finalKey = "${key}_$username";
      }
    }

    if (value is int) await prefs.setInt(finalKey, value);
    if (value is String) await prefs.setString(finalKey, value);
    if (value is bool) await prefs.setBool(finalKey, value);
    if (key == keyThemeMode) themeNotifier.value = value;
  }

  static Future<int> getSyncInterval() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username != null && username.isNotEmpty) {
      return prefs.getInt("${keySyncInterval}_$username") ??
          (prefs.getInt(keySyncInterval) ?? 0);
    }
    return prefs.getInt(keySyncInterval) ?? 0;
  }

  static Future<bool> getConflictDetectionEnabled() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username != null && username.isNotEmpty) {
      return prefs.getBool("${keyConflictDetectionEnabled}_$username") ??
          (prefs.getBool(keyConflictDetectionEnabled) ?? false);
    }
    return prefs.getBool(keyConflictDetectionEnabled) ?? false;
  }

  static Future<String> getThemeMode() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(keyThemeMode) ?? 'system';
  }

  static Future<void> setThemeColorMode(String mode) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keyThemeColorMode, mode);
    themeColorModeNotifier.value = mode;
  }

  static Future<void> setCustomThemeColor(Color color) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(keyCustomThemeColor, color.toARGB32());
    customThemeColorNotifier.value = color;
  }

  static void setAppWallpaperColor(Color? color) {
    appWallpaperColorNotifier.value = color;
  }

  static Future<void> saveServerChoice(String choice) async {
    final prefs = await StorageService.prefs;
    await prefs.setString(keyServerChoice, choice);
    ApiService.setServerChoice(choice);
  }

  static Future<String> getServerChoice() async {
    final prefs = await StorageService.prefs;
    return prefs.getString(keyServerChoice) ?? 'aliyun';
  }

  // ==========================================
  // 首页文字自定义配置
  // ==========================================
  static const String _keyHomeTextConfig = 'home_text_config';

  static Future<void> saveHomeTextConfig(Map<String, dynamic> config) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = username != null && username.isNotEmpty
        ? "${_keyHomeTextConfig}_$username"
        : _keyHomeTextConfig;
    await prefs.setString(key, jsonEncode(config));
  }

  static Future<Map<String, dynamic>> getHomeTextConfig() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final key = username != null && username.isNotEmpty
        ? "${_keyHomeTextConfig}_$username"
        : _keyHomeTextConfig;
    final String? jsonStr = prefs.getString(key);
    if (jsonStr != null) {
      return Map<String, dynamic>.from(jsonDecode(jsonStr));
    }
    return {};
  }

  static Future<bool> getSemesterEnabled() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username == null || username.isEmpty) {
      return prefs.getBool(keySemesterProgressEnabled) ?? false;
    }

    final bool? scoped =
        prefs.getBool("${keySemesterProgressEnabled}_$username");
    if (scoped == null) {
      final bool global = prefs.getBool(keySemesterProgressEnabled) ?? false;
      await prefs.setBool("${keySemesterProgressEnabled}_$username", global);
      return global;
    }
    return scoped;
  }

  static Future<DateTime?> getSemesterStart() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username == null || username.isEmpty) {
      String? s = prefs.getString(keySemesterStart);
      return s != null ? DateTime.tryParse(s) : null;
    }

    String? s = prefs.getString("${keySemesterStart}_$username");

    // 迁移检查：如果用户没有设置过隔离的日期，回退一次全局数据
    if (s == null) {
      s = prefs.getString(keySemesterStart);
      if (s != null) {
        await prefs.setString("${keySemesterStart}_$username", s);
      }
    }

    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<DateTime?> getSemesterEnd() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    if (username == null || username.isEmpty) {
      String? s = prefs.getString(keySemesterEnd);
      return s != null ? DateTime.tryParse(s) : null;
    }

    String? s = prefs.getString("${keySemesterEnd}_$username");
    if (s == null) {
      s = prefs.getString(keySemesterEnd);
      if (s != null) {
        await prefs.setString("${keySemesterEnd}_$username", s);
      }
    }
    return s != null ? DateTime.tryParse(s) : null;
  }

  // ==========================================
  // 多学期管理
  // ==========================================

  /// 获取所有学期列表
  static Future<List<SemesterInfo>> getSemesters() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keySemesters}_$username"
        : keySemesters;

    final String? jsonStr = prefs.getString(key);
    if (jsonStr == null || jsonStr.isEmpty) {
      // 迁移：如果没有任何学期数据，从旧的 semesterStart 创建一个默认学期
      final oldStart = await getSemesterStart();
      if (oldStart != null) {
        final defaultSemester = SemesterInfo(
          id: 'default',
          name: '当前学期',
          startDate: oldStart,
          isCurrent: true,
        );
        await saveSemesters([defaultSemester]);
        return [defaultSemester];
      }
      return [];
    }

    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list
          .map((e) => SemesterInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存学期列表
  static Future<void> saveSemesters(List<SemesterInfo> semesters) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keySemesters}_$username"
        : keySemesters;

    final jsonStr = jsonEncode(semesters.map((s) => s.toJson()).toList());
    await prefs.setString(key, jsonStr);

    // 同步更新旧的 semesterStart/semesterEnd（兼容）
    final current = semesters.where((s) => s.isCurrent).toList();
    if (current.isNotEmpty) {
      await prefs.setString(
          username != null && username.isNotEmpty
              ? "${keySemesterStart}_$username"
              : keySemesterStart,
          current.first.startDate.toIso8601String());
      if (current.first.endDate != null) {
        await prefs.setString(
            username != null && username.isNotEmpty
                ? "${keySemesterEnd}_$username"
                : keySemesterEnd,
            current.first.endDate!.toIso8601String());
      }
    }
  }

  /// 获取当前活跃学期 ID
  static Future<String> getActiveSemesterId() async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keyActiveSemester}_$username"
        : keyActiveSemester;

    return prefs.getString(key) ?? 'default';
  }

  /// 设置当前活跃学期 ID
  static Future<void> setActiveSemesterId(String semesterId) async {
    final prefs = await StorageService.prefs;
    final String? username = prefs.getString(keyCurrentUser);
    final String key = username != null && username.isNotEmpty
        ? "${keyActiveSemester}_$username"
        : keyActiveSemester;

    await prefs.setString(key, semesterId);
  }

  /// 获取指定学期的开学日期
  static Future<DateTime?> getSemesterStartById(String semesterId) async {
    final semesters = await getSemesters();
    try {
      final semester = semesters.firstWhere((s) => s.id == semesterId);
      return semester.startDate;
    } catch (_) {
      return null;
    }
  }

  /// 根据日期自动识别所属学期
  static Future<SemesterInfo?> getSemesterByDate(DateTime date) async {
    final semesters = await getSemesters();
    for (final semester in semesters) {
      final start = DateTime(semester.startDate.year, semester.startDate.month,
          semester.startDate.day);
      final end = semester.endDate != null
          ? DateTime(semester.endDate!.year, semester.endDate!.month,
              semester.endDate!.day)
          : start.add(const Duration(days: 120)); // 默认4个月

      if (!date.isBefore(start) && !date.isAfter(end)) {
        return semester;
      }
    }
    return null;
  }

  static Future<void> updateLastAutoSyncTime(String username) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(
        "${keyLastAutoSync}_$username", DateTime.now().millisecondsSinceEpoch);
  }

  static Future<DateTime?> getLastAutoSyncTime(String username) async {
    final prefs = await StorageService.prefs;
    int? timestamp = prefs.getInt("${keyLastAutoSync}_$username");
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
          .toLocal();
    }
    return null;
  }

  static Future<void> saveIslandBounds(
      String islandId, Map<String, dynamic> bounds) async {
    try {
      final prefs = await StorageService.prefs;
      await prefs.setString('island_bounds_$islandId', jsonEncode(bounds));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getIslandBounds(String islandId) async {
    try {
      final prefs = await StorageService.prefs;
      final s = prefs.getString('island_bounds_$islandId');
      if (s == null || s.isEmpty) return null;
      final m = jsonDecode(s);
      if (m is Map && m.isNotEmpty) return Map<String, dynamic>.from(m);
    } catch (_) {}
    return null;
  }

  // ==========================================
  // 🔄 大模型重试配置
  // ==========================================

  /// 获取大模型重试次数，默认3次
  static Future<int> getLLMRetryCount() async {
    final prefs = await StorageService.prefs;
    return prefs.getInt(keyLlmRetryCount) ?? 3;
  }

  /// 设置大模型重试次数
  static Future<void> setLLMRetryCount(int count) async {
    final prefs = await StorageService.prefs;
    await prefs.setInt(keyLlmRetryCount, count);
  }

  // ==========================================
  // 📋 待确认事项数据（用于通知点击后的二次确认）
  // ==========================================

  /// 保存待确认的事项数据（方法名为旧接口兼容保留）
  /// [status] 状态: 'processing'(处理中), 'success'(成功), 'failed'(失败)
  /// [compressedPath] 压缩后的图片路径，用于重试
  /// [currentAttempt] 当前尝试次数
  /// [maxAttempts] 最大尝试次数
  /// [errorMsg] 错误信息（失败时）
  static Future<void> savePendingTodoConfirm({
    required String imagePath,
    List<Map<String, dynamic>> results = const [],
    String status = 'success',
    String? compressedPath,
    int currentAttempt = 1,
    int maxAttempts = 1,
    String? errorMsg,
  }) async {
    final prefs = await StorageService.prefs;
    final data = jsonEncode({
      'imagePath': imagePath,
      'results': results,
      'status': status,
      'compressedPath': compressedPath,
      'currentAttempt': currentAttempt,
      'maxAttempts': maxAttempts,
      'errorMsg': errorMsg,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(keyPendingTodoConfirm, data);
  }

  /// 更新待确认事项数据的状态
  static Future<void> updatePendingTodoConfirmStatus({
    required String status,
    int? currentAttempt,
    int? maxAttempts,
    String? errorMsg,
    List<Map<String, dynamic>>? results,
  }) async {
    final existing = await getPendingTodoConfirm();
    if (existing == null) return;

    final prefs = await StorageService.prefs;
    final data = jsonEncode({
      ...existing,
      'status': status,
      'currentAttempt': currentAttempt ?? existing['currentAttempt'] ?? 1,
      'maxAttempts': maxAttempts ?? existing['maxAttempts'] ?? 1,
      'errorMsg': errorMsg ?? existing['errorMsg'],
      'results': results ?? existing['results'] ?? [],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(keyPendingTodoConfirm, data);
  }

  /// 获取待确认的事项数据
  static Future<Map<String, dynamic>?> getPendingTodoConfirm() async {
    final prefs = await StorageService.prefs;
    final data = prefs.getString(keyPendingTodoConfirm);
    if (data == null) return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 清除待确认的事项数据
  static Future<void> clearPendingTodoConfirm() async {
    final prefs = await StorageService.prefs;
    await prefs.remove(keyPendingTodoConfirm);
  }

  // ==========================================
  // 🔔 通知管理设置
  // ==========================================

  static Future<bool> isLiveActivityNotificationEnabled() =>
      AppSettingsStorage.isLiveActivityNotificationEnabled();

  static Future<void> setLiveActivityNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setLiveActivityNotificationEnabled(enabled);

  static Future<bool> isNormalNotificationEnabled() =>
      AppSettingsStorage.isNormalNotificationEnabled();

  static Future<void> setNormalNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setNormalNotificationEnabled(enabled);

  static Future<bool> isCourseNotificationEnabled() =>
      AppSettingsStorage.isCourseNotificationEnabled();

  static Future<void> setCourseNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setCourseNotificationEnabled(enabled);

  static Future<bool> isQuizNotificationEnabled() =>
      AppSettingsStorage.isQuizNotificationEnabled();

  static Future<void> setQuizNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setQuizNotificationEnabled(enabled);

  static Future<bool> isTodoSummaryNotificationEnabled() =>
      AppSettingsStorage.isTodoSummaryNotificationEnabled();

  static Future<void> setTodoSummaryNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setTodoSummaryNotificationEnabled(enabled);

  static Future<bool> isSpecialTodoNotificationEnabled() =>
      AppSettingsStorage.isSpecialTodoNotificationEnabled();

  static Future<void> setSpecialTodoNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setSpecialTodoNotificationEnabled(enabled);

  static Future<bool> isPomodoroNotificationEnabled() =>
      AppSettingsStorage.isPomodoroNotificationEnabled();

  static Future<void> setPomodoroNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setPomodoroNotificationEnabled(enabled);

  static Future<bool> isTodoRecognizeNotificationEnabled() =>
      AppSettingsStorage.isTodoRecognizeNotificationEnabled();

  static Future<void> setTodoRecognizeNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setTodoRecognizeNotificationEnabled(enabled);

  static Future<bool> isTodoLiveNotificationEnabled() =>
      AppSettingsStorage.isTodoLiveNotificationEnabled();

  static Future<void> setTodoLiveNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setTodoLiveNotificationEnabled(enabled);

  static Future<bool> isPomodoroEndNotificationEnabled() =>
      AppSettingsStorage.isPomodoroEndNotificationEnabled();

  static Future<void> setPomodoroEndNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setPomodoroEndNotificationEnabled(enabled);

  static Future<bool> isReminderNotificationEnabled() =>
      AppSettingsStorage.isReminderNotificationEnabled();

  static Future<void> setReminderNotificationEnabled(bool enabled) =>
      AppSettingsStorage.setReminderNotificationEnabled(enabled);

  static Future<int> getCourseReminderMinutes() =>
      AppSettingsStorage.getCourseReminderMinutes();

  static Future<void> setCourseReminderMinutes(int minutes) =>
      AppSettingsStorage.setCourseReminderMinutes(minutes);

  static Future<bool> isPrivacyPolicyAgreed() =>
      AppSettingsStorage.isPrivacyPolicyAgreed();

  static Future<void> setPrivacyPolicyAgreed(bool agreed, {String? date}) =>
      AppSettingsStorage.setPrivacyPolicyAgreed(agreed, date: date);

  static Future<bool> isPrivacyPolicyUpToDate() =>
      AppSettingsStorage.isPrivacyPolicyUpToDate();

  static Future<void> withdrawPrivacyAgreement() =>
      AppSettingsStorage.withdrawPrivacyAgreement();

  static void dispose() {
    _recurrenceCheckCache.clear();
    _attemptedRecurrenceSeriesRepairUploads.clear();
    _lastRecurrenceCheckDate = null;
  }

  static Future<String> getWallpaperProvider() =>
      AppSettingsStorage.getWallpaperProvider();

  static Future<void> saveWallpaperProvider(String provider) =>
      AppSettingsStorage.saveWallpaperProvider(provider);

  static Future<String> getWallpaperImageFormat() =>
      AppSettingsStorage.getWallpaperImageFormat();

  static Future<void> saveWallpaperImageFormat(String format) =>
      AppSettingsStorage.saveWallpaperImageFormat(format);

  static Future<int> getWallpaperIndex() =>
      AppSettingsStorage.getWallpaperIndex();

  static Future<void> saveWallpaperIndex(int index) =>
      AppSettingsStorage.saveWallpaperIndex(index);

  static Future<String> getWallpaperMkt() =>
      AppSettingsStorage.getWallpaperMkt();

  static Future<void> saveWallpaperMkt(String mkt) =>
      AppSettingsStorage.saveWallpaperMkt(mkt);

  static Future<String> getWallpaperResolution() =>
      AppSettingsStorage.getWallpaperResolution();

  static Future<void> saveWallpaperResolution(String resolution) =>
      AppSettingsStorage.saveWallpaperResolution(resolution);

  static Future<int?> getWallpaperCacheCleanupTime() =>
      AppSettingsStorage.getWallpaperCacheCleanupTime();

  static Future<void> saveWallpaperCacheCleanupTime(int timestamp) =>
      AppSettingsStorage.saveWallpaperCacheCleanupTime(timestamp);

  static Future<String?> getWallpaperCustomPath() =>
      AppSettingsStorage.getWallpaperCustomPath();

  static Future<void> saveWallpaperCustomPath(String path) =>
      AppSettingsStorage.saveWallpaperCustomPath(path);

  static Future<void> clearWallpaperCustomPath() =>
      AppSettingsStorage.clearWallpaperCustomPath();

  static Future<bool> getTodoFoldersInline() =>
      AppSettingsStorage.getTodoFoldersInline();

  static Future<void> setTodoFoldersInline(bool inline) =>
      AppSettingsStorage.setTodoFoldersInline(inline);

  static Future<String> getTodoFolderDisplayMode() =>
      AppSettingsStorage.getTodoFolderDisplayMode();

  static Future<void> setTodoFolderDisplayMode(String mode) =>
      AppSettingsStorage.setTodoFolderDisplayMode(mode);

  static Future<void> saveLastCourseImportUrl(String url) =>
      AppSettingsStorage.saveLastCourseImportUrl(url);

  static Future<String?> getLastCourseImportUrl() =>
      AppSettingsStorage.getLastCourseImportUrl();

  // categoryGroupId -> minutes
  static Future<Map<String, int>> getCategoryReminderMinutes(String username) =>
      AppSettingsStorage.getCategoryReminderMinutes(username);

  static Future<void> saveCategoryReminderMinutes(
          String username, Map<String, int> data) =>
      AppSettingsStorage.saveCategoryReminderMinutes(username, data);

  static Future<List<Map<String, dynamic>>> getSyncFailures() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query('op_logs',
        where: "sync_error IS NOT NULL AND sync_error != '' AND is_synced = 0",
        orderBy: 'timestamp DESC');
  }

  /// Resolve a conflict locally: clear the has_conflict flag in the database.
  /// If [createOplog] is true (keep_local case), also create an op_log entry
  /// with the bumped version so the next sync pushes it to the server.
  static Future<void> resolveConflictLocally({
    required String uuid,
    required String table,
    required Map<String, dynamic> resolvedData,
    bool createOplog = false,
    bool touchUpdatedAt = true,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();

    resolvedData['has_conflict'] = 0;
    resolvedData.remove('conflict_data');
    resolvedData.remove('serverVersionData');
    final now = DateTime.now().millisecondsSinceEpoch;
    final resolvedUpdatedAt = touchUpdatedAt
        ? now
        : (resolvedData['updated_at'] ??
            resolvedData['updatedAt'] ??
            DateTime.now().millisecondsSinceEpoch);
    resolvedData['updated_at'] = resolvedUpdatedAt;

    switch (table) {
      case 'todos':
        batch.update(
          'todos',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'created_at': resolvedData['created_at'] ??
                resolvedData['createdAt'] ??
                resolvedUpdatedAt,
            'content': resolvedData['content'] ?? resolvedData['title'] ?? '',
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'is_completed': resolvedData['is_completed'] == 1 ||
                    resolvedData['is_completed'] == true
                ? 1
                : 0,
            'due_date':
                resolvedData['due_date'] ?? resolvedData['dueDate'] ?? 0,
            'remark': resolvedData['remark'],
            'group_id': resolvedData['group_id'] ?? resolvedData['groupId'],
            'team_uuid': resolvedData['team_uuid'] ?? resolvedData['teamUuid'],
            'recurrence': resolvedData['recurrence'] ?? 0,
            'custom_interval_days': resolvedData['custom_interval_days'] ??
                resolvedData['customIntervalDays'] ??
                0,
            'recurrence_end_date': resolvedData['recurrence_end_date'] ??
                resolvedData['recurrenceEndDate'],
            'is_all_day': resolvedData['is_all_day'] == 1 ||
                    resolvedData['is_all_day'] == true ||
                    resolvedData['isAllDay'] == true
                ? 1
                : 0,
            'reminder_minutes': resolvedData['reminder_minutes'] ??
                resolvedData['reminderMinutes'] ??
                -1,
            'created_date': resolvedData['created_date'] ??
                resolvedData['createdDate'] ??
                0,
            'collab_type':
                resolvedData['collab_type'] ?? resolvedData['collabType'] ?? 0,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;

      case 'countdowns':
        final targetTime = resolvedData['target_time'] ??
            resolvedData['targetTime'] ??
            resolvedData['target_date'] ??
            0;
        batch.update(
          'countdowns',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'title': resolvedData['title'] ?? '',
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'is_completed': resolvedData['is_completed'] == 1 ||
                    resolvedData['is_completed'] == true
                ? 1
                : 0,
            'target_time': targetTime is int ? targetTime : 0,
            'team_uuid': resolvedData['team_uuid'] ?? resolvedData['teamUuid'],
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;

      case 'todo_groups':
        batch.update(
          'todo_groups',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'name': resolvedData['name'] ?? '',
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'is_expanded': resolvedData['is_expanded'] == 1 ||
                    resolvedData['is_expanded'] == true
                ? 1
                : 0,
            'team_uuid': resolvedData['team_uuid'] ?? resolvedData['teamUuid'],
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;
      case 'habit_goals':
        batch.update(
          'habit_goals',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'name': resolvedData['name'] ?? '',
            'icon': resolvedData['icon'],
            'source_type':
                resolvedData['source_type'] ?? resolvedData['sourceType'] ?? 2,
            'source_ids':
                resolvedData['source_ids'] ?? resolvedData['sourceIds'],
            'current_rule_uuid': resolvedData['current_rule_uuid'] ??
                resolvedData['currentRuleUuid'],
            'display_mode': resolvedData['display_mode'] ??
                resolvedData['displayMode'] ??
                0,
            'default_focus_minutes': resolvedData['default_focus_minutes'] ??
                resolvedData['defaultFocusMinutes'],
            'sort_order':
                resolvedData['sort_order'] ?? resolvedData['sortOrder'] ?? 0,
            'is_archived': resolvedData['is_archived'] == 1 ||
                    resolvedData['is_archived'] == true
                ? 1
                : 0,
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'device_id': resolvedData['device_id'] ?? resolvedData['deviceId'],
            'created_at': resolvedData['created_at'] ??
                resolvedData['createdAt'] ??
                resolvedUpdatedAt,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;
      case 'habit_goal_rule_revisions':
        batch.update(
          'habit_goal_rule_revisions',
          {
            'has_conflict': 0,
            'version': resolvedData['version'],
            'updated_at': resolvedUpdatedAt,
            'habit_uuid':
                resolvedData['habit_uuid'] ?? resolvedData['habitUuid'],
            'effective_from_date': resolvedData['effective_from_date'] ??
                resolvedData['effectiveFromDate'],
            'effective_to_date': resolvedData['effective_to_date'] ??
                resolvedData['effectiveToDate'],
            'period_type':
                resolvedData['period_type'] ?? resolvedData['periodType'] ?? 0,
            'weekdays_mask': resolvedData['weekdays_mask'] ??
                resolvedData['weekdaysMask'] ??
                127,
            'custom_interval_days': resolvedData['custom_interval_days'] ??
                resolvedData['customIntervalDays'],
            'target_value': resolvedData['target_value'] ??
                resolvedData['targetValue'] ??
                0,
            'unit': resolvedData['unit'],
            'target_time_minute': resolvedData['target_time_minute'] ??
                resolvedData['targetTimeMinute'],
            'time_comparison': resolvedData['time_comparison'] ??
                resolvedData['timeComparison'] ??
                0,
            'time_tolerance_minutes': resolvedData['time_tolerance_minutes'] ??
                resolvedData['timeToleranceMinutes'] ??
                0,
            'day_boundary_minute': resolvedData['day_boundary_minute'] ??
                resolvedData['dayBoundaryMinute'] ??
                0,
            'quick_values_json': resolvedData['quick_values_json'] ??
                resolvedData['quickValuesJson'],
            'reminder_policy_json': resolvedData['reminder_policy_json'] ??
                resolvedData['reminderPolicyJson'],
            'is_deleted': resolvedData['is_deleted'] == 1 ||
                    resolvedData['is_deleted'] == true
                ? 1
                : 0,
            'device_id': resolvedData['device_id'] ?? resolvedData['deviceId'],
            'created_at': resolvedData['created_at'] ??
                resolvedData['createdAt'] ??
                resolvedUpdatedAt,
          },
          where: 'uuid = ?',
          whereArgs: [uuid],
        );
        break;
    }

    batch.delete(
      'op_logs',
      where: 'is_synced = 0 AND target_table = ? AND target_uuid = ?',
      whereArgs: [table, uuid],
    );

    if (createOplog) {
      batch.insert('op_logs', {
        'op_type': 'UPSERT',
        'target_table': table,
        'target_uuid': uuid,
        'data_json': jsonEncode(resolvedData),
        'timestamp': now,
        'is_synced': 0,
        'sync_error': '',
      });
    }

    // Also clear conflict_data
    try {
      await db.rawUpdate(
        'UPDATE $table SET conflict_data = NULL WHERE uuid = ?',
        [uuid],
      );
    } catch (_) {}

    await batch.commit(noResult: true);
    _inflightTodoRequests.clear();

    // Invalidate SharedPreferences cache so next load picks up the resolved item
    final prefs = await SharedPreferences.getInstance();
    final key = table == 'todos'
        ? '${keyTodos}_${prefs.getString(keyCurrentUser) ?? 'default'}'
        : table == 'countdowns'
            ? '${keyCountdowns}_${prefs.getString(keyCurrentUser) ?? 'default'}'
            : '${keyTodoGroups}_${prefs.getString(keyCurrentUser) ?? 'default'}';
    await prefs.remove(key);

    triggerRefresh();
    recentlyResolvedUuids.add(uuid);
    recentlyResolvedTimes[uuid] = DateTime.now();
    debugPrint(
        '🔒 [MemoryShield] Locked recently resolved item in memory shield: $uuid (with timestamp)');
  }
}

class _TodoInterval {
  final TodoItem todo;
  final int startMs;
  final int endMs;

  const _TodoInterval({
    required this.todo,
    required this.startMs,
    required this.endMs,
  });
}
