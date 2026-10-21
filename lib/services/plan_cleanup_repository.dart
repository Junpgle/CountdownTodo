import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'conflict_visibility_service.dart';
import '../models/plan_availability.dart';
import '../models/plan_cleanup.dart';
import '../storage_service.dart';
import 'database_helper.dart';
import 'plan_todo_guard.dart';

class PlanCleanupCursor {
  const PlanCleanupCursor(this.fingerprint, this.start, this.id);
  final String fingerprint, id;
  final int start;
}

class PlanCleanupTodo {
  PlanCleanupTodo(this.values);
  final Map<String, Object?> values;
  String get id => values['uuid'] as String;
  String get title => values['content'] as String;
  int get count => values['n'] as int;
  int get eligible => values['eligible'] as int;
  int get nextStart => values['next_start'] as int;
  String get reason => values['reason'] as String? ?? '';
}

class PlanCleanupItem {
  PlanCleanupItem(Map<String, Object?> values)
    : reason = values['reason'] as String? ?? '',
      row = Map.unmodifiable({...values}..remove('reason'));
  final Map<String, Object?> row;
  final String reason;
  String get id => row['uuid']?.toString() ?? '';
  String get key => id.isNotEmpty ? id : 'legacy-row-${row['id'] ?? ''}';
  bool get eligible => reason.isEmpty;
  int get start => row['start_time'] as int? ?? 0;
  int get end => row['end_time'] as int? ?? 0;
  int get minutes =>
      row['planned_minutes'] is int ? row['planned_minutes'] as int : 0;
}

class PlanCleanupPage {
  const PlanCleanupPage({
    required this.identity,
    required this.rows,
    required this.total,
    required this.groups,
    required this.nextBoundary,
    required this.restarted,
    this.next,
  });
  final PlanTodoIdentity identity;
  final List<PlanCleanupTodo> rows;
  final int total;
  final List<TodoGroup> groups;
  final DateTime? nextBoundary;
  final bool restarted;
  final PlanCleanupCursor? next;
}

class PlanCleanupSnapshot {
  const PlanCleanupSnapshot({
    required this.identity,
    required this.todo,
    required this.rows,
    required this.total,
    required this.eligible,
    required this.fingerprint,
    required this.blockedReason,
    required this.nextBoundary,
    required this.restarted,
    this.next,
  });
  final PlanTodoIdentity identity;
  final TodoItem todo;
  final List<PlanCleanupItem> rows;
  final int total, eligible;
  final String fingerprint, blockedReason;
  final DateTime? nextBoundary;
  final bool restarted;
  final PlanCleanupCursor? next;
  PlanCleanupRequest select(Set<String> ids, DateTime now) {
    final chosen = rows.where((r) => ids.contains(r.id)).toList();
    if (blockedReason.isNotEmpty ||
        ids.isEmpty ||
        ids.length > 50 ||
        chosen.length != ids.length ||
        chosen.any((r) => !r.eligible)) {
      throw const PlanAvailabilityException('请选择已展示且可处理的规划，最多50段');
    }
    return PlanCleanupRequest(
      identity: identity,
      todoId: todo.id,
      fingerprint: fingerprint,
      rows: chosen.map((r) => r.row).toList(),
      cancelledAt: now.millisecondsSinceEpoch,
    );
  }
}

/// Read-only sparse pages. No facade reads that silently migrate legacy data.
class PlanCleanupRepository {
  const PlanCleanupRepository({this.databaseOverride, this.clock});
  final Database? databaseOverride;
  final DateTime Function()? clock;
  static final _tokens = Expando<int>();
  static int _nextToken = 0;
  DateTime get now => clock?.call() ?? DateTime.now();
  Future<Database> _database(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final pendingTodos =
        !(prefs.getBool('migration_marker_${username}_v4') ?? false) &&
        ((prefs.getStringList('user_todos_$username') ?? []).isNotEmpty ||
            (prefs.getStringList('user_todos') ?? []).isNotEmpty);
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final legacy = ['pomodoro_records_$username', 'pomodoro_records'].any((
      key,
    ) {
      final raw = prefs.getString(key)?.trim();
      return raw != null && raw.isNotEmpty && raw != '[]';
    });
    if (pendingTodos ||
        (legacy &&
            (Sqflite.firstIntValue(
                      await db.rawQuery(
                        'SELECT COUNT(*) FROM pomodoro_records',
                      ),
                    ) ??
                    0) ==
                0)) {
      throw const PlanAvailabilityException('历史存储尚未初始化，请返回首页或专注页加载后重试');
    }
    return db;
  }

