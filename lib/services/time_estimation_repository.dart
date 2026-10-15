import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class TimeEstimationAccountChanged implements Exception {
  const TimeEstimationAccountChanged();
}

class TimeEstimationSample {
  TimeEstimationSample({
    required this.todoId,
    required this.title,
    required this.actualSeconds,
    required this.endedAt,
    this.groupId,
    Set<String> tagIds = const {},
  }) : tagIds = Set.unmodifiable(tagIds);

  final String todoId, title;
  final int actualSeconds, endedAt;
  final String? groupId;
  final Set<String> tagIds;
  double get minutes => actualSeconds / 60;
}

class TimeEstimationHistory {
  TimeEstimationHistory(
    Iterable<TimeEstimationSample> samples, {
    this.incompleteCount = 0,
    this.noActualCount = 0,
  }) : samples = List.unmodifiable(samples);
  final List<TimeEstimationSample> samples;
  final int incompleteCount, noActualCount;
}

/// Read-only calibration data. Planned durations and plan caches are never
/// measurements. Aggregate complete tasks before applying the sample limit.
class TimeEstimationRepository {
  const TimeEstimationRepository({this.databaseOverride});
  final Database? databaseOverride;
  static const maxSamples = 500;

  static Future<String> activeUsername() async {
    final value = (await SharedPreferences.getInstance()).getString(
      'current_login_user',
    );
    return value == null || value.isEmpty ? 'default' : value;
  }

  static Future<void> checkAccount(String username) async {
    if (await activeUsername() != username) {
      throw const TimeEstimationAccountChanged();
    }
  }

  // Contradictory bindings taint both tasks. A missing/deleted plan is never
  // a fallback owner, but an explicit todo binding remains authoritative.
  // A two-second tolerance permits rounding at old record boundaries.
  static const _cte = '''
WITH raw AS (
 SELECT r.uuid AS record_id, NULLIF(TRIM(r.todo_uuid), '') AS direct_id,
   NULLIF(TRIM(p.todo_uuid), '') AS linked_id,
   CASE WHEN p.is_deleted = 0 AND p.uuid NOT LIKE 'mapped\\_%' ESCAPE '\\'
     THEN NULLIF(TRIM(p.todo_uuid), '') END AS fallback_id,
   r.actual_duration AS seconds, r.end_time AS ended_at, r.tag_uuids AS tags,
   CASE WHEN r.uuid IS NOT NULL AND TRIM(r.uuid) != ''
     AND COALESCE(r.has_conflict, 0) = 0
     AND r.status IN ('completed', 'abandoned')
     AND typeof(r.start_time) = 'integer' AND r.start_time > 0
     AND typeof(r.end_time) = 'integer' AND r.end_time > r.start_time
     AND r.end_time <= ?
     AND typeof(r.actual_duration) IN ('integer', 'real')
     AND r.actual_duration = CAST(r.actual_duration AS INTEGER)
     AND r.actual_duration >= 0
     AND r.actual_duration <= (r.end_time - r.start_time) / 1000.0 + 2
     AND (NULLIF(TRIM(r.todo_uuid), '') IS NULL
       OR NULLIF(TRIM(p.todo_uuid), '') IS NULL OR r.todo_uuid = p.todo_uuid)
     THEN 1 ELSE 0 END AS valid
 FROM pomodoro_records r
 LEFT JOIN todo_plan_blocks p ON p.uuid = r.plan_block_id
 WHERE COALESCE(r.is_deleted, 0) = 0
), attributed AS (
 SELECT record_id, COALESCE(direct_id, fallback_id) AS todo_id,
   seconds, ended_at, tags, valid FROM raw
 UNION ALL
 SELECT record_id, linked_id, seconds, ended_at, tags, 0 FROM raw
 WHERE direct_id IS NOT NULL AND linked_id IS NOT NULL AND direct_id != linked_id
), totals AS (
 SELECT todo_id, SUM(CASE WHEN valid = 1 THEN seconds ELSE 0 END) AS seconds,
   MAX(CASE WHEN valid = 1 THEN ended_at ELSE 0 END) AS ended_at,
   SUM(CASE WHEN valid = 0 THEN 1 ELSE 0 END) AS invalid_count
 FROM attributed WHERE todo_id IS NOT NULL GROUP BY todo_id
), completed AS (
 SELECT t.uuid, t.content AS title, t.group_id, a.seconds, a.ended_at,
   COALESCE(a.invalid_count, 0) AS invalid_count
 FROM todos t LEFT JOIN totals a ON a.todo_id = t.uuid
 WHERE t.is_completed = 1 AND COALESCE(t.is_deleted, 0) = 0
   AND COALESCE(t.has_conflict, 0) = 0
   AND t.uuid IS NOT NULL AND TRIM(t.uuid) != ''
   AND TRIM(COALESCE(t.content, '')) != ''
)
''';

  Future<TimeEstimationHistory> read(String username, DateTime now) async {
    await checkAccount(username);
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final history = await db.transaction((txn) async {
      final args = [now.millisecondsSinceEpoch];
      final rows = await txn.rawQuery('''$_cte
 SELECT uuid, title, group_id, seconds, ended_at FROM completed
 WHERE invalid_count = 0 AND seconds > 0
 ORDER BY ended_at DESC, uuid LIMIT $maxSamples
''', args);
      final diagnostics = (await txn.rawQuery('''$_cte
 SELECT COALESCE(SUM(CASE WHEN invalid_count > 0 THEN 1 ELSE 0 END), 0) AS incomplete,
   COALESCE(SUM(CASE WHEN invalid_count = 0 AND COALESCE(seconds, 0) = 0
     THEN 1 ELSE 0 END), 0) AS no_actual FROM completed
''', args)).single;
      final tags = <String, Set<String>>{};
      if (rows.isNotEmpty) {
        final ids = rows.map((r) => r['uuid'] as String).toList();
        final tagRows = await txn.rawQuery(
          '''$_cte
 SELECT DISTINCT todo_id, tags FROM attributed
 WHERE valid = 1 AND todo_id IN (${List.filled(ids.length, '?').join(',')})
   AND tags IS NOT NULL AND tags != ''
''',
          [...args, ...ids],
        );
        for (final row in tagRows) {
          final set = tags.putIfAbsent(row['todo_id'] as String, () => {});
          try {
            final decoded = jsonDecode(row['tags'] as String);
            if (decoded is List) {
              set.addAll(
                decoded.whereType<String>().where((id) => id.isNotEmpty),
              );
            }
          } catch (_) {
            // Invalid tag metadata cannot create a category match.
          }
        }
      }
      await checkAccount(username);
      return TimeEstimationHistory(
        rows.map(
          (row) => TimeEstimationSample(
            todoId: row['uuid'] as String,
            title: (row['title'] as String).trim(),
            actualSeconds: (row['seconds'] as num).toInt(),
            endedAt: (row['ended_at'] as num).toInt(),
            groupId: row['group_id'] as String?,
            tagIds: tags[row['uuid']] ?? {},
          ),
        ),
        incompleteCount: (diagnostics['incomplete'] as num).toInt(),
        noActualCount: (diagnostics['no_actual'] as num).toInt(),
      );
    }, exclusive: false);
    await checkAccount(username);
    return history;
  }
}
