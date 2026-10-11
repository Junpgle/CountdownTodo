import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'plan_todo_guard.dart';

enum PlanReviewFilter {
  plans,
  ended,
  missed,
  focus,
  linked,
  unlinked,
  attribution,
  logs,
  issues,
}

class PlanReviewEntry {
  PlanReviewEntry(Map<String, Object?> row) : values = Map.unmodifiable(row);
  final Map<String, Object?> values;
  String get id => values['id']?.toString() ?? '';
  String get kind => values['kind'] as String;
  String get title => (values['title']?.toString().trim().isNotEmpty ?? false)
      ? values['title'].toString()
      : '未命名记录';
  String get reason => values['reason']?.toString() ?? '';
  int get start => values['start'] is int ? values['start'] as int : 0;
  int get end => values['end'] is int ? values['end'] as int : 0;
  int get seconds => values['seconds'] is int ? values['seconds'] as int : 0;
  String? get planId => values['planId'] as String?;
  String? get todoId => values['todoId'] as String?;
  bool get verified => values['verified'] == 1;
}

class PlanReviewCursor {
  const PlanReviewCursor(this.fingerprint, this.start, this.kind, this.id);
  final String fingerprint, kind, id;
  final int start;
}

class PlanReviewPage {
  const PlanReviewPage(
    this.rows,
    this.total,
    this.seconds,
    this.next,
    this.restarted,
    this.identity,
    this.fingerprint,
    this.nextBoundary,
  );
  final List<PlanReviewEntry> rows;
  final int total, seconds;
  final PlanReviewCursor? next;
  final bool restarted;
  final PlanTodoIdentity identity;
  final String fingerprint;
  final DateTime nextBoundary;
}

class PlanReviewSummary {
  const PlanReviewSummary({
    required this.identity,
    required this.start,
    required this.end,
    required this.plans,
    required this.focus,
    required this.logs,
    required this.issues,
    required this.days,
    required this.ranking,
    required this.missed,
    required this.nextBoundary,
  });
  final PlanTodoIdentity identity;
  final DateTime start, end, nextBoundary;
  final Map<String, Object?> plans, focus, logs;
  final int issues;
  final List<Map<String, Object?>> days, ranking;
  final List<PlanReviewEntry> missed;
  int plan(String key) => (plans[key] as num?)?.toInt() ?? 0;
  int actual(String key) => (focus[key] as num?)?.toInt() ?? 0;
  int log(String key) => (logs[key] as num?)?.toInt() ?? 0;
}

/// All aggregation is read-only. No facade migrations or state maintenance run
/// here; full record payloads are fetched only after selecting a detail row.
class PlanReviewRepository {
  const PlanReviewRepository({this.databaseOverride, this.clock, this.onQuery});
  final Database? databaseOverride;
  final DateTime Function()? clock;
  final void Function(String sql, int rowCount)? onQuery;
  static final _databaseTokens = Expando<int>();
  static int _nextDatabaseToken = 0;
  DateTime get now => clock?.call() ?? DateTime.now();

  Future<List<Map<String, Object?>>> _query(
    DatabaseExecutor db,
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final rows = await db.rawQuery(sql, args);
    onQuery?.call(sql, rows.length);
    return rows;
  }

  Future<Database> _database(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pendingTodos =
        !(prefs.getBool('migration_marker_${username}_v4') ?? false) &&
        ((prefs.getStringList('user_todos_$username') ?? []).isNotEmpty ||
            (prefs.getStringList('user_todos') ?? []).isNotEmpty);
    final pendingLogs =
        (prefs.getStringList('user_time_logs_$username') ?? []).isNotEmpty ||
        (prefs.getStringList('user_time_logs') ?? []).isNotEmpty;
    bool hasLegacyFocus(String key) {
      final value = prefs.getString(key)?.trim();
      return value != null && value.isNotEmpty && value != '[]';
    }

    if (pendingTodos ||
        pendingLogs ||
        hasLegacyFocus('pomodoro_records_$username') ||
        hasLegacyFocus('pomodoro_records')) {
      // The existing Pomodoro migration retains Prefs; check SQL presence below.
      final db =
          databaseOverride ??
          await DatabaseHelper.instance.databaseForUser(username);
      if (pendingTodos ||
          pendingLogs ||
          (Sqflite.firstIntValue(
                    await _query(db, 'SELECT COUNT(*) FROM pomodoro_records'),
                  ) ??
                  0) ==
              0) {
        throw StateError('历史存储尚未初始化，请返回首页或专注页加载后重试');
      }
      return db;
    }
    return databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
  }