  Future<_CleanupSql> _sql(
    DatabaseExecutor db,
    PlanTodoIdentity identity,
  ) async {
    await identity.check();
    final p = (await db.rawQuery('PRAGMA table_info(todo_plan_blocks)'))
        .any((r) => r['name'] == 'has_conflict');
    final r = (await db.rawQuery('PRAGMA table_info(pomodoro_records)'))
        .any((r) => r['name'] == 'has_conflict');
    var focusReason = '';
    Set<String> focusIds = {};
    try {
      focusIds = await PlanTodoGuard.focusIds(db, identity);
    } on PlanAvailabilityException catch (e) {
      focusReason = e.message;
    }
    await identity.check();
    // Keep malformed persisted state as a visible read failure. The focused
    // todo set above is the only run-state value needed for these fingerprints.
    await PlanTodoGuard.runState(identity);
    return _CleanupSql(p, r, focusIds, focusReason);
  }

  static String _escaped(String value) => value
      .trim()
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  Future<PlanCleanupPage> read(
    String username, {
    String search = '',
    String? folder,
    PlanCleanupCursor? cursor,
  }) async {
    final identity = await PlanTodoIdentity.capture(username),
        db = await _database(username);
    final instant = now;
    final page = await db.transaction((tx) async {
      final rules = await _sql(tx, identity);
      final sql =
          '''WITH classified AS (
        SELECT t.uuid,t.content,
          CASE WHEN EXISTS(SELECT 1 FROM todo_groups g WHERE g.uuid=t.group_id AND COALESCE(g.is_deleted,0)=0)
            THEN t.group_id ELSE '' END AS folder,
          p.start_time,${rules.reason} AS reason
        FROM todos t LEFT JOIN todo_completions c ON c.todo_uuid=t.uuid AND c.user_id=?
        JOIN todo_plan_blocks p ON p.todo_uuid=t.uuid
        WHERE COALESCE(t.is_deleted,0)=0 AND ${PlanTodoGuard.completionSql('t', 'c')}=1
          AND LENGTH(TRIM(t.uuid))>0 AND LENGTH(TRIM(t.content))>0
          AND ${_CleanupSql.remaining}
      ), grouped AS (SELECT uuid,content,folder,COUNT(*) n,MIN(start_time) next_start,
        SUM(CASE WHEN reason='' THEN 1 ELSE 0 END) eligible,
        CASE WHEN SUM(CASE WHEN reason='' THEN 1 ELSE 0 END)>0 THEN '' ELSE MIN(reason) END reason
        FROM classified GROUP BY uuid,content,folder), filtered AS (
        SELECT * FROM grouped WHERE content LIKE ? ESCAPE '\\' ${folder == null ? '' : 'AND folder=?'})''';
      final args = <Object?>[
        instant.millisecondsSinceEpoch,
        identity.userId,
        instant.millisecondsSinceEpoch,
        '%${_escaped(search)}%',
        ?folder,
      ];
      final total =
          Sqflite.firstIntValue(
            await tx.rawQuery('$sql SELECT COUNT(*) FROM filtered', args),
          ) ??
          0;
      final fingerprintBoundary = await _boundary(
        tx,
        instant,
        identity: identity,
        search: search,
        folder: folder,
      );
      _tokens[db] ??= ++_nextToken;
      final fingerprint = _hash([
        _tokens[db],
        username,
        identity.userId,
        search,
        folder,
        await tx.rawQuery('SELECT total_changes() AS n'),
        await tx.rawQuery('PRAGMA data_version'),
        [rules.focusIds.toList()..sort(), rules.focusReason],
        fingerprintBoundary?.millisecondsSinceEpoch,
        total,
      ]);
      final restarted = cursor != null && cursor.fingerprint != fingerprint;
      final seek = restarted ? null : cursor;
      final rows = await tx.rawQuery(
        '''$sql SELECT * FROM filtered
        ${seek == null ? '' : 'WHERE next_start>? OR (next_start=? AND uuid>?)'}
        ORDER BY next_start,uuid LIMIT 51''',
        [
          ...args,
          if (seek != null) ...[seek.start, seek.start, seek.id],
        ],
      );
      final items = rows.take(50).map(PlanCleanupTodo.new).toList();
      final nextBoundary = await _boundary(
        tx,
        instant,
        todoIds: items.map((item) => item.id),
      );
      final groups = await tx.rawQuery(
        'SELECT uuid,name FROM todo_groups WHERE COALESCE(is_deleted,0)=0 ORDER BY name,uuid',
      );
      await identity.check();
      return PlanCleanupPage(
        identity: identity,
        rows: items,
        total: total,
        groups: groups.map(TodoGroup.fromSql).toList(),
        nextBoundary: nextBoundary,
        restarted: restarted,
        next: rows.length > 50
            ? PlanCleanupCursor(
                fingerprint,
                items.last.nextStart,
                items.last.id,
              )
            : null,
      );
    });
    await identity.check();
    return page;
  }

