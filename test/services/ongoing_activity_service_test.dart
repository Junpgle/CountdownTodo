import 'package:CountDownTodo/models.dart';
import 'package:CountDownTodo/services/ongoing_activity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OngoingActivityService', () {
    final now = DateTime(2026, 7, 15, 10, 30);

    test('课程优先于同时进行的计划块和待办', () {
      final todo = TodoItem(
        id: 'todo-1',
        title: '写方案',
        createdDate: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 12),
      );
      final plan = TodoPlanBlock(
        id: 'plan-1',
        todoId: 'todo-2',
        titleSnapshot: '整理资料',
        startTime: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
      );
      final course = CourseItem(
        uuid: 'course-1',
        courseName: '高等数学',
        teacherName: '教师',
        date: '2026-07-15',
        weekday: 3,
        startTime: 1000,
        endTime: 1140,
        weekIndex: 1,
        roomName: 'A101',
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: [plan],
        courses: [course],
        now: now,
      );

      expect(result.activity?.kind, OngoingActivityKind.course);
      expect(result.activity?.title, '高等数学');
      expect(result.activity?.subtitle, 'A101');
    });

    test('活动计划块会替代其关联待办，避免重复展示', () {
      final todo = TodoItem(
        id: 'todo-1',
        title: '写方案',
        createdDate: DateTime(2026, 7, 15, 10).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 12),
      );
      final plan = TodoPlanBlock(
        id: 'plan-1',
        todoId: todo.id,
        startTime: DateTime(2026, 7, 15, 10, 15).millisecondsSinceEpoch,
        endTime: DateTime(2026, 7, 15, 11).millisecondsSinceEpoch,
      );

      final result = OngoingActivityService.resolve(
        todos: [todo],
        planBlocks: [plan],
        courses: const [],
        now: now,
      );

      expect(result.activity?.kind, OngoingActivityKind.planBlock);
      expect(result.activity?.title, '写方案');
    });

    test('忽略全天和跨日待办，并返回下一处时间边界', () {
      final crossDay = TodoItem(
        title: '跨日任务',
        createdDate: DateTime(2026, 7, 14, 22).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 11),
      );
      final future = TodoItem(
        title: '下午会议',
        createdDate: DateTime(2026, 7, 15, 14).millisecondsSinceEpoch,
        dueDate: DateTime(2026, 7, 15, 15),
      );

      final result = OngoingActivityService.resolve(
        todos: [crossDay, future],
        planBlocks: const [],
        courses: const [],
        now: now,
      );

      expect(result.activity, isNull);
      expect(result.nextBoundary, DateTime(2026, 7, 15, 14));
    });
  });
}