  Future<_ReviewSql> _sql(
    DatabaseExecutor db,
    DateTime start,
    DateTime end,
    DateTime instant, {
    String? planId,
  }) async {
    final flags = <String, bool>{};
    for (final table in ['todo_plan_blocks', 'pomodoro_records', 'time_logs']) {
      flags[table] = (await _query(
        db,
        'PRAGMA table_info($table)',
      )).any((row) => row['name'] == 'has_conflict');
    }
    if (!end.isAfter(start) || end.difference(start).inDays > 32) {
      throw ArgumentError('请选择有效的日、周或月范围');
    }
    return _ReviewSql(start, end, instant, flags, planId);
  }

  Future<PlanReviewSummary> read(
    String username,
    DateTime start,
    DateTime end,
  ) async {
    final identity = await PlanTodoIdentity.capture(username);
    final db = await _database(username);
    final instant = now;
    final result = await db.transaction((tx) async {
      final sql = await _sql(tx, start, end, instant);
      final plans = (await _query(
        tx,
        '${sql.cte} ${sql.planAggregate}',
        sql.args,
      )).single;
      final focus = (await _query(
        tx,
        '${sql.cte} ${sql.focusAggregate}',
        sql.args,
      )).single;
      final logs = (await _query(
        tx,
        '${sql.cte} ${sql.logAggregate}',
        sql.args,
      )).single;
      final issues = (await _query(
        tx,
        '${sql.cte} SELECT COUNT(*) n FROM (${sql.entries(PlanReviewFilter.issues)})',
        sql.args,
      )).single;
      final days = await _query(tx, '${sql.cte} ${sql.dayAggregate}', sql.args);
      final ranking = await _query(
        tx,
        '''${sql.cte}
        SELECT ownerId id, MAX(ownerTitle) title, SUM(seconds) seconds, COUNT(*) n
        FROM focus WHERE valid=1 AND ownerId IS NOT NULL
        GROUP BY ownerId ORDER BY seconds DESC, ownerId ASC LIMIT 10''',
        sql.args,
      );
      final missed = await _query(tx, '''${sql.cte}
        SELECT * FROM (${sql.entries(PlanReviewFilter.missed)})
        ORDER BY start DESC, kind, id LIMIT 10''', sql.args);
      final boundary = plans['boundary'] as int?;
      final midnight = DateTime(instant.year, instant.month, instant.day + 1);
      return PlanReviewSummary(
        identity: identity,
        start: start,
        end: end,
        plans: Map.unmodifiable(plans),
        focus: Map.unmodifiable(focus),
        logs: Map.unmodifiable(logs),
        issues: (issues['n'] as num).toInt(),
        days: List.unmodifiable(days),
        ranking: List.unmodifiable(ranking),
        missed: List.unmodifiable(missed.map(PlanReviewEntry.new)),
        nextBoundary:
            boundary != null && boundary < midnight.millisecondsSinceEpoch
            ? DateTime.fromMillisecondsSinceEpoch(boundary)
            : midnight,
      );
    });
    await identity.check();
    return result;
  }

