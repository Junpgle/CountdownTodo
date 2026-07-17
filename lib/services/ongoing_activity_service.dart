import '../models.dart';
import '../storage_service.dart';
import 'course_service.dart';

enum OngoingActivityKind { course, planBlock, todo }

class OngoingActivity {
  const OngoingActivity({
    required this.id,
    required this.kind,
    required this.title,
    required this.startMs,
    required this.endMs,
    this.subtitle = '',
    this.detail = '',
    this.relatedTodoId = '',
    this.groupName = '',
  });

  final String id;
  final OngoingActivityKind kind;
  final String title;
  final String subtitle;
  final String detail;
  final String relatedTodoId;
  final String groupName;
  final int startMs;
  final int endMs;

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': switch (kind) {
          OngoingActivityKind.course => 'course',
          OngoingActivityKind.planBlock => 'plan_block',
          OngoingActivityKind.todo => 'todo',
        },
        'title': title,
        'subtitle': subtitle,
        'detail': detail,
        if (relatedTodoId.isNotEmpty) 'relatedTodoId': relatedTodoId,
        if (groupName.isNotEmpty) 'groupName': groupName,
        'startMs': startMs,
        'endMs': endMs,
      };
}

class OngoingActivityResolution {
  const OngoingActivityResolution({
    this.activity,
    this.nextActivity,
    this.nextBoundary,
  });

  final OngoingActivity? activity;
  final OngoingActivity? nextActivity;
  final DateTime? nextBoundary;
}

/// 统一解析当前正在发生的课程、计划块和有明确时段的待办。
class OngoingActivityService {
  OngoingActivityService._();

  static Future<OngoingActivityResolution> resolveFromStorage(
    String username, {
    DateTime? now,
  }) async {
    final results = await Future.wait<dynamic>([
      StorageService.getTodos(username),
      StorageService.getPlanBlocks(username),
      CourseService.getAllCourses(username),
      StorageService.getTodoGroups(username),
    ]);
    return resolve(
      todos: results[0] as List<TodoItem>,
      planBlocks: results[1] as List<TodoPlanBlock>,
      courses: results[2] as List<CourseItem>,
      todoGroups: results[3] as List<TodoGroup>,
      now: now,
    );
  }

