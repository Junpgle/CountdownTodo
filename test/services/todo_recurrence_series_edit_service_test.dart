import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_recurrence_series_edit_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TodoItem item(
    String id,
    DateTime start, {
    bool done = false,
    bool skipped = false,
    String seriesId = 'series-a',
  }) =>
      TodoItem(
        id: id,
        title: id,
        isDone: done,
        isSkipped: skipped,
        recurrenceSeriesId: seriesId,
        createdDate: start.toUtc().millisecondsSinceEpoch,
      );

  test('系列成员和状态分布包含所有未删除真实期次', () {
    final todos = [
      item('past', DateTime(2026, 10, 19), done: true),
      item('today', DateTime(2026, 10, 20), skipped: true),
      item('future', DateTime(2026, 10, 21)),
      item('deleted', DateTime(2026, 10, 22))..isDeleted = true,
      item('other', DateTime(2026, 10, 20), seriesId: 'series-b'),
    ];

    final members = TodoRecurrenceSeriesEditService.activeMembers(
      todos,
      'series-a',
    );
    final counts = TodoRecurrenceSeriesEditService.countMembers(
      todos,
      'series-a',
      now: DateTime(2026, 10, 20, 12),
    );

    expect(members.map((todo) => todo.id), ['past', 'today', 'future']);
    expect(counts.total, 3);
    expect(counts.historical, 1);
    expect(counts.current, 1);
    expect(counts.future, 1);
    expect(counts.completed, 1);
    expect(counts.skipped, 1);
  });

  test('老式无系列字段的重复锚点使用自身 UUID 作为系列标识', () {
    final anchor = TodoItem(
      id: 'legacy-anchor',
      title: 'legacy',
      recurrence: RecurrenceType.weekly,
    );
    final generated = TodoItem(
      id: 'legacy-occurrence',
      title: 'legacy',
      recurrenceSeriesId: 'legacy-anchor',
    );

    expect(
      TodoRecurrenceSeriesEditService.seriesIdFor(anchor),
      'legacy-anchor',
    );
    expect(
      TodoRecurrenceSeriesEditService.activeMemberIds(
        [anchor, generated],
        'legacy-anchor',
      ),
      {'legacy-anchor', 'legacy-occurrence'},
    );
  });

  test('结束日期按本地日历日平移并保留时刻', () {
    final shifted = TodoRecurrenceSeriesEditService.shiftCalendarDate(
      DateTime(2026, 10, 31, 8, 45),
      2,
    );

    expect(shifted, DateTime(2026, 11, 2, 8, 45));
  });
}