  Future<PlanReviewPage> page(
    String username,
    DateTime start,
    DateTime end,
    PlanReviewFilter filter, {
    String? todoId,
    String? planId,
    PlanReviewCursor? cursor,
    bool cumulative = false,
  }) async {
    final identity = await PlanTodoIdentity.capture(username);
    final db = await _database(username);
    final instant = now;
    final result = await db.transaction((tx) async {
      final sql = await _sql(
        tx,
        start,
        end,
        instant,
        planId: cumulative ? planId : null,
      );
      final where = [
        if (todoId != null) 'todoId=?',
        if (planId != null) 'planId=?',
      ].join(' AND ');
      final entries =
          'SELECT * FROM (${sql.entries(filter)})'
          '${where.isEmpty ? '' : ' WHERE $where'}';
      final args = [...sql.args, ?todoId, ?planId];
      final totals = (await _query(tx, '''${sql.cte}
        SELECT COUNT(*) n, COALESCE(SUM(durationMs),0)/1000 seconds,
          (SELECT MIN(boundary) FROM (
            SELECT MIN(end) boundary FROM plans WHERE ${sql.planRange} AND valid=1
              AND status NOT IN (3,7) AND end>${instant.millisecondsSinceEpoch}
            UNION ALL
            SELECT MIN(end) boundary FROM logs
              WHERE end>${instant.millisecondsSinceEpoch}
          )) boundary
          FROM ($entries)''', args)).single;
      // Covers writes in this connection and commits in other connections.
      // No full-history metadata decoding, cache table or persistence write.
      final connection = await _query(tx, 'SELECT total_changes() n');
      final external = await _query(tx, 'PRAGMA data_version');
      final fingerprint = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                username,
                _databaseTokens[db] ??= ++_nextDatabaseToken,
                identity.userId,
                start.millisecondsSinceEpoch,
                end.millisecondsSinceEpoch,
                filter.name,
                todoId,
                planId,
                cumulative,
                totals,
                connection,
                external,
                instant.year,
                instant.month,
                instant.day,
              ]),
            ),
          )
          .toString();
      final restarted = cursor != null && cursor.fingerprint != fingerprint;
      final validCursor = restarted ? null : cursor;
      final rows = await _query(
        tx,
        '''${sql.cte}
        SELECT * FROM ($entries)
        ${validCursor == null ? '' : 'WHERE start < ? OR (start = ? AND (kind > ? OR (kind = ? AND id > ?)))'}
        ORDER BY start DESC, kind ASC, id ASC LIMIT 51''',
        [
          ...args,
          if (validCursor != null) ...[
            validCursor.start,
            validCursor.start,
            validCursor.kind,
            validCursor.kind,
            validCursor.id,
          ],
        ],
      );
      final selected = rows.take(50).map(PlanReviewEntry.new).toList();
      final last = selected.isEmpty ? null : selected.last;
      final midnight = DateTime(instant.year, instant.month, instant.day + 1);
      final boundary = totals['boundary'] as int?;
      return PlanReviewPage(
        List.unmodifiable(selected),
        (totals['n'] as num).toInt(),
        (totals['seconds'] as num).toInt(),
        rows.length > 50 && last != null
            ? PlanReviewCursor(fingerprint, last.start, last.kind, last.id)
            : null,
        restarted,
        identity,
        fingerprint,
        boundary != null && boundary < midnight.millisecondsSinceEpoch
            ? DateTime.fromMillisecondsSinceEpoch(boundary)
            : midnight,
      );
    });
    await identity.check();
    return result;
  }

  Future<Map<String, Object?>> detail(
    PlanTodoIdentity identity,
    String kind,
    String id,
  ) async {
    await identity.check();
    final db = await _database(identity.username);
    final table = switch (kind) {
      'plan' => 'todo_plan_blocks',
      'focus' => 'pomodoro_records',
      'log' => 'time_logs',
      _ => throw ArgumentError('未知记录类型'),
    };
    final rows = await _query(
      db,
      'SELECT * FROM $table WHERE uuid=? AND COALESCE(is_deleted,0)=0 LIMIT 1',
      [id],
    );
    await identity.check();
    if (rows.isEmpty) throw StateError('记录已删除或不存在，请刷新列表');
    final row = rows.single;
    final rawTags = row['tag_uuids'];
    var tagIds = <String>[];
    if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) tagIds = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        tagIds = rawTags.split(',');
      }
    }
    final tags = <Map<String, Object?>>[];
    for (var i = 0; i < tagIds.length; i += 400) {
      final batch = tagIds.skip(i).take(400).toList();
      tags.addAll(
        await _query(
          db,
          'SELECT * FROM pomodoro_tags WHERE COALESCE(is_deleted,0)=0 AND uuid IN (${List.filled(batch.length, '?').join(',')})',
          batch,
        ),
      );
    }
    final a = row['start_time'],
        b = row['end_time'],
        seconds = row['actual_duration'];
    final valid =
        a is int &&
        b is int &&
        a > 0 &&
        b > a &&
        b <= 8640000000000000 &&
        (row['has_conflict'] == null || row['has_conflict'] == 0) &&
        (kind != 'focus' ||
            (seconds is int &&
                seconds >= 0 &&
                b <= now.millisecondsSinceEpoch &&
                const [
                  'completed',
                  'interrupted',
                  'switched',
                ].contains(row['status'])));
    await identity.check();
    return Map.unmodifiable({
      ...row,
      'review_tags': tags,
      'review_valid': valid,
    });
  }
}

