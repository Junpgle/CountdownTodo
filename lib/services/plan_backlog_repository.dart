import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../models/plan_availability.dart';
import 'conflict_visibility_service.dart';
import 'database_helper.dart';
import 'plan_todo_guard.dart';

class PlanBacklogRow {
  factory PlanBacklogRow(Map<String, Object?> row, bool paused) {
    final todo = TodoItem.fromSql(row)..id = row['uuid'] as String;
    return PlanBacklogRow._(
      todo: todo,
      planCount: (row['plan_count'] as num).toInt(),
      nextStart: row['next_start'] as int?,
      nextEnd: row['next_end'] as int?,
      needsReview: row['bad'] == 1 ||
          ConflictVisibilityService.blocksTodoPlanning(todo),
      focusing: row['focused'] == 1,
      legacy: row['legacy'] == 1,
      sortGroup: row['sort_group'] as int,
      sortDue: row['sort_due'] as int,
      paused: paused,
    );
  }

  const PlanBacklogRow._({
    required this.todo,
    required this.planCount,
    required this.nextStart,
    required this.nextEnd,
    required this.needsReview,
    required this.focusing,
    required this.legacy,
    required this.sortGroup,
    required this.sortDue,
    required this.paused,
  });

  final TodoItem todo;
  String get id => todo.id;
  final int planCount, sortGroup, sortDue;
  final int? nextStart, nextEnd;
  final bool needsReview, focusing, paused, legacy;
  bool get arranged => planCount > 0 || focusing || legacy;
}

class PlanBacklogCursor {
  const PlanBacklogCursor(this.fingerprint, this.group, this.due, this.id);
  final String fingerprint, id;
  final int group, due;
}

class PlanBacklogPage {
  const PlanBacklogPage({
    required this.rows,
    required this.total,
    required this.groups,
    required this.identity,
    required this.nextBoundary,
    this.next,
    this.restarted = false,
  });
  final List<PlanBacklogRow> rows;
  final int total;
  final List<TodoGroup> groups;
  final PlanTodoIdentity identity;
  final DateTime nextBoundary;
  final PlanBacklogCursor? next;
  final bool restarted;
}

/// One SQLite snapshot, sparse projection, keyset pagination after series selection.
/// No business writes, migrations, calendar reads or estimation work.
class PlanBacklogRepository {
  const PlanBacklogRepository({
    this.clock,
    this.databaseOverride,
    this.onQuery,
  });
  final DateTime Function()? clock;
  final Database? databaseOverride;
  final void Function(String sql)? onQuery;
  Future<List<Map<String, Object?>>> _query(
    DatabaseExecutor db,
    String sql, [
    List<Object?>? args,
  ]) {
    onQuery?.call(sql);
    return db.rawQuery(sql, args);
  }

  DateTime get now => clock?.call() ?? DateTime.now();

