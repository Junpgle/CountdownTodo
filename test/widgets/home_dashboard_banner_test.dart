import 'dart:collection';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/utils/home_banner_todo_iterator.dart';
import 'package:countdown_todo/widgets/home_dashboard_banner_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingTodoIterable extends IterableBase<TodoItem> {
  _CountingTodoIterable(this.items);

  final List<TodoItem> items;
  int iteratorReads = 0;

  @override
  Iterator<TodoItem> get iterator {
    iteratorReads++;
    return items.iterator;
  }
}

void main() {
  testWidgets('Pomodoro ticks rebuild only the Pomodoro banner', (
    tester,
  ) async {
    final pomodoroRevision = ValueNotifier<int>(0);
    var pomodoroBuilds = 0;
    var courseBannerBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboardBannerLayout(
          bannerKey: const ValueKey('dashboard-banner'),
          pomodoroRevision: pomodoroRevision,
          showPomodoro: true,
          pomodoroBuilder: (context) {
            pomodoroBuilds++;
            return Text('timer ${pomodoroRevision.value}');
          },
          banners: [
            Builder(
              builder: (context) {
                courseBannerBuilds++;
                return const Text('course banner');
              },
            ),
          ],
        ),
      ),
    );

    expect(pomodoroBuilds, 1);
    expect(courseBannerBuilds, 1);

    pomodoroRevision.value++;
    await tester.pump();

    expect(pomodoroBuilds, 2);
    expect(courseBannerBuilds, 1);
    expect(find.text('timer 1'), findsOneWidget);

    pomodoroRevision.dispose();
  });

  test('visits eligible todos once and classifies each title once', () {
    final todos = _CountingTodoIterable([
      TodoItem(
        id: 'ordinary',
        title: '普通任务',
        dueDate: DateTime(2026, 10, 16, 18),
      ),
      TodoItem(
        id: 'done',
        title: '已完成任务',
        isDone: true,
        dueDate: DateTime(2026, 10, 16, 18),
      ),
      TodoItem(
        id: 'deleted',
        title: '已删除任务',
        isDeleted: true,
        dueDate: DateTime(2026, 10, 16, 18),
      ),
      TodoItem(id: 'unscheduled', title: '无截止时间'),
      TodoItem(
        id: 'special',
        title: '顺丰取件',
        dueDate: DateTime(2026, 10, 16, 19),
      ),
    ]);
    final classifiedTitles = <String>[];
    final visitedIds = <String>[];
    final classifiedTypes = <String>[];

    forEachEligibleHomeBannerTodo(
      todos: todos,
      classifyTodoType: (title) {
        classifiedTitles.add(title);
        return title == '顺丰取件' ? 'delivery' : 'default';
      },
      visit: (todo, specialType) {
        visitedIds.add(todo.id);
        classifiedTypes.add(specialType);
      },
    );

    expect(todos.iteratorReads, 1);
    expect(classifiedTitles, ['普通任务', '顺丰取件']);
    expect(visitedIds, ['ordinary', 'special']);
    expect(classifiedTypes, ['default', 'delivery']);
  });
}
