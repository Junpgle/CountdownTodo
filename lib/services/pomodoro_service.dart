import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:countdown_todo/services/database_helper.dart';

import '../models.dart';
import '../storage_service.dart';
import '../utils/time_utils.dart';
import '../utils/calendar_date_math.dart';
export '../utils/time_utils.dart';
import 'api_service.dart';
import 'storage/storage_key_scope.dart';
import 'storage/user_session_storage.dart';
import '../utils/json_value_parser.dart';
import 'focus_do_not_disturb_service.dart';

part 'pomodoro/pomodoro_models.dart';
part 'pomodoro/pomodoro_tags_and_records.dart';
part 'pomodoro/pomodoro_sync_and_queries.dart';

const _keySettings = 'pomodoro_settings_v2';
const _keyRunState = 'pomodoro_run_state';
const _keyTags = 'pomodoro_tags_v2';
const _keyRecords = 'pomodoro_records'; // 本地缓存记录列表
Future<void> _recordMutationQueue = Future<void>.value();

// ── 流控（用于 UI 实时响应状态变更，替代轮询） ──────────
final _runStateCtrl = StreamController<PomodoroRunState?>.broadcast();
const _keyLastRecordUpload = 'pomodoro_last_record_upload';
const _keyLastRecordDownload = 'pomodoro_last_record_download';
const _keyLastRecordRecoveryUpload = 'pomodoro_last_record_recovery_upload';
({DateTime fetchedAt, String dayKey, PomodoroCommunityStats? stats})?
_communityStatsCache;

class PomodoroService {
  static Stream<PomodoroRunState?> get onRunStateChanged =>
      _runStateCtrl.stream;

  static void dispose() => _pomoDispose();

  static Future<PomodoroSettings> getSettings() => _pomoGetSettings();

  static Future<void> saveSettings(PomodoroSettings settings) =>
      _pomoSaveSettings(settings);

  static Future<PomodoroRunState?> loadRunState() => _pomoLoadRunState();

  static Future<void> saveRunState(PomodoroRunState state) =>
      _pomoSaveRunState(state);

  static Future<void> clearRunState() => _pomoClearRunState();

  static Future<List<PomodoroTag>> getTags() => _pomoGetTags();

  /// 获取所有标签（包括已删除的），用于识别未知标签
  static Future<List<PomodoroTag>> getAllTagsIncludingDeleted() =>
      _pomoGetAllTagsIncludingDeleted();

  /// 保存标签（自动检测丢失的项并转化为墓碑，防止云端同步时复活）
  static Future<void> saveTags(
    List<PomodoroTag> tagsToSave, {
    bool isSyncSource = false,
  }) => _pomoSaveTags(tagsToSave, isSyncSource: isSyncSource);

  /// 软删除一个标签（打上 tombstone 标记），以便同步时告诉云端删除
  static Future<void> deleteTag(String uuid) => _pomoDeleteTag(uuid);

  static Future<void> syncTagsToCloud() => _pomoSyncTagsToCloud();

  static Future<void> syncTagsFromCloud() => _pomoSyncTagsFromCloud();

  /// 读取有效记录（不含已删除）
  static Future<List<PomodoroRecord>> getRecords() => _pomoGetRecords();

  /// Reads only the newest active record for summary surfaces.
  /// Falls back to the full reader when SQL has no active row so legacy
  /// preference data can still be migrated exactly as before.
  static Future<PomodoroRecord?> getLatestRecord() => _pomoGetLatestRecord();

  /// 添加一条专注记录，本地保存后立即尝试上传云端
  static Future<void> addRecord(
    PomodoroRecord record, {
    bool isSyncSource = false,
  }) => _pomoAddRecord(record, isSyncSource: isSyncSource);

  /// Rebuilds derived plan progress after the outer data sync saves its
  /// snapshot of plan blocks, which may predate the Pomodoro record merge.
  static Future<void> reconcilePlanBlockProgress(String username) =>
      _pomoReconcilePlanBlockProgress(username);

  /// 按半开时间范围 `[from, to)` 查询有效记录。
  static Future<List<PomodoroRecord>> getRecordsInRange(
    DateTime from,
    DateTime to,
  ) => _pomoGetRecordsInRange(from, to);