  Future<PlanCleanupSnapshot> detail(
    String username,
    String todoId, {
    PlanCleanupCursor? cursor,
  }) async {
    final identity = await PlanTodoIdentity.capture(username),
        db = await _database(username);
    final instant = now;
    final snapshot = await db.transaction((tx) async {
      final rules = await _sql(tx, identity);
      final todo = await PlanTodoGuard.read(
        tx,
        identity,
        todoId,
        requireEligible: false,
      );
      final blocked = _blocked(todo, rules);
      final fingerprint = await _fingerprint(tx, identity, todoId, rules);
      final restarted = cursor != null && cursor.fingerprint != fingerprint;
      final seek = restarted ? null : cursor;
      final from = '''FROM todo_plan_blocks p JOIN todos t ON t.uuid=p.todo_uuid
        WHERE p.todo_uuid=? AND ${_CleanupSql.remaining}''';
      final args = [
        instant.millisecondsSinceEpoch,
        todoId,
        instant.millisecondsSinceEpoch,
      ];
      final count = (await tx.rawQuery(
        '''SELECT COUNT(*) n,
        COALESCE(SUM(CASE WHEN ${rules.reason}='' THEN 1 ELSE 0 END),0) eligible $from''',
        args,
      )).single;
      final rows = await tx.rawQuery(
        '''SELECT p.*,${rules.reason} AS reason $from
        ${seek == null ? '' : 'AND (p.start_time>? OR (p.start_time=? AND p.uuid>?))'}
        ORDER BY p.start_time,p.uuid LIMIT 51''',
        [
          ...args,
          if (seek != null) ...[seek.start, seek.start, seek.id],
        ],
      );
      final items = rows.take(50).map(PlanCleanupItem.new).toList();
      await identity.check();
      return PlanCleanupSnapshot(
        identity: identity,
        todo: todo,
        rows: items,
        total: count['n'] as int,
        eligible: blocked.isEmpty ? count['eligible'] as int : 0,
        fingerprint: fingerprint,
        blockedReason: blocked,
        restarted: restarted,
        nextBoundary: await _boundary(tx, instant, todoId: todoId),
        next: rows.length > 50
            ? PlanCleanupCursor(fingerprint, items.last.start, items.last.id)
            : null,
      );
    });
    await identity.check();
    return snapshot;
  }

