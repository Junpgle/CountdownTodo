import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:countdown_todo/services/pomodoro_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI context and preview disclose truncated lists', () {
    final now = DateTime(2026, 10, 2, 12);
    DateTime upcomingDate(int offset) =>
        DateTime(now.year, now.month, now.day + offset);
    const userMessage = '查看所有待办、倒计时、番茄标签、日程、时间块、冲突、团队和课程表';
    final courses = [
      for (var index = 0; index < 31; index++)
        CourseItem(
          uuid: 'course-$index',
          courseName: '课程 $index',
          teacherName: '教师',
          date: upcomingDate(index + 1).toIso8601String().substring(0, 10),
          weekday: upcomingDate(index + 1).weekday,
          startTime: 900,
          endTime: 1000,
          weekIndex: 1,
          roomName: '教室',
        ),
    ];
    final todos = [
      for (var index = 0; index < 81; index++)
        {
          'id': 'todo-$index',
          'title': '待办 $index',
          'isDone': false,
          'timeMode': 'unscheduled',
        },
    ];
    final countdowns = [
      for (var index = 0; index < 41; index++)
        CountdownItem(
          id: 'countdown-$index',
          title: '倒计时 $index',
          targetDate: upcomingDate(index + 1),
        ),
    ];
    final pomodoroTags = [
      for (var index = 0; index < 41; index++)
        PomodoroTag(uuid: 'tag-$index', name: '标签 $index'),
    ];
    final fixedSchedules = [
      for (var index = 0; index < 51; index++)
        FixedScheduleItem(
          id: 'schedule-$index',
          title: '日程 $index',
          date: upcomingDate(index + 1).toIso8601String().substring(0, 10),
          startTime: upcomingDate(index + 1).millisecondsSinceEpoch,
        ),
    ];
    final planBlocks = [
      for (var index = 0; index < 61; index++)
        TodoPlanBlock(
          id: 'plan-$index',
          todoId: 'todo-$index',
          titleSnapshot: '规划 $index',
          startTime: upcomingDate(index + 1).millisecondsSinceEpoch,
          endTime: upcomingDate(index + 1)
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          plannedMinutes: 60,
        ),
    ];
    final conflicts = [
      for (var index = 0; index < 21; index++)
        ConflictInfo(
          type: '时间冲突',
          item: {'title': '事项 $index'},
          conflictWith: {'title': '日程'},
        ),
    ];
    final teams = [
      for (var index = 0; index < 21; index++)
        Team(
          uuid: 'team-$index',
          name: '团队 $index',
          creatorId: index,
          createdAt: 0,
          userRole: TeamRole.member,
        ),
    ];

    final context = AiTodoContextBuilder.buildContextInjection(
      userMessage: userMessage,
      courses: courses,
      timeLogs: const [],
      todos: todos,
      countdowns: countdowns,
      pomodoroTags: pomodoroTags,
      fixedSchedules: fixedSchedules,
      planBlocks: planBlocks,
      conflicts: conflicts,
      teams: teams,
      now: now,
    )!;
    final preview = AiTodoContextBuilder.buildContextInjectionSummary(
      userMessage: userMessage,
      courses: courses,
      timeLogs: const [],
      todos: todos,
      countdowns: countdowns,
      pomodoroTags: pomodoroTags,
      fixedSchedules: fixedSchedules,
      planBlocks: planBlocks,
      conflicts: conflicts,
      teams: teams,
      now: now,
    )!;

    for (final expectedCount in [
      '展示 80/81 条',
      '展示 40/41 条',
      '展示 40/41 个',
      '展示 50/51 条',
      '展示 60/61 条',
      '展示 20/21 条',
      '展示 20/21 个',
      '展示 30/31 节',
    ]) {
      expect(context, contains(expectedCount));
    }
    for (final expectedCount in [
      '待办80/81条',
      '倒计时40/41个',
      '番茄标签40/41个',
      '日程50/51条',
      '规划块60/61个',
      '冲突信息20/21条',
      '团队信息20/21个',
    ]) {
      expect(preview, contains(expectedCount));
    }
  });
}
