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
  });

  final String id;
  final OngoingActivityKind kind;
  final String title;
  final String subtitle;
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
        'startMs': startMs,
        'endMs': endMs,
      };
}

class OngoingActivityResolution {
  const OngoingActivityResolution({this.activity, this.nextBoundary});

  final OngoingActivity? activity;
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
    ]);
    return resolve(
      todos: results[0] as List<TodoItem>,
      planBlocks: results[1] as List<TodoPlanBlock>,
      courses: results[2] as List<CourseItem>,
      now: now,
    );
  }

  static OngoingActivityResolution resolve({
    required List<TodoItem> todos,
    required List<TodoPlanBlock> planBlocks,
    required List<CourseItem> courses,
    DateTime? now,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final nowMs = localNow.millisecondsSinceEpoch;
    final candidates = <OngoingActivity>[];
    final boundaries = <int>[];
    final todoById = {for (final todo in todos) todo.id: todo};
    final activePlanTodoIds = <String>{};

    for (final course in courses) {
      if (course.isDeleted) continue;
      final range = _courseRange(course);
      if (range == null) continue;
      _addFutureBoundaries(boundaries, range.$1, range.$2, nowMs);
      if (_containsNow(range.$1, range.$2, nowMs)) {
        candidates.add(OngoingActivity(
          id: course.uuid,
          kind: OngoingActivityKind.course,
          title: _firstNonEmpty([course.courseName, '未命名课程']),
          subtitle: course.roomName,
          startMs: range.$1,
          endMs: range.$2,
        ));
      }
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
      if (_containsNow(block.startTime, block.endTime, nowMs)) {
        activePlanTodoIds.add(block.todoId);
        final linkedTodo = todoById[block.todoId];
        candidates.add(OngoingActivity(
          id: block.id,
          kind: OngoingActivityKind.planBlock,
          title:
              _firstNonEmpty([block.titleSnapshot, linkedTodo?.title, '计划事项']),
          subtitle: block.remark ?? linkedTodo?.remark ?? '',
          startMs: block.startTime,
          endMs: block.endTime,
        ));
      }
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
      if (_containsNow(startMs, endMs, nowMs)) {
        candidates.add(OngoingActivity(
          id: todo.id,
          kind: OngoingActivityKind.todo,
          title: _firstNonEmpty([todo.title, '未命名待办']),
          subtitle: todo.remark ?? '',
          startMs: startMs,
          endMs: endMs,
        ));
      }
    }

    candidates.sort((a, b) {
      final kindOrder = _kindPriority(a.kind).compareTo(_kindPriority(b.kind));
      if (kindOrder != 0) return kindOrder;
      final endOrder = a.endMs.compareTo(b.endMs);
      if (endOrder != 0) return endOrder;
      return a.startMs.compareTo(b.startMs);
    });
    boundaries.sort();

    return OngoingActivityResolution(
      activity: candidates.isEmpty ? null : candidates.first,
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