  static String _blocked(TodoItem todo, _CleanupSql rules) {
    if (todo.isDeleted || !todo.isDone) return '待办已删除或不再是已完成状态，请查看最新待办';
    if (ConflictVisibilityService.blocksTodoPlanning(todo) ||
        todo.id.trim().isEmpty ||
        todo.title.trim().isEmpty) {
      return '待办存在冲突或内容无效，请先核对';
    }
    if ((todo.teamUuid?.trim() ?? '').isNotEmpty || todo.collabType != 0) {
      return '关联团队待办的剩余规划暂不支持批量处理，请逐条核对';
    }
    if (rules.focusReason.isNotEmpty) return rules.focusReason;
    if (rules.focusIds.contains(todo.id)) return '此待办正在专注或已暂停，请先查看当前专注';
    return '';
  }

  Future<List<TodoPlanBlock>> cancel(
    PlanCleanupRequest request, {
    bool sync = true,
  }) async {
    await request.identity.check();
    // Ensure pending legacy storage cannot turn a missing record into no evidence.
    await _database(request.identity.username);
    return StorageService.cancelPlanBlocksReviewed(
      request.identity.username,
      request,
      sync: sync,
      validate: (tx, retry) async {
        final rules = await _sql(tx, request.identity);
        final todo = await PlanTodoGuard.read(
          tx,
          request.identity,
          request.todoId,
          requireEligible: false,
        );
        final blocked = _blocked(todo, rules);
        if (blocked.isNotEmpty) throw PlanAvailabilityException(blocked);
        if (await _fingerprint(
              tx,
              request.identity,
              request.todoId,
              rules,
              normalize: retry ? request : null,
            ) !=
            request.fingerprint) {
          throw const PlanAvailabilityException('安排或投入已变化，请核对后再试');
        }
        // For a retry, reconstruct only this request's original status. All other
        // evidence and time guards still apply to the latest database snapshot.
        final ids = request.ids;
        final result = await tx.rawQuery(
          '''SELECT p.uuid,${rules.reasonForRetry(retry ? ids : [])} reason
          FROM todo_plan_blocks p JOIN todos t ON t.uuid=p.todo_uuid
          WHERE p.uuid IN (${List.filled(ids.length, '?').join(',')})''',
          [now.millisecondsSinceEpoch, if (retry) ...ids, ...ids],
        );
        if (result.length != ids.length ||
            result.any((r) => r['reason'] != '')) {
          throw const PlanAvailabilityException('规划已开始、存在投入或状态变化，请核对后再试');
        }
        await request.identity.check();
      },
    );
  }

  Future<DateTime?> _boundary(
    DatabaseExecutor tx,
    DateTime instant, {
    String? todoId,
    Iterable<String>? todoIds,
    PlanTodoIdentity? identity,
    String search = '',
    String? folder,
  }) async {
    final ms = instant.millisecondsSinceEpoch;
    if (todoIds != null && todoIds.isEmpty) return null;
    final todoFilter = todoId != null
        ? ' AND todo_uuid=?'
        : todoIds == null
        ? ''
        : ' AND todo_uuid IN (${List.filled(todoIds.length, '?').join(',')})';
    final completedFilter = identity == null
        ? ''
        : ''' AND todo_uuid IN (
        SELECT t.uuid FROM todos t
        LEFT JOIN todo_completions c ON c.todo_uuid=t.uuid AND c.user_id=?
        WHERE COALESCE(t.is_deleted,0)=0
          AND ${PlanTodoGuard.completionSql('t', 'c')}=1
          AND LENGTH(TRIM(t.uuid))>0 AND LENGTH(TRIM(t.content))>0
          AND t.content LIKE ? ESCAPE '\\'
          ${folder == null ? '' : "AND CASE WHEN EXISTS(SELECT 1 FROM todo_groups g WHERE g.uuid=t.group_id AND COALESCE(g.is_deleted,0)=0) THEN t.group_id ELSE '' END=?"}
      )''';
    final scopeArgs = <Object?>[
      ?todoId,
      ...?todoIds,
      if (identity != null) ...[
        identity.userId,
        '%${_escaped(search)}%',
        ?folder,
      ],
    ];
    const remaining = '''COALESCE(is_deleted,0)=0 AND status IN (0,2,4,5)
      AND typeof(start_time)='integer' AND typeof(end_time)='integer'
      AND start_time>0 AND end_time>start_time
      AND end_time<=8640000000000000''';
    final rows = await tx.rawQuery(
      '''SELECT MIN(boundary) n FROM (
      SELECT start_time boundary FROM todo_plan_blocks WHERE $remaining AND start_time>?$todoFilter
      $completedFilter
      UNION ALL SELECT end_time boundary FROM todo_plan_blocks WHERE $remaining AND end_time>?$todoFilter
      $completedFilter)''',
      [ms, ...scopeArgs, ms, ...scopeArgs],
    );
    final value = rows.single['n'];
    return value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
  }