class _ReviewSql {
  _ReviewSql(this.start, this.end, this.now, this.flags, this.planId);
  final DateTime start, end, now;
  final Map<String, bool> flags;
  final String? planId;
  int get lo => start.millisecondsSinceEpoch;
  int get hi => end.millisecondsSinceEpoch;
  int get instant => now.millisecondsSinceEpoch;
  List<Object?> get args => planId == null ? [] : [planId, planId, planId];
  String conflict(String table, String alias) =>
      flags[table]! ? 'COALESCE($alias.has_conflict,0)=0' : '1';
  String get focusScope => planId == null
      ? 'r.start_time >= $lo AND r.start_time < $hi'
      : '''(r.plan_block_id=? OR r.todo_uuid=(SELECT todo_uuid FROM todo_plan_blocks WHERE uuid=?)
        OR INSTR(','||(SELECT COALESCE(pomodoro_record_ids,'') FROM todo_plan_blocks WHERE uuid=?)||',', ','||r.uuid||',')>0)''';
  String get cte =>
      '''WITH
    plans AS (SELECT p.uuid id, p.todo_uuid todoId, p.title_snapshot title,
      p.start_time start, p.end_time end, p.planned_minutes minutes, p.status status,
      p.actual_focus_seconds cache, p.pomodoro_record_ids links,
      COALESCE(p.is_deleted,0) deleted,
      CASE WHEN COALESCE(p.is_deleted,0)=0 AND ${conflict('todo_plan_blocks', 'p')}
        AND typeof(p.start_time)='integer' AND p.start_time>0
        AND typeof(p.end_time)='integer' AND p.end_time>p.start_time AND p.end_time<=8640000000000000
        AND typeof(p.planned_minutes)='integer' AND p.planned_minutes>0
        AND p.status IN (0,1,2,3,4,5,6,7) AND LENGTH(TRIM(COALESCE(p.uuid,'')))>0
        THEN 1 ELSE 0 END valid FROM todo_plan_blocks p
      WHERE (p.start_time >= $lo AND p.start_time < $hi)
        OR p.uuid IN (SELECT planId FROM raw_focus WHERE planId IS NOT NULL)
        OR (p.todo_uuid IN (SELECT todoId FROM raw_focus WHERE todoId IS NOT NULL)
          AND EXISTS (SELECT 1 FROM raw_focus r WHERE r.todoId=p.todo_uuid
            AND p.start_time<r.end AND p.end_time>r.start))
        OR (LENGTH(COALESCE(p.pomodoro_record_ids,''))>0 AND EXISTS (
          SELECT 1 FROM raw_focus r WHERE INSTR(','||p.pomodoro_record_ids||',',','||r.id||',')>0))),
    raw_focus AS (SELECT r.uuid id, NULLIF(TRIM(r.todo_uuid),'') todoId,
      r.todo_title title, r.start_time start, r.end_time end,
      r.actual_duration seconds, r.planned_duration legacySeconds,
      NULLIF(TRIM(r.plan_block_id),'') planId,
      CASE WHEN ${conflict('pomodoro_records', 'r')}
        AND typeof(r.start_time)='integer' AND r.start_time>0
        AND typeof(r.end_time)='integer' AND r.end_time>r.start_time AND r.end_time<=$instant
        AND typeof(r.actual_duration)='integer' AND r.actual_duration>=0
        AND r.status IN ('completed','interrupted','switched')
        AND LENGTH(TRIM(COALESCE(r.uuid,'')))>0 THEN 1 ELSE 0 END valid
      FROM pomodoro_records r WHERE COALESCE(r.is_deleted,0)=0 AND $focusScope),
    explicit AS (SELECT r.id recordId, p.id, p.todoId, p.valid
      FROM raw_focus r JOIN plans p ON p.id=r.planId
        OR INSTR(','||COALESCE(p.links,'')||',', ','||r.id||',')>0),
    claims AS (SELECT * FROM explicit UNION
      SELECT r.id recordId, p.id, p.todoId, p.valid
      FROM raw_focus r JOIN plans p ON p.todoId=r.todoId AND p.deleted=0
        AND p.start<r.end AND p.end>r.start
      WHERE r.planId IS NULL AND NOT EXISTS(SELECT 1 FROM explicit e WHERE e.recordId=r.id)),
    owners AS (SELECT c.recordId, COUNT(DISTINCT c.id) n, MIN(c.id) planId,
      MIN(c.todoId) todoId, MIN(c.valid) valid,
      MAX(CASE WHEN r.todoId IS NOT NULL AND (c.todoId IS NULL OR r.todoId<>c.todoId) THEN 1 ELSE 0 END) mismatch
      FROM claims c JOIN raw_focus r ON r.id=c.recordId GROUP BY c.recordId),
    attributed AS (SELECT r.*, CASE
      WHEN o.n IS NULL AND r.planId IS NULL THEN 'unlinked'
      WHEN o.n=1 AND o.valid=1 AND o.mismatch=0 AND (r.planId IS NULL OR r.planId=o.planId) AND LENGTH(TRIM(COALESCE(o.todoId,'')))>0 THEN 'linked'
      ELSE 'attribution' END category,
      CASE WHEN o.n=1 AND o.valid=1 AND o.mismatch=0 AND (r.planId IS NULL OR r.planId=o.planId) THEN o.planId ELSE NULL END ownerPlan,
      CASE WHEN COALESCE(o.mismatch,0)=0 AND (r.todoId IS NOT NULL OR
        (o.n=1 AND o.valid=1 AND (r.planId IS NULL OR r.planId=o.planId)))
        THEN COALESCE(r.todoId, NULLIF(TRIM(o.todoId),'')) ELSE NULL END ownerId
      FROM raw_focus r LEFT JOIN owners o ON o.recordId=r.id),
    focus AS (SELECT a.*, CASE WHEN t.uuid IS NULL OR COALESCE(t.is_deleted,0)=1
      THEN COALESCE(NULLIF(a.title,''),'历史待办专注')
      ELSE COALESCE(NULLIF(t.content,''),NULLIF(a.title,''),'未绑定待办的专注') END ownerTitle,
      CASE WHEN a.ownerId IS NOT NULL AND (t.uuid IS NULL OR COALESCE(t.is_deleted,0)=1) THEN 1 ELSE 0 END historical
      FROM attributed a LEFT JOIN todos t ON t.uuid=a.ownerId),
    logs AS (SELECT l.uuid id, l.title title, l.start_time start, l.end_time end,
      CASE WHEN ${conflict('time_logs', 'l')}
        AND typeof(l.start_time)='integer' AND l.start_time>0
        AND typeof(l.end_time)='integer' AND l.end_time>l.start_time
        AND l.end_time<=$instant AND l.end_time<=8640000000000000
        THEN 1 ELSE 0 END valid FROM time_logs l
      WHERE COALESCE(l.is_deleted,0)=0 AND l.start_time<$hi AND (l.end_time>$lo OR l.start_time>=$lo))
  ''';
  String get planRange => 'start >= $lo AND start < $hi AND deleted=0';
  String get planAggregate =>
      '''SELECT
    COALESCE(SUM(CASE WHEN valid=1 AND status NOT IN (3,7) THEN minutes*60 ELSE 0 END),0) seconds,
    SUM(CASE WHEN valid=1 AND status NOT IN (3,7) THEN 1 ELSE 0 END) n,
    SUM(CASE WHEN valid=1 AND status NOT IN (3,7) AND end<=$instant THEN 1 ELSE 0 END) ended,
    SUM(CASE WHEN valid=1 AND status=1 AND end<=$instant THEN 1 ELSE 0 END) done,
    SUM(CASE WHEN valid=1 AND status=6 AND end<=$instant THEN 1 ELSE 0 END) missed,
    SUM(CASE WHEN valid=1 AND status NOT IN (3,7) AND end>$instant THEN 1 ELSE 0 END) upcoming,
    SUM(CASE WHEN valid=1 AND status=3 THEN 1 ELSE 0 END) cancelled,
    SUM(CASE WHEN valid=1 AND status=7 THEN 1 ELSE 0 END) skipped,
    (SELECT MIN(boundary) FROM (
      SELECT MIN(end) boundary FROM plans WHERE valid=1 AND status NOT IN (3,7) AND end>$instant
      UNION ALL SELECT MIN(end) boundary FROM logs WHERE end>$instant
    )) boundary
    FROM plans WHERE $planRange''';
  String get focusAggregate =>
      '''SELECT COALESCE(SUM(CASE WHEN valid=1 THEN seconds ELSE 0 END),0) seconds,
    SUM(CASE WHEN valid=1 THEN 1 ELSE 0 END) n,
    ${['linked', 'unlinked', 'attribution'].map((c) => "COALESCE(SUM(CASE WHEN valid=1 AND category='$c' THEN seconds ELSE 0 END),0) $c").join(',')}
    FROM focus''';
  String get logAggregate =>
      '''SELECT COALESCE(SUM(MIN(end,$hi)-MAX(start,$lo)),0)/1000 seconds, COUNT(*) n
    FROM logs WHERE valid=1 AND end>$lo''';

