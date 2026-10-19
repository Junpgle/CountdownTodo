import '../models.dart';
import '../storage_service.dart';
import 'course_service.dart';
import 'device_calendar_read_service.dart';
import 'plan_review_repository.dart';
import 'plan_todo_guard.dart';

enum HomeAgendaSource { plans, courses, fixed, calendar }

extension HomeAgendaSourceLabel on HomeAgendaSource {
  String get label => switch (this) {
    HomeAgendaSource.plans => '规划',
    HomeAgendaSource.courses => '课程',
    HomeAgendaSource.fixed => '固定日程',
    HomeAgendaSource.calendar => '手机日历',
  };
}

class HomeAgendaItem {
  const HomeAgendaItem({
    required this.id,
    required this.title,
    required this.sourceLabel,
    required this.start,
    required this.end,
    this.detail = '',
    this.allDay = false,
    this.completed = false,
    this.plan,
    this.course,
    this.fixed,
    this.calendar,
    this.todo,
  });
  final String id, title, sourceLabel, detail;
  final DateTime start, end;
  final bool allDay, completed;
  final PlanTodayRow? plan;
  final CourseItem? course;
  final FixedScheduleItem? fixed;
  final DeviceCalendarEvent? calendar;
  final TodoItem? todo;

  bool get isFocusing => plan?.status == TodoPlanStatus.focusing.index;
  bool needsAttention(DateTime now) =>
      plan != null &&
      !completed &&
      !isFocusing &&
      (plan!.status == TodoPlanStatus.missed.index || !end.isAfter(now));
  bool isCurrent(DateTime now) =>
      !allDay &&
      !completed &&
      (isFocusing ||
          (!needsAttention(now) && !start.isAfter(now) && end.isAfter(now)));
  bool isUpcoming(DateTime now) =>
      !allDay &&
      !completed &&
      !isFocusing &&
      !needsAttention(now) &&
      start.isAfter(now);
}

class HomeAgendaSnapshot {
  HomeAgendaSnapshot({
    required this.identity,
    required this.day,
    required this.instant,
    required this.sources,
    required this.errors,
    required this.plans,
    required this.todos,
    required this.includeSchedules,
  });
  final PlanTodoIdentity identity;
  final DateTime day, instant;
  final Map<HomeAgendaSource, List<HomeAgendaItem>> sources;
  final Map<HomeAgendaSource, String> errors;
  final PlanAgendaProjection? plans;
  final List<TodoItem> todos;
  final bool includeSchedules;

  late final List<HomeAgendaItem> items = _buildItems();
  late final _HomeAgendaBuckets _buckets = _partitionItems();

  List<HomeAgendaItem> get current => _buckets.current;
  List<HomeAgendaItem> get upcoming => _buckets.upcoming;
  List<HomeAgendaItem> get attention => _buckets.attention;
  List<HomeAgendaItem> get ended => _buckets.ended;
  List<HomeAgendaItem> get allDay => _buckets.allDay;

  List<HomeAgendaItem> _buildItems() {
    final result = <String, HomeAgendaItem>{};
    for (final source in sources.values) {
      for (final item in source) {
        result[item.id] = item;
      }
    }
    if (includeSchedules) {
      final endOfDay = DateTime(day.year, day.month, day.day + 1);
      for (final todo in todos) {
        if (todo.isDeleted ||
            todo.dueDate == null ||
            (plans?.plannedTodoIds.contains(todo.id) ?? false)) {
          continue;
        }
        final due = todo.dueDate!.toLocal();
        final allDay = todo.isAllDayTask;
        final start = allDay
            ? DateTime(due.year, due.month, due.day)
            : DateTime.fromMillisecondsSinceEpoch(
                todo.createdDate ?? todo.createdAt,
              );
        final end = allDay
            ? DateTime(start.year, start.month, start.day + 1)
            : due;
        if (!end.isAfter(start) ||
            !start.isBefore(endOfDay) ||
            !end.isAfter(day)) {
          continue;
        }
        // A failed planning source must not turn linked todos into duplicates.
        if (!allDay && errors.containsKey(HomeAgendaSource.plans)) continue;
        result['todo:${todo.id}'] = HomeAgendaItem(
          id: 'todo:${todo.id}',
          title: todo.title,
          sourceLabel: '待办',
          start: start,
          end: end,
          allDay: allDay,
          completed: todo.isDone,
          todo: todo,
          detail: todo.remark ?? '',
        );
      }
    }
    return result.values.toList()..sort(compare);
  }

