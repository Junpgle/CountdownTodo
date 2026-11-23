import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/conflict_visibility_service.dart';
import 'package:flutter_test/flutter_test.dart';

TodoItem conflictedTodo({
  String? teamUuid,
  bool isAllDay = false,
  Map<String, dynamic>? serverVersionData,
}) {
  final start = DateTime(2026, 8, 10, 9);
  return TodoItem(
    title: '冲突待办',
    createdDate: start.toUtc().millisecondsSinceEpoch,
    dueDate: start.add(const Duration(hours: 1)),
    teamUuid: teamUuid,
    isAllDay: isAllDay,
    hasConflict: true,
    serverVersionData: serverVersionData,
  );
}

void main() {
  group('ConflictVisibilityService', () {
    test('只显示未删除且确实有冲突的待办', () {
      expect(
        ConflictVisibilityService.isVisibleTodoConflict(
          conflictedTodo(teamUuid: 'team-1'),
        ),
        isTrue,
      );
      expect(
        ConflictVisibilityService.isVisibleTodoConflict(
          conflictedTodo()..hasConflict = false,
        ),
        isFalse,
      );
      expect(
        ConflictVisibilityService.isVisibleTodoConflict(
          conflictedTodo()..isDeleted = true,
        ),
        isFalse,
      );
    });

    test('全天待办不计入冲突入口', () {
      expect(
        ConflictVisibilityService.isVisibleTodoConflict(
          conflictedTodo(
            isAllDay: true,
            serverVersionData: {
              'type': 'schedule',
              'conflict_with': [
                {
                  'created_date': DateTime(
                    2026,
                    8,
                    10,
                    10,
                  ).millisecondsSinceEpoch,
                  'due_date': DateTime(2026, 8, 10, 11).millisecondsSinceEpoch,
                },
              ],
            },
          ),
        ),
        isFalse,
      );
    });

    test('日程冲突至少需要一个非全天对等项', () {
      final allDayPeer = {'is_all_day': 1};
      final timedPeer = {
        'created_date': DateTime(2026, 8, 10, 10).millisecondsSinceEpoch,
        'due_date': DateTime(2026, 8, 10, 11).millisecondsSinceEpoch,
      };

      expect(
        ConflictVisibilityService.isVisibleTodoConflict(
          conflictedTodo(
            serverVersionData: {
              'type': 'schedule',
              'conflict_with': [allDayPeer],
            },
          ),
        ),
        isFalse,
      );
      expect(
        ConflictVisibilityService.isVisibleTodoConflict(
          conflictedTodo(
            serverVersionData: {
              'type': 'schedule',
              'conflict_with': [allDayPeer, timedPeer],
            },
          ),
        ),
        isTrue,
      );
    });

    test('首页只对可见的团队冲突显示角标', () {
      expect(
        ConflictVisibilityService.hasTeamConflict(
          todos: [conflictedTodo(teamUuid: 'team-1')],
          groups: const [],
          countdowns: const [],
        ),
        isTrue,
      );
      expect(
        ConflictVisibilityService.hasTeamConflict(
          todos: [conflictedTodo()],
          groups: const [],
          countdowns: const [],
        ),
        isFalse,
      );
    });
  });
}
