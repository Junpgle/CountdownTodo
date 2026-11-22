import 'package:countdown_todo/services/ai_planning_draft_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 10, 19, 23);
  const request = '从现在开始安排今天剩下的时间，截止晚上21:30。';

  List<Map<String, dynamic>> actionWithBlocks(
    List<Map<String, dynamic>> blocks,
  ) => [
    {'action': 'create_plan_block', 'blocks': blocks},
  ];

  test('拒绝从现在开始请求中的过去时段', () {
    final issue = AiPlanningDraftValidator.validateFromNow(
      requestText: request,
      actions: actionWithBlocks([
        {
          'newTodoTitle': '习概论文',
          'startTime': '2026-10-10 18:30',
          'dueDate': '2026-10-10 19:20',
        },
      ]),
      now: now,
    );

    expect(issue, contains('早于本轮请求时的当前时间'));
  });

  test('允许当前时刻之后且在截止前、不重叠的规划块', () {
    final issue = AiPlanningDraftValidator.validateFromNow(
      requestText: request,
      actions: actionWithBlocks([
        {
          'newTodoTitle': '行测',
          'startTime': '2026-10-10 19:25',
          'dueDate': '2026-10-10 20:00',
        },
        {
          'newTodoTitle': '申论',
          'startTime': '2026-10-10 20:05',
          'dueDate': '2026-10-10 21:00',
        },
      ]),
      now: now,
    );

    expect(issue, isNull);
  });

  test('拒绝彼此重叠的规划块', () {
    final issue = AiPlanningDraftValidator.validateFromNow(
      requestText: request,
      actions: actionWithBlocks([
        {
          'newTodoTitle': '行测',
          'startTime': '2026-10-10 19:25',
          'dueDate': '2026-10-10 20:00',
        },
        {
          'newTodoTitle': '申论',
          'startTime': '2026-10-10 19:55',
          'dueDate': '2026-10-10 21:00',
        },
      ]),
      now: now,
    );

    expect(issue, contains('时间重叠'));
  });

  test('支持中文截止时间并拒绝超时安排', () {
    final issue = AiPlanningDraftValidator.validateFromNow(
      requestText: '从现在开始安排今天剩下的时间，规划到晚上九点半。',
      actions: actionWithBlocks([
        {
          'newTodoTitle': '党课',
          'startTime': '2026-10-10 21:20',
          'dueDate': '2026-10-10 21:40',
        },
      ]),
      now: now,
    );

    expect(issue, contains('截止时间'));
  });

  test('普通改期请求不会被“从现在开始”规划校验拦截', () {
    final issue = AiPlanningDraftValidator.validateFromNow(
      requestText: '把行测规划块改到18:30开始。',
      actions: actionWithBlocks([
        {
          'newTodoTitle': '行测',
          'startTime': '2026-10-10 18:30',
          'dueDate': '2026-10-10 19:00',
        },
      ]),
      now: now,
    );

    expect(issue, isNull);
  });
}