  static int compare(HomeAgendaItem a, HomeAgendaItem b) {
    final time = a.start.compareTo(b.start);
    return time != 0 ? time : a.id.compareTo(b.id);
  }

  _HomeAgendaBuckets _partitionItems() {
    final current = <HomeAgendaItem>[];
    final upcoming = <HomeAgendaItem>[];
    final attention = <HomeAgendaItem>[];
    final ended = <HomeAgendaItem>[];
    final allDay = <HomeAgendaItem>[];
    var currentNonPlanCount = 0;
    var upcomingNonPlanCount = 0;
    var endedNonPlanCount = 0;
    var nextBoundary = DateTime(day.year, day.month, day.day + 1);
    final planBoundary = plans?.card.nextBoundary;
    if (planBoundary != null &&
        planBoundary.isAfter(instant) &&
        planBoundary.isBefore(nextBoundary)) {
      nextBoundary = planBoundary;
    }

    for (final item in items) {
      final isFocusing = item.isFocusing;
      final needsAttention = item.needsAttention(instant);
      if (needsAttention) attention.add(item);
      if (item.allDay) allDay.add(item);

      if (!item.allDay && !item.completed && !needsAttention) {
        // The outer guards already establish the non-focus and attention
        // conditions used by the item getters, so classify directly here.
        if (isFocusing ||
            (!item.start.isAfter(instant) && item.end.isAfter(instant))) {
          current.add(item);
          if (item.plan == null) currentNonPlanCount++;
        } else if (item.start.isAfter(instant)) {
          upcoming.add(item);
          if (item.plan == null) upcomingNonPlanCount++;
        }
      }

      if (!item.allDay &&
          !needsAttention &&
          (item.completed || !item.end.isAfter(instant))) {
        ended.add(item);
        if (item.plan == null) endedNonPlanCount++;
      }

      if (item.allDay || item.completed) continue;
      if (item.start.isAfter(instant) && item.start.isBefore(nextBoundary)) {
        nextBoundary = item.start;
      }
      if (item.end.isAfter(instant) && item.end.isBefore(nextBoundary)) {
        nextBoundary = item.end;
      }
    }

    return _HomeAgendaBuckets(
      current: current,
      upcoming: upcoming,
      attention: attention,
      ended: ended,
      allDay: allDay,
      currentNonPlanCount: currentNonPlanCount,
      upcomingNonPlanCount: upcomingNonPlanCount,
      endedNonPlanCount: endedNonPlanCount,
      nextBoundary: nextBoundary,
    );
  }

  int _count(int group, int nonPlanCount) =>
      nonPlanCount + (plans?.counts[group] ?? 0);
  late final int currentCount = _count(0, _buckets.currentNonPlanCount);
  late final int upcomingCount = _count(1, _buckets.upcomingNonPlanCount);
  late final int attentionCount = plans?.counts[2] ?? 0;
  late final int endedCount = _count(3, _buckets.endedNonPlanCount);
  late final int total =
      currentCount +
      upcomingCount +
      attentionCount +
      endedCount +
      allDay.length;
  late final List<HomeAgendaItem> visible = _buildVisibleItems();

  List<HomeAgendaItem> _buildVisibleItems() {
    final limit = attentionCount > 0 ? 4 : 5;
    final result = <HomeAgendaItem>[];
    for (final item in current) {
      if (result.length == limit) break;
      result.add(item);
    }
    for (final item in upcoming) {
      if (result.length == limit) break;
      result.add(item);
    }
    return result;
  }

  late final int hiddenCurrent =
      currentCount - visible.where((i) => i.isCurrent(instant)).length;
  late final DateTime nextBoundary = _buckets.nextBoundary;
}