  Future<String> _fingerprint(
    DatabaseExecutor tx,
    PlanTodoIdentity identity,
    String todoId,
    _CleanupSql rules, {
    PlanCleanupRequest? normalize,
  }) async {
    final digest = _CleanupDigest();
    final instant = now.millisecondsSinceEpoch;
    final sink = sha256.startChunkedConversion(digest);
    void add(Object? value) => sink.add(utf8.encode(jsonEncode(value)));
    add([
      identity.username,
      identity.userId,
      rules.focusIds.contains(todoId),
      rules.focusReason,
    ]);
    add(await PlanTodoGuard.projectedRows(tx, identity, todoId));
    final original = {
      for (final row in normalize?.rows ?? <Map<String, Object?>>[])
        row['uuid']: row,
    };
    for (final (table, where, columns) in [
      ('todo_plan_blocks', 'todo_uuid=?', '*'),
      (
        'pomodoro_records',
        '''todo_uuid=? OR plan_block_id IN
        (SELECT uuid FROM todo_plan_blocks WHERE todo_uuid=?) OR EXISTS
        (SELECT 1 FROM todo_plan_blocks p WHERE p.todo_uuid=? AND
        instr(','||COALESCE(p.pomodoro_record_ids,'')||',',','||pomodoro_records.uuid||',')>0)''',
        'uuid,todo_uuid,plan_block_id,start_time,end_time,actual_duration,status,is_deleted,version,updated_at${rules.recordConflict ? ',has_conflict' : ''}',
      ),
    ]) {
      add(table);
      String? after;
      while (true) {
        final rows = await tx.rawQuery(
          'SELECT $columns FROM $table WHERE ($where) AND uuid IS NOT NULL '
          '${after == null ? '' : 'AND uuid>?'} ORDER BY uuid LIMIT 200',
          [
            todoId,
            if (table == 'pomodoro_records') ...[todoId, todoId],
            ?after,
          ],
        );
        for (final row in rows) {
          final old = original[row['uuid']];
          final normalizedRetry =
              table == 'todo_plan_blocks' &&
              old != null &&
              PlanCleanupRequest.sameRow(row, normalize!.cancelledRow(old));
          add(normalizedRetry ? old : row);
          if (table == 'todo_plan_blocks') {
            final start = row['start_time'], end = row['end_time'];
            // A successful cancellation remains an idempotent retry after its
            // original start time passes. Preserve the eligibility boundary
            // state from the reviewed snapshot for only those exact rows.
            add(
              normalizedRetry
                  ? [false, false]
                  : [
                      start is int && start <= instant,
                      end is int && end <= instant,
                    ],
            );
          }
        }
        if (rows.length < 200) break;
        after = rows.last['uuid'] as String;
      }
    }
    sink.close();
    return digest.value!.toString();
  }