  static OngoingActivityResolution resolve({
    required List<TodoItem> todos,
    required List<TodoPlanBlock> planBlocks,
    required List<CourseItem> courses,
    List<TodoGroup> todoGroups = const [],
    DateTime? now,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final nowMs = localNow.millisecondsSinceEpoch;
    final candidates = <OngoingActivity>[];
    final nextCandidates = <OngoingActivity>[];
    final boundaries = <int>[];
    final todoById = {for (final todo in todos) todo.id: todo};
    final groupById = {for (final group in todoGroups) group.id: group};
    final activePlanTodoIds = <String>{};

    for (final course in courses) {
      if (course.isDeleted) continue;
      final range = _courseRange(course);
      if (range == null) continue;
      _addFutureBoundaries(boundaries, range.$1, range.$2, nowMs);
      _classifyCandidate(
        OngoingActivity(
          id: course.uuid,
          kind: OngoingActivityKind.course,
          title: _firstNonEmpty([course.courseName, '未命名课程']),
          subtitle: course.roomName,
          detail: course.teacherName,
          startMs: range.$1,
          endMs: range.$2,
        ),
        nowMs: nowMs,
        current: candidates,
        upcoming: nextCandidates,
      );
    }

    for (final block in planBlocks) {
      if (block.isDeleted || !_isDisplayablePlanStatus(block.status)) continue;
      if (block.endTime <= block.startTime) continue;
      final blockStart =
          DateTime.fromMillisecondsSinceEpoch(block.startTime).toLocal();
      final blockEnd =
          DateTime.fromMillisecondsSinceEpoch(block.endTime).toLocal();
      if (!_isSameDay(blockStart, blockEnd)) continue;
      _addFutureBoundaries(boundaries, block.startTime, block.endTime, nowMs);
      final linkedTodo = todoById[block.todoId];
      if (_containsNow(block.startTime, block.endTime, nowMs)) {
        activePlanTodoIds.add(block.todoId);
      }
      _classifyCandidate(
        OngoingActivity(
          id: block.id,
          kind: OngoingActivityKind.planBlock,
          title:
              _firstNonEmpty([block.titleSnapshot, linkedTodo?.title, '计划事项']),
          subtitle: block.remark ?? linkedTodo?.remark ?? '',
          detail: linkedTodo?.title ?? '',
          relatedTodoId: block.todoId,
          groupName: groupById[linkedTodo?.groupId]?.name ?? '',
          startMs: block.startTime,
          endMs: block.endTime,
        ),
        nowMs: nowMs,
        current: candidates,
        upcoming: nextCandidates,
      );
    }

    for (final todo in todos) {
      if (todo.isDone ||
          todo.isDeleted ||
          activePlanTodoIds.contains(todo.id)) {
        continue;
      }
      final startMs = todo.createdDate;
      final endMs = todo.dueDate?.millisecondsSinceEpoch;
      if (startMs == null || endMs == null || endMs <= startMs) continue;
      final start = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
      final end = DateTime.fromMillisecondsSinceEpoch(endMs).toLocal();
      if (todo.isAllDayTask || !_isSameDay(start, end)) continue;
      _addFutureBoundaries(boundaries, startMs, endMs, nowMs);
      _classifyCandidate(
        OngoingActivity(
          id: todo.id,
          kind: OngoingActivityKind.todo,
          title: _firstNonEmpty([todo.title, '未命名待办']),
          subtitle: todo.remark ?? '',
          relatedTodoId: todo.id,
          groupName: groupById[todo.groupId]?.name ?? '',
          startMs: startMs,
          endMs: endMs,
        ),
        nowMs: nowMs,
        current: candidates,
        upcoming: nextCandidates,
      );
    }

    candidates.sort((a, b) {
      final kindOrder = _kindPriority(a.kind).compareTo(_kindPriority(b.kind));
      if (kindOrder != 0) return kindOrder;
      final endOrder = a.endMs.compareTo(b.endMs);
      if (endOrder != 0) return endOrder;
      return a.startMs.compareTo(b.startMs);
    });
    boundaries.sort();
    nextCandidates.sort((a, b) {
      final startOrder = a.startMs.compareTo(b.startMs);
      if (startOrder != 0) return startOrder;
      final kindOrder = _kindPriority(a.kind).compareTo(_kindPriority(b.kind));
      if (kindOrder != 0) return kindOrder;
      return a.endMs.compareTo(b.endMs);
    });

    return OngoingActivityResolution(
      activity: candidates.isEmpty ? null : candidates.first,
      nextActivity: nextCandidates.isEmpty ? null : nextCandidates.first,
      nextBoundary: boundaries.isEmpty
          ? null
          : DateTime.fromMillisecondsSinceEpoch(boundaries.first),
    );
  }

  static (int, int)? _courseRange(CourseItem course) {
    final date = DateTime.tryParse(course.date)?.toLocal();
    if (date == null ||
        !_validHhmm(course.startTime) ||
        !_validHhmm(course.endTime)) {
      return null;
    }
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      course.startTime ~/ 100,
      course.startTime % 100,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      course.endTime ~/ 100,
      course.endTime % 100,
    );
    if (!end.isAfter(start)) return null;
    return (start.millisecondsSinceEpoch, end.millisecondsSinceEpoch);
  }

  static bool _validHhmm(int value) =>
      value >= 0 && value ~/ 100 < 24 && value % 100 < 60;

  static bool _containsNow(int startMs, int endMs, int nowMs) =>
      startMs <= nowMs && nowMs < endMs;

  static void _classifyCandidate(
    OngoingActivity activity, {
    required int nowMs,
    required List<OngoingActivity> current,
    required List<OngoingActivity> upcoming,
  }) {
    if (_containsNow(activity.startMs, activity.endMs, nowMs)) {
      current.add(activity);
    } else if (activity.startMs > nowMs) {
      upcoming.add(activity);
    }
  }

  static void _addFutureBoundaries(
    List<int> target,
    int startMs,
    int endMs,
    int nowMs,
  ) {
    if (startMs > nowMs) target.add(startMs);
    if (endMs > nowMs) target.add(endMs);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _isDisplayablePlanStatus(TodoPlanStatus status) =>
      status != TodoPlanStatus.finished &&
      status != TodoPlanStatus.cancelled &&
      status != TodoPlanStatus.missed &&
      status != TodoPlanStatus.skipped;

  static int _kindPriority(OngoingActivityKind kind) => switch (kind) {
        OngoingActivityKind.course => 0,
        OngoingActivityKind.planBlock => 1,
        OngoingActivityKind.todo => 2,
      };

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }
}