  Future<PlanBacklogPage> read(
    String username,
    DateTime target, {
    bool scheduled = false,
    String search = '',
    String? folder,
    PlanBacklogCursor? cursor,
  }) async {
    final identity = await PlanTodoIdentity.capture(username);
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('migration_marker_${username}_v4') ?? false) &&
        ((prefs.getStringList('user_todos_$username') ?? []).isNotEmpty ||
            (prefs.getStringList('user_todos') ?? []).isNotEmpty)) {
      throw const PlanAvailabilityException('待办存储尚未初始化，请返回首页加载后重试');
    }
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final instant = now;
    final day = DateTime(target.year, target.month, target.day);
    final tomorrow = DateTime(day.year, day.month, day.day + 1);
    final midnight = DateTime(instant.year, instant.month, instant.day + 1);
    final ms = instant.millisecondsSinceEpoch;
    final escaped = search
        .trim()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final page = await db.transaction((txn) async {
      final focusIds = await PlanTodoGuard.focusIds(
        txn,
        identity,
        tolerateAmbiguous: true,
      );
      var focusReview = false;
      try {
        await PlanTodoGuard.focusIds(txn, identity);
      } on PlanAvailabilityException {
        focusReview = true;
      }
      final run = await PlanTodoGuard.runState(identity);
      final focused = focusIds.toList()..sort();
      final focusSql = focused.isEmpty
          ? '0'
          : "r.uuid IN (${List.filled(focused.length, '?').join(',')})";
      // Match the picker: same target day > active anchor > latest past > earliest
      // future. UUID gives the existing first-in-input tie rule a stable input.
      final sql =
          '''WITH eligible AS (
        SELECT t.uuid,t.content,
          CASE WHEN EXISTS (SELECT 1 FROM todo_groups g WHERE g.uuid=t.group_id AND COALESCE(g.is_deleted,0)=0)
            THEN t.group_id ELSE NULL END AS group_id,
          CASE WHEN LENGTH(t.due_date)>0 AND t.due_date NOT GLOB '*[^0-9]*'
            THEN CAST(t.due_date AS INTEGER)
            ELSE CAST(ROUND((julianday(t.due_date)-2440587.5)*86400000) AS INTEGER) END AS due_date,
          t.created_date,t.created_at,
          t.recurrence,t.recurrence_series_id,t.is_all_day,t.has_conflict,
          t.conflict_data,
          COALESCE(t.created_date,t.created_at,0) AS business_start,
          CASE WHEN COALESCE(t.created_date,t.created_at,0)>=? AND COALESCE(t.created_date,t.created_at,0)<?
            THEN CASE WHEN COALESCE(t.recurrence,0)<>0 THEN 0 ELSE 1 END
            WHEN COALESCE(t.recurrence,0)<>0 THEN 2
            WHEN COALESCE(t.created_date,t.created_at,0)<? THEN 3 ELSE 4 END AS priority
        FROM todos t LEFT JOIN todo_completions c ON c.todo_uuid=t.uuid AND c.user_id=?
        WHERE COALESCE(t.is_deleted,0)=0 AND COALESCE(${PlanTodoGuard.completionSql('t', 'c')},0)=0
          AND LENGTH(TRIM(t.uuid))>0 AND LENGTH(TRIM(t.content))>0
      ), representatives AS (
        SELECT e.* FROM eligible e WHERE COALESCE(e.recurrence_series_id,'')='' OR NOT EXISTS (
          SELECT 1 FROM eligible b WHERE b.recurrence_series_id=e.recurrence_series_id AND (
            b.priority<e.priority OR (b.priority=e.priority AND (
              (e.priority=3 AND b.business_start>e.business_start) OR
              (e.priority=4 AND b.business_start<e.business_start) OR
              ((e.priority IN (0,1,2) OR b.business_start=e.business_start) AND b.uuid<e.uuid)))))
      ), plans AS (
        SELECT todo_uuid,COUNT(*) AS plan_count,MIN(start_time) AS next_start,
          MIN(end_time) AS boundary FROM todo_plan_blocks
        WHERE COALESCE(is_deleted,0)=0 AND status IN (0,2,4,5)
          AND typeof(start_time)='integer' AND typeof(end_time)='integer' AND start_time>0 AND end_time<=8640000000000000 AND end_time>start_time AND end_time>?
        GROUP BY todo_uuid
      ), classified AS (
        SELECT r.*,COALESCE(p.plan_count,0) AS plan_count,p.next_start,
          (SELECT end_time FROM todo_plan_blocks x WHERE x.todo_uuid=r.uuid
            AND COALESCE(x.is_deleted,0)=0 AND x.status IN (0,2,4,5)
            AND x.start_time>0 AND x.end_time>x.start_time AND x.end_time>?
            ORDER BY x.start_time,x.uuid LIMIT 1) AS next_end,
          CASE WHEN $focusSql THEN 1 ELSE 0 END AS focused,
          CASE WHEN ${focusReview ? focusSql : '0'} OR EXISTS (SELECT 1 FROM todo_plan_blocks x WHERE x.todo_uuid=r.uuid
            AND COALESCE(x.is_deleted,0)=0 AND (x.status IS NULL OR x.status NOT IN (0,1,2,3,4,5,6,7)
              OR typeof(x.start_time)<>'integer' OR typeof(x.end_time)<>'integer' OR x.start_time<=0 OR x.end_time>8640000000000000 OR x.end_time<=x.start_time)) THEN 1 ELSE 0 END AS bad,
          CASE WHEN COALESCE(p.plan_count,0)=0 AND COALESCE(r.is_all_day,0)=0
            AND r.created_date>0 AND r.created_date<>r.created_at AND r.due_date>r.created_date AND r.due_date>?
            AND NOT EXISTS (SELECT 1 FROM todo_plan_blocks x WHERE x.todo_uuid=r.uuid
              AND COALESCE(x.is_deleted,0)=0
              AND x.start_time < CAST(strftime('%s',r.created_date/1000,'unixepoch','localtime','start of day','+1 day','utc') AS INTEGER)*1000
              AND x.end_time > CAST(strftime('%s',r.created_date/1000,'unixepoch','localtime','start of day','utc') AS INTEGER)*1000)
            AND date(r.created_date/1000,'unixepoch','localtime')=date(r.due_date/1000,'unixepoch','localtime')
            AND NOT (strftime('%H:%M:%S',r.created_date/1000,'unixepoch','localtime')='00:00:00' AND r.created_date%1000=0
              AND strftime('%H:%M',r.due_date/1000,'unixepoch','localtime')='23:59')
            THEN 1 ELSE 0 END AS legacy,
          CASE WHEN r.due_date IS NULL OR r.due_date<=0 THEN 3
            WHEN r.due_date<? THEN 0 WHEN r.due_date<? THEN 1 ELSE 2 END AS sort_group,
          COALESCE(r.due_date,0) AS sort_due
        FROM representatives r LEFT JOIN plans p ON p.todo_uuid=r.uuid
      ), filtered AS (SELECT * FROM classified WHERE
        (plan_count>0 OR focused=1 OR bad=1 OR legacy=1)=?
        AND content LIKE ? ESCAPE '\\' ${folder == null ? '' : 'AND COALESCE(group_id,\'\')=?'})''';
      final args = <Object?>[
        day.millisecondsSinceEpoch,
        tomorrow.millisecondsSinceEpoch,
        day.millisecondsSinceEpoch,
        identity.userId,
        ms,
        ms,
        ...focused,
        if (focusReview) ...focused,
        ms,
        day.millisecondsSinceEpoch,
        tomorrow.millisecondsSinceEpoch,
        scheduled ? 1 : 0,
        '%$escaped%',
        ?folder,
      ];
      // Business writes advance version/updated_at. Stream bounded metadata
      // batches rather than materializing titles/remarks from the entire DB.
      final revision = await _revision(txn, identity);
      final boundariesRow = await _query(
        txn,
        """SELECT MIN(end_time) boundary
        FROM todo_plan_blocks WHERE COALESCE(is_deleted,0)=0 AND status IN (0,2,4,5)
        AND typeof(end_time)='integer' AND end_time>?""",
        [ms],
      );
      final count = await _query(
        txn,
        '$sql SELECT COUNT(*) n, (SELECT MIN(due_date) FROM classified WHERE legacy=1) legacy_boundary FROM filtered',
        args,
      );
      final fingerprint = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                username,
                identity.userId,
                day.millisecondsSinceEpoch,
                search,
                folder,
                scheduled,
                revision,
                boundariesRow.single['boundary'],
                count.single['legacy_boundary'],
                run?.toJson(),
                DateTime(
                  instant.year,
                  instant.month,
                  instant.day,
                ).millisecondsSinceEpoch,
              ]),
            ),
          )
          .toString();
      final restarted = cursor != null && cursor.fingerprint != fingerprint;
      final validCursor = restarted ? null : cursor;
      final rows = await _query(
        txn,
        '''$sql SELECT * FROM filtered
        ${validCursor == null ? '' : 'WHERE sort_group>? OR (sort_group=? AND (sort_due>? OR (sort_due=? AND uuid>?)))'}
        ORDER BY sort_group,sort_due,uuid LIMIT 51''',
        [
          ...args,
          if (validCursor != null) ...[
            validCursor.group,
            validCursor.group,
            validCursor.due,
            validCursor.due,
            validCursor.id,
          ],
        ],
      );
      final items = rows
          .take(50)
          .map((r) => PlanBacklogRow(r, run?.isPaused ?? false))
          .toList();
      final groups = await _query(
        txn,
        'SELECT uuid,name FROM todo_groups WHERE COALESCE(is_deleted,0)=0 ORDER BY name,uuid',
      );
      final boundaries = [
        boundariesRow.single['boundary'] as int?,
        count.single['legacy_boundary'] as int?,
        ...items
            .map((row) => row.todo.effectiveDueAt)
            .whereType<DateTime>()
            .map((deadline) => deadline.add(const Duration(milliseconds: 1)))
            .where((boundary) => boundary.isAfter(instant))
            .map((deadline) => deadline.millisecondsSinceEpoch),
        ...items
            .where((row) => row.legacy)
            .map((row) => row.todo.dueDate?.millisecondsSinceEpoch),
      ].whereType<int>().toList()..sort();
      final boundary = boundaries.firstOrNull;
      return PlanBacklogPage(
        rows: List.unmodifiable(items),
        total: count.single['n'] as int,
        identity: identity,
        groups: groups.map(TodoGroup.fromSql).toList(),
        restarted: restarted,
        nextBoundary:
            boundary != null && boundary < midnight.millisecondsSinceEpoch
            ? DateTime.fromMillisecondsSinceEpoch(boundary)
            : midnight,
        next: rows.length > 50
            ? PlanBacklogCursor(
                fingerprint,
                items.last.sortGroup,
                items.last.sortDue,
                items.last.id,
              )
            : null,
      );
    });
    await identity.check();
    return page;
  }

  Future<String> _revision(
    DatabaseExecutor db,
    PlanTodoIdentity identity,
  ) async {
    final digest = _DigestSink();
    final sink = sha256.startChunkedConversion(digest);
    for (final (table, key, projection, where, args) in [
      (
        'todos',
        'uuid',
        'uuid,version,updated_at,is_completed,is_deleted,has_conflict,collab_type,group_id,due_date,created_date,created_at,is_all_day,recurrence,recurrence_series_id,length(content) AS title_length,substr(content,1,128) AS title_prefix',
        '1=1',
        <Object?>[],
      ),
      (
        'todo_plan_blocks',
        'uuid',
        'uuid,todo_uuid,version,updated_at,start_time,end_time,status,is_deleted',
        '1=1',
        <Object?>[],
      ),
      (
        'todo_completions',
        'todo_uuid',
        'todo_uuid,is_completed,updated_at',
        'user_id=?',
        <Object?>[identity.userId],
      ),
      (
        'todo_groups',
        'uuid',
        'uuid,name,is_deleted,version,updated_at',
        '1=1',
        <Object?>[],
      ),
    ]) {
      sink.add(utf8.encode(table));
      String? after;
      while (true) {
        final seek = after == null ? '' : 'AND $key>? ';
        final rows = await _query(
          db,
          'SELECT $projection FROM $table WHERE $where '
          'AND $key IS NOT NULL $seek'
          'ORDER BY $key LIMIT 200',
          [...args, ?after],
        );
        for (final row in rows) {
          sink.add(utf8.encode(jsonEncode(row)));
        }
        if (rows.length < 200) break;
        after = rows.last[key] as String;
      }
    }
    sink.close();
    return digest.value!.toString();
  }

  Future<(TodoItem, PlanBacklogSaveContext)> prepare(
    PlanTodoIdentity identity,
    String id,
  ) async {
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(identity.username);
    return db.transaction((txn) async {
      await PlanTodoGuard.validate(txn, identity, id);
      final todo = await PlanTodoGuard.read(txn, identity, id);
      final fingerprint = await PlanTodoGuard.arrangements(txn, id, now);
      return (todo, PlanBacklogSaveContext(identity, id, fingerprint));
    });
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
