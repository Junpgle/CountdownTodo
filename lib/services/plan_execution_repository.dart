import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'pomodoro_service.dart';

class PlanExecutionData {
  const PlanExecutionData({required this.records, required this.logs});
  final List<PomodoroRecord> records;
  final List<TimeLogItem> logs;
}

/// Read the actual intervals that overlap a local day, including records
/// beginning yesterday. This projection never creates planning blocks.
class PlanExecutionRepository {
  const PlanExecutionRepository({this.databaseOverride});
  final Database? databaseOverride;

  static List<String> _tags(Object? value) {
    if (value is List) return value.map((tag) => tag.toString()).toList();
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((tag) => tag.toString()).toList();
        }
      } catch (_) {
        // Old optional tag metadata must not hide an otherwise valid interval.
      }
    }
    return const [];
  }

  Future<PlanExecutionData> read(String username, DateTime date) async {
    Future<void> checkAccount() async {
      if ((await StorageService.getLoginSession() ?? 'default') != username) {
        throw StateError('账号已切换，请重新打开规划页');
      }
    }

    await checkAccount();
    final prefs = await SharedPreferences.getInstance();
    // Retain the existing legacy-log migration before using bounded SQL reads.
    if (!(prefs.getBool('migrated_timelogs_$username') ?? false) ||
        (prefs.getStringList('user_time_logs_$username')?.isNotEmpty ??
            false)) {
      await StorageService.getTimeLogs(username, limit: 1);
    }
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final start = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final end = DateTime(
      date.year,
      date.month,
      date.day + 1,
    ).millisecondsSinceEpoch;
    // Preserve PomodoroService's one-time Prefs migration when the SQL table
    // is empty; ordinary day reads do not load the entire record history.
    if (prefs.getString('pomodoro_records_$username') != null ||
        prefs.getString('pomodoro_records') != null) {
      final count =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM pomodoro_records'),
          ) ??
          0;
      if (count == 0) {
        await checkAccount();
        await PomodoroService.getRecords();
      }
    }
    await checkAccount();
    final recordRows = await db.query(
      'pomodoro_records',
      where:
          'is_deleted = 0 AND start_time < ? AND '
          'COALESCE(end_time, start_time + '
          'COALESCE(actual_duration, planned_duration, 0) * 1000) > ?',
      whereArgs: [end, start],
      orderBy: 'start_time ASC',
    );
    final logRows = await db.query(
      'time_logs',
      where:
          'is_deleted = 0 AND start_time < ? AND end_time > ? '
          'AND end_time > start_time',
      whereArgs: [end, start],
      orderBy: 'start_time ASC',
    );
    await checkAccount();
    return PlanExecutionData(
      records: recordRows
          .map(PomodoroRecord.fromJson)
          .where(
            (record) =>
                (record.endTime ??
                    record.startTime + record.effectiveDuration * 1000) >
                record.startTime,
          )
          .toList(),
      logs: logRows
          .map(
            (row) => TimeLogItem.fromJson({
              ...row,
              'id': row['uuid'],
              'tag_uuids': _tags(row['tag_uuids']),
            }),
          )
          .toList(),
    );
  }
}