  String _planEntries(String condition, {String reason = "''"}) =>
      '''SELECT id,'plan' kind,title,start,end,minutes*60 seconds,$reason reason,id planId,todoId,status,minutes*60000 durationMs,valid verified
    FROM plans WHERE $planRange AND $condition''';
  String _focusEntries(String condition) =>
      '''SELECT id,'focus' kind,ownerTitle title,start,end,
    CASE WHEN valid=1 THEN seconds ELSE 0 END seconds,
    CASE WHEN valid=0 THEN CASE WHEN seconds IS NULL THEN '旧记录时长待核对' ELSE '记录时长、时间、状态或同步冲突待核对' END
      WHEN category='attribution' THEN '归属待核对'
      WHEN category='unlinked' THEN '未关联规划' ELSE '已关联规划' END ||
      CASE WHEN historical=1 THEN ' · 历史待办已删除或不存在，保留标题快照' ELSE '' END reason,
    ownerPlan planId,ownerId todoId,NULL status,CASE WHEN valid=1 THEN seconds*1000 ELSE 0 END durationMs,valid verified FROM focus WHERE $condition''';
  String entries(PlanReviewFilter filter) => switch (filter) {
    PlanReviewFilter.plans => _planEntries('valid=1 AND status NOT IN (3,7)'),
    PlanReviewFilter.ended => _planEntries(
      'valid=1 AND status NOT IN (3,7) AND end<=$instant',
    ),
    PlanReviewFilter.missed => _planEntries(
      'valid=1 AND status=6 AND end<=$instant',
    ),
    PlanReviewFilter.focus => _focusEntries('valid=1'),
    PlanReviewFilter.linked => _focusEntries("valid=1 AND category='linked'"),
    PlanReviewFilter.unlinked => _focusEntries(
      "valid=1 AND category='unlinked'",
    ),
    PlanReviewFilter.attribution => _focusEntries(
      "valid=1 AND category='attribution'",
    ),
    PlanReviewFilter.logs =>
      '''SELECT id,'log' kind,title,start,end,(MIN(end,$hi)-MAX(start,$lo))/1000 seconds,
      '日志记录时长，可与其他记录重叠' reason,NULL planId,NULL todoId,NULL status,MIN(end,$hi)-MAX(start,$lo) durationMs,1 verified FROM logs WHERE valid=1 AND end>$lo''',
    PlanReviewFilter.issues =>
      '''${_planEntries('valid=0 OR (valid=1 AND status IN (0,2,4,5) AND end<=$instant) OR (valid=1 AND status=6 AND end>$instant)', reason: "'规划状态、时长或同步冲突待核对'")}
      UNION ALL ${_focusEntries("valid=0 OR category='attribution'")}
      UNION ALL SELECT id,'log' kind,title,start,end,0 seconds,'日志时间或同步冲突待核对' reason,NULL planId,NULL todoId,NULL status,0 durationMs,0 verified FROM logs WHERE valid=0''',
  };

  String get dayAggregate {
    final days = <String>[];
    for (
      var d = start;
      d.isBefore(end);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final a = d.millisecondsSinceEpoch,
          b = DateTime(d.year, d.month, d.day + 1).millisecondsSinceEpoch;
      days.add('SELECT $a start, $b end');
    }
    return '''SELECT d.start,
      COALESCE((SELECT SUM(p.minutes*60) FROM plans p WHERE p.start>=d.start AND p.start<d.end AND p.valid=1 AND p.status NOT IN (3,7)),0) planned,
      COALESCE((SELECT SUM(f.seconds) FROM focus f WHERE f.start>=d.start AND f.start<d.end AND f.valid=1),0) actual
      FROM (${days.join(' UNION ALL ')}) d ORDER BY d.start''';
  }
}