class _HomeAgendaBuckets {
  const _HomeAgendaBuckets({
    required this.current,
    required this.upcoming,
    required this.attention,
    required this.ended,
    required this.allDay,
    required this.currentNonPlanCount,
    required this.upcomingNonPlanCount,
    required this.endedNonPlanCount,
    required this.nextBoundary,
  });

  final List<HomeAgendaItem> current;
  final List<HomeAgendaItem> upcoming;
  final List<HomeAgendaItem> attention;
  final List<HomeAgendaItem> ended;
  final List<HomeAgendaItem> allDay;
  final int currentNonPlanCount;
  final int upcomingNonPlanCount;
  final int endedNonPlanCount;
  final DateTime nextBoundary;
}

typedef HomeAgendaCourseLoader = Future<List<CourseItem>> Function(
  String username,
);
typedef HomeAgendaCourseRangeLoader = Future<List<CourseItem>> Function(
  String username, {
  required DateTime from,
  required DateTime to,
});
typedef HomeAgendaFixedLoader = Future<List<FixedScheduleItem>> Function(
  String username,
  DateTime day,
);
typedef HomeAgendaCalendarLoader = Future<List<DeviceCalendarEvent>> Function(
  DateTime day,
);

/// Independent source failures are visible and retryable. No business writes.
class HomeAgendaRepository {
  HomeAgendaRepository({
    required this.plans,
    HomeAgendaCourseLoader? courseLoader,
    HomeAgendaCourseRangeLoader? courseRangeLoader,
    this.fixedLoader = StorageService.getFixedSchedulesByDay,
    this.calendarLoader = _readCalendar,
  }) : courseLoader = courseLoader ?? CourseService.getAllCourses,
       courseRangeLoader =
           courseRangeLoader ??
           (courseLoader == null ? CourseService.getCoursesForDateRange : null);
  final PlanReviewRepository plans;
  final HomeAgendaCourseLoader courseLoader;
  final HomeAgendaCourseRangeLoader? courseRangeLoader;
  final HomeAgendaFixedLoader fixedLoader;
  final HomeAgendaCalendarLoader calendarLoader;

  static Future<List<DeviceCalendarEvent>> _readCalendar(DateTime day) =>
      DeviceCalendarReadService.readEvents(
        start: DeviceCalendarReadService.monthGridStart(day),
        end: DeviceCalendarReadService.monthGridEnd(day),
      );

  Future<List<HomeAgendaItem>> _loadCourseItems(
    String username,
    DateTime day,
  ) async {
    final parsedDates = <String, DateTime?>{};
    final items = <HomeAgendaItem>[];
    final rangeLoader = courseRangeLoader;
    final courses = rangeLoader == null
        ? await courseLoader(username)
        : await rangeLoader(
            username,
            from: day,
            to: DateTime(day.year, day.month, day.day + 1),
          );
    for (final course in courses) {
      if (course.isDeleted) continue;
      final courseDay = parsedDates.putIfAbsent(
        course.date,
        () => DateTime.tryParse(course.date),
      );
      if (courseDay != day) continue;

      final roomName = course.roomName;
      final teacherName = course.teacherName;
      final hasRoom = roomName.trim().isNotEmpty;
      final hasTeacher = teacherName.trim().isNotEmpty;
      final detail = hasRoom
          ? hasTeacher
                ? '$roomName · $teacherName'
                : roomName
          : hasTeacher
          ? teacherName
          : '';

      final item = HomeAgendaItem(
        id: 'course:${course.uuid}',
        title: course.courseName,
        sourceLabel: '课程',
        start: DateTime(
          day.year,
          day.month,
          day.day,
          course.startTime ~/ 100,
          course.startTime % 100,
        ),
        end: DateTime(
          day.year,
          day.month,
          day.day,
          course.endTime ~/ 100,
          course.endTime % 100,
        ),
        detail: detail,
        course: course,
      );
      if (item.end.isAfter(item.start)) items.add(item);
    }
    return items;
  }