  /// 按半开时间范围读取专注统计所需的轻量字段。
  /// 年视图只显示汇总，不需要解码备注、暂停区间等完整记录内容。
  static Future<List<PomodoroSessionSummary>> getSessionSummariesInRange(
    DateTime from,
    DateTime to, {
    DateTime? tagsFrom,
    DateTime? tagsTo,
  }) => _pomoGetSessionSummariesInRange(
    from,
    to,
    tagsFrom: tagsFrom,
    tagsTo: tagsTo,
  );

  /// 总专注时长（秒），使用 effectiveDuration
  static int totalFocusSeconds(List<PomodoroRecord> records) =>
      _pomoTotalFocusSeconds(records);

  /// 按标签统计专注时长（秒）
  static Map<String, int> focusByTag(List<PomodoroRecord> records) =>
      _pomoFocusByTag(records);

  /// 格式化时长
  static String formatDuration(int totalSeconds) =>
      _pomoFormatDuration(totalSeconds);

  /// 从云端增量拉取专注记录（LWW 合并），返回是否有新增/变更
  static Future<bool> syncRecordsFromCloud({
    int? fromMs,
    bool forceFullSync = false,
    http.Client? client,
  }) => _pomoSyncRecordsFromCloud(
    fromMs: fromMs,
    forceFullSync: forceFullSync,
    client: client,
  );

  static Future<bool> mergeRecordsLww(List<PomodoroRecord> remoteRecords) =>
      _pomoMergeRecordsLww(remoteRecords);

  static Future<void> syncRecordsToCloud({
    bool forceFullSync = false,
    http.Client? client,
  }) => _pomoSyncRecordsToCloud(forceFullSync: forceFullSync, client: client);

  /// 今日专注记录（本地，不含已删除）
  static Future<List<PomodoroRecord>> getTodayRecords() =>
      _pomoGetTodayRecords();

  /// 昨日专注记录（本地，不含已删除）
  static Future<List<PomodoroRecord>> getYesterdayRecords() =>
      _pomoGetYesterdayRecords();

  /// 最近专注：今日有则返回今日，否则返回昨日；同时返回是哪天
  static Future<({List<PomodoroRecord> records, bool isToday})>
  getRecentRecords() => _pomoGetRecentRecords();

  /// 查询绑定到指定 todoUuid 的所有专注记录
  static Future<List<PomodoroRecord>> getRecordsByTodoUuid(String todoUuid) =>
      _pomoGetRecordsByTodoUuid(todoUuid);

  /// 查询绑定到一组待办的有效专注记录。
  ///
  /// 编辑循环待办时，一个编辑对象可能对应多个历史 occurrence。这里直接
  /// 按 todo_uuid 查询，避免先读取、反序列化全部专注历史再在 Dart 侧过滤。
  static Future<List<PomodoroRecord>> getRecordsByTodoUuids(
    Iterable<String> todoUuids,
  ) => _pomoGetRecordsByTodoUuids(todoUuids);

  static Future<List<PomodoroRecord>> getSessions() => _pomoGetRecords();
  static Future<void> addSession(PomodoroRecord session) =>
      _pomoAddRecord(session);
  static Future<List<PomodoroRecord>> getSessionsInRange(
    DateTime from,
    DateTime to,
  ) => _pomoGetRecordsInRange(from, to);
  static int totalFocusSecondsFromSessions(List<PomodoroRecord> s) =>
      _pomoTotalFocusSeconds(s);

  /// 更新一条记录（修改标签 / 绑定任务等）
  /// 先本地保存（立即返回），云端上传在后台异步进行
  static Future<void> updateRecord(PomodoroRecord updated) =>
      _pomoUpdateRecord(updated);

  /// 软删除一条记录
  static Future<void> deleteRecord(String uuid) => _pomoDeleteRecord(uuid);

  // 统计页面兼容别名
  static Future<void> updateSession(PomodoroRecord s) => _pomoUpdateRecord(s);
  static Future<void> deleteSession(String uuid) => _pomoDeleteRecord(uuid);

  /// 获取近7日全站专注日均统计（带 60 秒内存缓存；无数据或离线时返回 null）
  static Future<PomodoroCommunityStats?> getTodayCommunityStats({
    bool forceRefresh = false,
    DateTime? now,
    Future<Map<String, dynamic>?> Function(int fromMs, int toMs)? fetcher,
  }) => _pomoGetTodayCommunityStats(
    forceRefresh: forceRefresh,
    now: now,
    fetcher: fetcher,
  );

  static void clearCommunityStatsCacheForTest() =>
      _pomoClearCommunityStatsCacheForTest();
}