  static String _hash(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

class _CleanupDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _CleanupSql {
  const _CleanupSql(
    this.planConflict,
    this.recordConflict,
    this.focusIds,
    this.focusReason,
  );
  final bool planConflict, recordConflict;
  final Set<String> focusIds;
  final String focusReason;
  static const remaining =
      '''COALESCE(p.is_deleted,0)=0 AND p.status IN (0,2,4,5)
    AND typeof(p.start_time)='integer' AND typeof(p.end_time)='integer'
    AND p.start_time>0 AND p.end_time>p.start_time AND p.end_time<=8640000000000000 AND p.end_time>?''';

  String get reason => reasonForRetry([]);
  String reasonForRetry(List<String> retryIds) {
    // IDs have already been bound and checked against the request by storage;
    // no values are interpolated here. Retry allows only the cancelled status.
    final counterOverflow = retryIds.isEmpty
        ? 'p.version>=9223372036854775807 OR p.updated_at>=9223372036854775807'
        : '0';
    final status = retryIds.isEmpty
        ? 'p.status NOT IN (0,2,4)'
        : 'p.status NOT IN (0,2,3,4)';
    final started = retryIds.isEmpty
        ? 'p.start_time<=?'
        : 'p.start_time<=? AND p.uuid NOT IN (${List.filled(retryIds.length, '?').join(',')})';
    final focus = focusIds
        .map((id) => "'${id.replaceAll("'", "''")}'")
        .join(',');
    return '''CASE
      WHEN COALESCE(t.is_deleted,0)<>0 THEN '待办需核对'
      WHEN LENGTH(TRIM(COALESCE(t.team_uuid,'')))>0 OR COALESCE(t.collab_type,0)<>0 THEN '关联团队待办的剩余规划暂不支持批量处理，请逐条核对'
      WHEN ${focusReason.isNotEmpty ? '1' : '0'} ${focus.isEmpty ? '' : 'OR t.uuid IN ($focus)'} THEN '专注状态需核对，请查看当前专注'
      WHEN COALESCE(p.is_deleted,0)<>0 ${planConflict ? 'OR COALESCE(p.has_conflict,0)<>0' : ''} THEN '规划删除或冲突待核对'
      WHEN LENGTH(TRIM(COALESCE(p.uuid,'')))=0 OR typeof(p.start_time)<>'integer' OR typeof(p.end_time)<>'integer' OR p.start_time<=0
        OR p.end_time>8640000000000000 OR p.end_time<=p.start_time
        OR typeof(p.planned_minutes)<>'integer' OR p.planned_minutes<=0
        OR p.end_time-p.start_time<>p.planned_minutes*60000
        OR typeof(p.version)<>'integer' OR p.version<1
        OR typeof(p.updated_at)<>'integer' OR ($counterOverflow)
        THEN '规划时间或版本需核对'
      WHEN $started THEN '规划已开始，仅供查看'
      WHEN $status THEN '规划状态不可批量取消'
      WHEN typeof(p.actual_focus_seconds)<>'integer' OR p.actual_focus_seconds<>0
        OR LENGTH(TRIM(COALESCE(p.pomodoro_record_ids,'')))>0 THEN '已有投入或关联记录，请逐条核对'
      WHEN EXISTS (SELECT 1 FROM pomodoro_records r WHERE r.plan_block_id=p.uuid
        OR instr(','||COALESCE(p.pomodoro_record_ids,'')||',',','||r.uuid||',')>0
        OR (r.todo_uuid=p.todo_uuid AND ((COALESCE(r.plan_block_id,'')<>'' AND NOT EXISTS
          (SELECT 1 FROM todo_plan_blocks owned WHERE owned.uuid=r.plan_block_id AND owned.todo_uuid=r.todo_uuid))
          OR (${recordConflict ? 'COALESCE(r.has_conflict,0)<>0 OR' : ''}
          typeof(r.start_time)<>'integer' OR typeof(r.end_time)<>'integer' OR r.end_time<=r.start_time
          OR typeof(r.actual_duration)<>'integer' OR r.actual_duration<0
          OR r.status IS NULL OR r.status NOT IN ('completed','interrupted','switched'))
          OR (COALESCE(r.plan_block_id,'')='' AND r.start_time<p.end_time AND r.end_time>p.start_time))))
        THEN '已有投入或归属待核对'
      ELSE '' END''';
  }
}
