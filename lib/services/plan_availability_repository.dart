import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../course_import/course_schedule_semantics.dart';
import '../models.dart';
import '../models/plan_availability.dart';
import '../storage_service.dart';
import 'course_calendar_adjustment_service.dart';
import 'database_helper.dart';
import 'device_calendar_read_service.dart';
import 'plan_availability_service.dart';

typedef PlanAvailabilityLoader = Future<PlanAvailabilitySnapshot> Function(
  PlanAvailabilityQuery query, {
  bool forceRefresh,
});

/// Strict, account-scoped reads. A failed source never becomes a free interval.
class PlanAvailabilityRepository {
  const PlanAvailabilityRepository({this.databaseOverride, this.clock});
  final Database? databaseOverride;
  final DateTime Function()? clock;
  DateTime get now => clock?.call() ?? DateTime.now();

  Future<void> _checkAccount(String username) async {
    if ((await StorageService.getLoginSession() ?? 'default') != username) {
      throw const PlanAvailabilityException('账号已切换，请重新打开规划编辑器');
    }
  }

  Future<String> _settingsFingerprint(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final keys =
        prefs
            .getKeys()
            .where(
              (key) => [
                'course_calendar_adjustments_v1',
                StorageService.keySemesters,
                StorageService.keySemesterStart,
              ].any((base) => key == base || key == '${base}_$username'),
            )
            .toList()
          ..sort();
    for (final key in keys.where(
      (key) => key.startsWith('course_calendar_adjustments'),
    )) {
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) throw const FormatException();
          final rules = CourseCalendarAdjustment.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          final transfers = decoded['transfers'];
          if (transfers != null) {
            if (transfers is! List) throw const FormatException();
            for (final transfer in transfers) {
              if (transfer is! Map ||
                  transfer['from_date'] is! String ||
                  transfer['to_date'] is! String) {
                throw const FormatException();
              }
              DateFormat('yyyy-MM-dd')
                  .parseStrict(transfer['from_date'] as String);
              DateFormat('yyyy-MM-dd')
                  .parseStrict(transfer['to_date'] as String);
            }
          }
          for (final date in rules.holidayDates) {
            DateFormat('yyyy-MM-dd').parseStrict(date);
          }
          for (final transfer in rules.transfers) {
            DateFormat('yyyy-MM-dd').parseStrict(transfer.fromDate);
            DateFormat('yyyy-MM-dd').parseStrict(transfer.toDate);
          }
        } catch (_) {
          throw const PlanAvailabilityException('课程日期规则无法解析，请检查设置后重试');
        }
      }
    }
    return jsonEncode({for (final key in keys) key: prefs.get(key)});
  }

  Future<List<Map<String, Object?>>> _rows(
    DatabaseExecutor db,
    String table,
  ) async {
    try {
      return await db.query(table, orderBy: 'uuid ASC');
    } catch (_) {
      final name = switch (table) {
        'courses' => '课程',
        'todos' => '待办',
        'fixed_schedules' => '固定日程',
        _ => '规划块',
      };
      throw PlanAvailabilityException('$name读取失败，请重试');
    }
  }

  Future<_LocalAvailabilityData> _readLocal(
    DatabaseExecutor db, {
    List<CourseItem>? preparedCourses,
    String? expectedCourseFingerprint,
  }) async {
    final courseRows = await _rows(db, 'courses');
    final fingerprint = jsonEncode(courseRows);
    if (expectedCourseFingerprint != null &&
        fingerprint != expectedCourseFingerprint) {
      throw const PlanAvailabilityException('课程已变更，请重新查找时段');
    }
    List<CourseItem> courses;
    try {
      courses =
          preparedCourses ??
          await CourseCalendarAdjustmentService.applyToCourses(
            courseRows
                .map(CourseItem.fromJson)
                .where((course) => !course.isDeleted)
                .toList(),
          );
    } catch (_) {
      throw const PlanAvailabilityException('课程日期规则读取失败，请重试');
    }
    final todoRows = await _rows(db, 'todos');
    final fixedRows = await _rows(db, 'fixed_schedules');
    final planRows = await _rows(db, 'todo_plan_blocks');
    try {
      return _LocalAvailabilityData(
        courses: courses,
        courseFingerprint: fingerprint,
        todos: todoRows.map((row) {
          final todo = TodoItem.fromSql(row);
          // Preserve the storage key for legacy IDs; this read does not migrate.
          todo.id = row['uuid'].toString();
          return todo;
        }).toList(),
        schedules: fixedRows.map(FixedScheduleItem.fromJson).toList(),
        blocks: planRows.map(TodoPlanBlock.fromJson).toList(),
      );
    } catch (_) {
      throw const PlanAvailabilityException('安排数据无法解析，请检查记录后重试');
    }
  }

  PlanAvailabilitySnapshot _snapshot(
    PlanAvailabilityQuery query,
    _LocalAvailabilityData local, {
    List<PlanBusyInterval> external = const [],
    bool included = false,
    String coverage = '已检查课程、固定日程和规划；未计入手机日历',
    String settingsFingerprint = '',
    int calendarRevision = 0,
  }) {
    final todo = local.todos
        .where((item) => item.id == query.todoId)
        .firstOrNull;
    if (todo == null || todo.isDeleted || todo.isDone) {
      throw const PlanAvailabilityException('待办已完成或删除，请重新选择');
    }
    final sources = _daySources(query, local, external: external);
    return PlanAvailabilitySnapshot(
      todo: todo,
      busy: sources.busy,
      coverage: coverage,
      unknownTimes: sources.unknownTimes,
      deviceCalendarIncluded: included,
      courseFingerprint: local.courseFingerprint,
      settingsFingerprint: settingsFingerprint,
      calendarRevision: calendarRevision,
    );
  }

  PlanAvailabilityDaySources _daySources(
    PlanAvailabilityQuery query,
    _LocalAvailabilityData local, {
    List<PlanBusyInterval> external = const [],
  }) {
    final busy = <PlanBusyInterval>[...external];
    final unknown = <String>[];
    final day = DateFormat('yyyy-MM-dd').format(query.dayStart);
    void add(
      DateTime start,
      DateTime end,
      PlanBusySource source,
      String id,
      String title,
      Object record,
    ) {
      if (end.isAfter(start) &&
          end.isAfter(query.dayStart) &&
          start.isBefore(query.dayEnd)) {
        busy.add(
          PlanBusyInterval(
            start,
            end,
            source: source,
            id: id,
            title: title,
            record: record,
          ),
        );
      }
    }

    final courseIds = <String>{};
    for (final course in local.courses) {
      if (course.isDeleted || !courseIds.add(course.uuid)) continue;
      DateTime date;
      try {
        date = DateFormat('yyyy-MM-dd').parseStrict(course.date);
      } catch (_) {
        unknown.add('课程“${course.courseName}”：日期待定');
        continue;
      }
      if (DateFormat('yyyy-MM-dd').format(date) != day) continue;
      if (!CourseScheduleSemantics.hasUsableTime(course)) {
        unknown.add('课程“${course.courseName}”：时间待定');
        continue;
      }
      add(
        DateTime(
          date.year,
          date.month,
          date.day,
          course.startTime ~/ 100,
          course.startTime % 100,
        ),
        DateTime(
          date.year,
          date.month,
          date.day,
          course.endTime ~/ 100,
          course.endTime % 100,
        ),
        PlanBusySource.course,
        course.uuid,
        course.courseName,
        course,
      );
    }
    for (final item in local.schedules) {
      if (item.isDeleted || item.status == FixedScheduleStatus.cancelled) {
        continue;
      }
      if (item.startTime == null ||
          item.endTime == null ||
          item.endTime! <= item.startTime!) {
        if (item.date == day) unknown.add('固定日程“${item.title}”：时间待定');
        continue;
      }
      add(
        DateTime.fromMillisecondsSinceEpoch(item.startTime!),
        DateTime.fromMillisecondsSinceEpoch(item.endTime!),
        PlanBusySource.fixedSchedule,
        item.id,
        item.title,
        item,
      );
    }
    final plannedTodoIds = local.blocks
        .where(
          (item) =>
              !item.isDeleted &&
              item.endTime > query.dayStart.millisecondsSinceEpoch &&
              item.startTime < query.dayEnd.millisecondsSinceEpoch,
        )
        .map((item) => item.todoId)
        .toSet();
    for (final item in local.blocks) {
      if (item.id == query.excludeBlockId ||
          !PlanAvailabilityService.occupies(item)) {
        continue;
      }
      if (item.endTime <= item.startTime) {
        if (DateFormat('yyyy-MM-dd')
                .format(DateTime.fromMillisecondsSinceEpoch(item.startTime)) ==
            day) {
          unknown.add('规划“${item.titleSnapshot ?? '未命名'}”：时间无效');
        }
        continue;
      }
      add(
        DateTime.fromMillisecondsSinceEpoch(item.startTime),
        DateTime.fromMillisecondsSinceEpoch(item.endTime),
        PlanBusySource.planBlock,
        item.id,
        item.titleSnapshot ?? '未命名规划',
        item,
      );
    }
    for (final item in local.todos) {
      if (item.isDeleted ||
          item.isDone ||
          !item.hasLegacyTimeRange ||
          // Match the planning calendar's legacy projection. A cross-day
          // deadline, zero placeholder or physical creation fallback does not
          // establish a continuous execution reservation.
          (item.createdDate ?? 0) <= 0 ||
          item.createdDate == item.createdAt ||
          DateTime(
                item.effectiveStartTime.year,
                item.effectiveStartTime.month,
                item.effectiveStartTime.day,
              ) !=
              DateTime(
                item.dueDate!.year,
                item.dueDate!.month,
                item.dueDate!.day,
              ) ||
          plannedTodoIds.contains(item.id)) {
        continue;
      }
      add(
        item.effectiveStartTime,
        item.dueDate!.toLocal(),
        PlanBusySource.legacyTodo,
        item.id,
        item.title,
        item,
      );
    }
    return PlanAvailabilityDaySources(
      date: query.dayStart,
      busy: List.unmodifiable(
        busy.where(
          (item) =>
              item.end.isAfter(query.dayStart) &&
              item.start.isBefore(query.dayEnd),
        ),
      ),
      unknownTimes: List.unmodifiable(unknown),
    );
  }

  Future<_AvailabilityReadSources> _readSources(
    String username,
    DateTime start,
    DateTime end, {
    bool appOnly = false,
    bool forceRefresh = false,
    bool requireCalendar = false,
  }) async {
    await _checkAccount(username);
    // Let existing account/semester compatibility migrations settle before
    // capturing the settings revision; validate first so corrupt data is fatal.
    await _settingsFingerprint(username);
    await CourseCalendarAdjustmentService.load();
    await StorageService.getSemesters();
    await StorageService.getSemesterStart();
    await _checkAccount(username);
    final settings = await _settingsFingerprint(username);
    final revision = DeviceCalendarReadService.revision.value;
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(username);
    final local = await _readLocal(db);
    final external = <PlanBusyInterval>[];
    var included = false;
    var coverage = '已检查课程、固定日程和规划；未计入手机日历';
    try {
      if (!appOnly &&
          DeviceCalendarReadService.isSupported &&
          await DeviceCalendarReadService.isEnabled() &&
          await DeviceCalendarReadService.checkPermission()) {
        final events = await DeviceCalendarReadService.readEvents(
          start: start,
          end: end,
          forceRefresh: forceRefresh,
        );
        if (!await DeviceCalendarReadService.isEnabled() ||
            !await DeviceCalendarReadService.checkPermission()) {
          throw const PlanAvailabilityException('手机日历权限已变化');
        }
        included = true;
        external.addAll(
          events
              .where((item) => !item.allDay)
              .map(
                (item) => PlanBusyInterval(
                  item.start,
                  item.end,
                  source: PlanBusySource.deviceCalendar,
                  id: item.id,
                  title: item.title,
                  record: item,
                ),
              ),
        );
        coverage = '已检查课程、固定日程、规划和手机日历；全天及跨天手机日历事项不占用时间';
      }
    } catch (_) {
      throw const PlanAvailabilityException(
        '手机日历读取失败，请重试或仅按应用内安排查找',
        canUseAppOnly: true,
      );
    }
    if (requireCalendar && !included) {
      throw const PlanAvailabilityException('手机日历读取范围已变化，请重新查找时段');
    }
    if (settings != await _settingsFingerprint(username) ||
        revision != DeviceCalendarReadService.revision.value) {
      throw const PlanAvailabilityException('日程设置已变化，请重新查找时段');
    }
    await _checkAccount(username);
    return _AvailabilityReadSources(
      local,
      external,
      included,
      coverage,
      settings,
      revision,
    );
  }

  Future<PlanAvailabilitySnapshot> read(
    PlanAvailabilityQuery query, {
    bool forceRefresh = false,
    bool requireCalendar = false,
  }) async {
    final sources = await _readSources(
      query.username,
      query.dayStart,
      query.dayEnd,
      appOnly: query.appOnly,
      forceRefresh: forceRefresh,
      requireCalendar: requireCalendar,
    );
    return _snapshot(
      query,
      sources.local,
      external: sources.external,
      included: sources.included,
      coverage: sources.coverage,
      settingsFingerprint: sources.settings,
      calendarRevision: sources.calendarRevision,
    );
  }

  Future<PlanAvailabilityRangeSnapshot> readRange(
    String username,
    DateTime date, {
    int days = 1,
    bool appOnly = false,
    bool forceRefresh = false,
  }) async {
    if (days < 1 || days > 7) {
      throw const PlanAvailabilityException('检查范围须为1至7天');
    }
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(start.year, start.month, start.day + days);
    final sources = await _readSources(
      username,
      start,
      end,
      appOnly: appOnly,
      forceRefresh: forceRefresh,
    );
    return PlanAvailabilityRangeSnapshot(
      username: username,
      start: start,
      end: end,
      blocks: List.unmodifiable(sources.local.blocks),
      todos: List.unmodifiable(sources.local.todos),
      coverage: sources.coverage,
      deviceCalendarIncluded: sources.included,
      days: List.unmodifiable([
        for (var i = 0; i < days; i++)
          _daySources(
            PlanAvailabilityQuery(
              username: username,
              todoId: '',
              date: DateTime(start.year, start.month, start.day + i),
              minutes: 1,
            ),
            sources.local,
            external: sources.external,
          ),
      ]),
    );
  }

  Future<TodoPlanBlock> save(
    PlanAvailabilitySelection selection,
    TodoPlanBlock draft, {
    int? expectedVersion,
    int? expectedUpdatedAt,
    bool sync = true,
    Future<void> Function(DatabaseExecutor executor)? beforeWrite,
  }) async {
    final query = selection.query;
    if (draft.todoId != query.todoId ||
        draft.id != (query.excludeBlockId ?? draft.id) ||
        draft.startTime != selection.slot.start.millisecondsSinceEpoch ||
        draft.endTime != selection.slot.end.millisecondsSinceEpoch) {
      throw const PlanAvailabilityException('规划草稿与推荐时段不一致，请重新选择');
    }
    final fresh = await read(
      query,
      forceRefresh: true,
      requireCalendar: selection.snapshot.deviceCalendarIncluded,
    );
    if (!PlanAvailabilityService.accepts(selection, fresh, now: now)) {
      throw const PlanAvailabilityException('该时段已失效或被占用，请重新查找时段');
    }
    final db =
        databaseOverride ??
        await DatabaseHelper.instance.databaseForUser(query.username);
    // Prepare adjusted course occurrences outside the transaction; raw rows and
    // settings are compared again inside, without recursively reading the DB.
    final local = await _readLocal(db);
    if (local.courseFingerprint != fresh.courseFingerprint) {
      throw const PlanAvailabilityException('课程已变更，请重新查找时段');
    }
    return StorageService.savePlanBlockEdited(
      query.username,
      draft,
      expectedVersion: expectedVersion,
      expectedUpdatedAt: expectedUpdatedAt,
      sync: sync,
      beforeWrite: (executor) async {
        await _checkAccount(query.username);
        if (fresh.settingsFingerprint !=
                await _settingsFingerprint(query.username) ||
            fresh.calendarRevision !=
                DeviceCalendarReadService.revision.value) {
          throw const PlanAvailabilityException('日程设置已变化，请重新查找时段');
        }
        final current = await _readLocal(
          executor,
          preparedCourses: local.courses,
          expectedCourseFingerprint: fresh.courseFingerprint,
        );
        if (query.excludeBlockId != null) {
          final editing = current.blocks
              .where((item) => item.id == query.excludeBlockId)
              .firstOrNull;
          if (editing == null ||
              !PlanAvailabilityService.canReschedule(editing)) {
            throw const PlanAvailabilityException('规划状态已变化，请读取最新记录后重新编辑');
          }
        }
        final latest = _snapshot(
          query,
          current,
          external: fresh.busy
              .where((item) => item.source == PlanBusySource.deviceCalendar)
              .toList(),
        );
        if (!PlanAvailabilityService.accepts(selection, latest, now: now)) {
          throw const PlanAvailabilityException('该时段已失效或被占用，请重新查找时段');
        }
        await _checkAccount(query.username);
        if (beforeWrite != null) await beforeWrite(executor);
      },
    );
  }
}

class _LocalAvailabilityData {
  const _LocalAvailabilityData({
    required this.courses,
    required this.courseFingerprint,
    required this.todos,
    required this.schedules,
    required this.blocks,
  });
  final List<CourseItem> courses;
  final String courseFingerprint;
  final List<TodoItem> todos;
  final List<FixedScheduleItem> schedules;
  final List<TodoPlanBlock> blocks;
}

class _AvailabilityReadSources {
  const _AvailabilityReadSources(
    this.local,
    this.external,
    this.included,
    this.coverage,
    this.settings,
    this.calendarRevision,
  );
  final _LocalAvailabilityData local;
  final List<PlanBusyInterval> external;
  final bool included;
  final String coverage, settings;
  final int calendarRevision;
}