  Future<HomeAgendaSnapshot> read(
    String username, {
    required DateTime now,
    required List<TodoItem> todos,
    bool includeSchedules = true,
    bool includePlans = true,
    HomeAgendaSnapshot? previous,
    Set<HomeAgendaSource>? only,
    String? planningError,
  }) async {
    final identity = await PlanTodoIdentity.capture(username);
    final day = DateTime(now.year, now.month, now.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final canReuse =
        previous?.day == day &&
        previous?.identity.username == username &&
        previous?.identity.userId == identity.userId &&
        previous?.includeSchedules == includeSchedules;
    final sources = <HomeAgendaSource, List<HomeAgendaItem>>{
      if (canReuse) ...previous!.sources,
    };
    final errors = <HomeAgendaSource, String>{
      if (canReuse) ...previous!.errors,
    };
    PlanAgendaProjection? projection = canReuse ? previous!.plans : null;
    Future<void> load(
      HomeAgendaSource source,
      Future<List<HomeAgendaItem>> Function() action,
    ) async {
      if (only != null && !only.contains(source) && canReuse) return;
      try {
        sources[source] = await action();
        errors.remove(source);
      } catch (error) {
        sources.remove(source);
        errors[source] = '$error';
        if (source == HomeAgendaSource.plans) projection = null;
      }
    }

    await Future.wait([
      if (includePlans)
        load(HomeAgendaSource.plans, () async {
          if (planningError != null) throw StateError(planningError);
          final result = await plans.readAgendaCard(username);
          projection = result;
          return result.card.rows
              .map(
                (row) => HomeAgendaItem(
                  id: 'plan:${row.entry.id}',
                  title: row.entry.title,
                  sourceLabel: '待办规划',
                  start: DateTime.fromMillisecondsSinceEpoch(row.entry.start),
                  end: DateTime.fromMillisecondsSinceEpoch(row.entry.end),
                  completed: row.status == TodoPlanStatus.finished.index,
                  plan: row,
                ),
              )
              .toList();
        }),
      if (includeSchedules) ...[
        load(HomeAgendaSource.courses, () => _loadCourseItems(username, day)),
        load(
          HomeAgendaSource.fixed,
          () async => (await fixedLoader(username, day))
              .where(
                (f) =>
                    !f.isDeleted && f.status != FixedScheduleStatus.cancelled,
              )
              .map(
                (f) => HomeAgendaItem(
                  id: 'fixed:${f.id}:${f.date}',
                  title: f.title,
                  sourceLabel: '固定日程',
                  start: f.startTime == null
                      ? day
                      : DateTime.fromMillisecondsSinceEpoch(f.startTime!),
                  end: DateTime.fromMillisecondsSinceEpoch(
                    f.effectiveActivityEndTime ?? end.millisecondsSinceEpoch,
                  ),
                  allDay: f.startTime == null,
                  completed: f.status == FixedScheduleStatus.finished,
                  detail: f.location ?? '',
                  fixed: f,
                ),
              )
              .toList(),
        ),
        load(
          HomeAgendaSource.calendar,
          () async => (await calendarLoader(day))
              .where((e) => e.overlaps(day, end))
              .map(
                (e) => HomeAgendaItem(
                  id: 'calendar:${e.calendarId}:${e.id}:${e.start.millisecondsSinceEpoch}',
                  title: e.title,
                  sourceLabel: '手机日历',
                  start: e.start,
                  end: e.end,
                  allDay: e.allDay,
                  detail: e.location == null ? '只读' : '${e.location} · 只读',
                  calendar: e,
                ),
              )
              .toList(),
        ),
      ],
    ]);
    if (!includePlans) {
      sources.remove(HomeAgendaSource.plans);
      errors.remove(HomeAgendaSource.plans);
      projection = null;
    }
    if (!includeSchedules) {
      sources.removeWhere((key, _) => key != HomeAgendaSource.plans);
      errors.removeWhere((key, _) => key != HomeAgendaSource.plans);
    }
    await identity.check();
    return HomeAgendaSnapshot(
      identity: identity,
      day: day,
      instant: now,
      sources: Map.unmodifiable(sources),
      errors: Map.unmodifiable(errors),
      plans: projection,
      todos: List.unmodifiable(todos),
      includeSchedules: includeSchedules,
    );
  }
}
