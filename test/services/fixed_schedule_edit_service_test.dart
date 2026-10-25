import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/fixed_schedule_edit_service.dart';
import 'package:countdown_todo/services/fixed_schedule_recurrence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FixedScheduleEditService', () {
    late List<FixedScheduleItem> series;

    setUp(() {
      final root = FixedScheduleItem(
        id: 'weekly-root',
        title: '周会',
        date: '2026-10-19',
        startTime: DateTime(2026, 10, 19, 9).millisecondsSinceEpoch,
        endTime: DateTime(2026, 10, 19, 10).millisecondsSinceEpoch,
        recurrence: RecurrenceType.weekly,
        recurrenceSeriesId: 'weekly-root',
        externalSource: 'calendar-a',
        externalId: 'event-root',
        relatedTodoIds: const ['agenda-root'],
      );
      series = FixedScheduleRecurrenceService.rebuildSeries(
        template: root,
        existingSeries: const [],
        recurrence: RecurrenceType.weekly,
        recurrenceEndDate: DateTime(2026, 11, 2),
      ).active;
      series[0].status = FixedScheduleStatus.finished;
      series[1].status = FixedScheduleStatus.cancelled;
      series[1].relatedTodoIds = ['agenda-second'];
      series[1].externalId = 'event-second';
      series[2].relatedTodoIds = ['agenda-third'];
      series[2].externalId = 'event-third';
    });

    test('editing one occurrence leaves every other instance untouched', () {
      final selected = series[1];
      final edited = FixedScheduleItem.fromJson(selected.toJson())
        ..title = '周会改期'
        ..status = FixedScheduleStatus.scheduled
        ..remark = '只改本次';

      final result = FixedScheduleEditService.buildChanges(
        scope: FixedScheduleEditScope.occurrence,
        selectedOccurrence: selected,
        existingSeries: series,
        editedTemplate: edited,
        recurrence: RecurrenceType.weekly,
        recurrenceEndDate: DateTime(2026, 11, 2),
      );

      expect(result.changes, hasLength(1));
      expect(result.affected.single.id, selected.id);
      expect(result.affected.single.title, '周会改期');
      expect(result.affected.single.status, FixedScheduleStatus.scheduled);
      expect(result.affected.single.recurrenceSeriesId, 'weekly-root');
      expect(result.affected.single.relatedTodoIds, ['agenda-second']);
      expect(series[0].status, FixedScheduleStatus.finished);
      expect(series[0].title, '周会');
      expect(series[2].status, FixedScheduleStatus.scheduled);
      expect(series[2].title, '周会');
    });

    test(
      'moving one occurrence cancels its old slot and creates a standalone',
      () {
        final selected = series[1];
        final edited = FixedScheduleItem.fromJson(selected.toJson())
          ..date = '2026-11-05'
          ..startTime = DateTime(2026, 11, 5, 11).millisecondsSinceEpoch
          ..endTime = DateTime(2026, 11, 5, 12).millisecondsSinceEpoch;

        final result = FixedScheduleEditService.buildChanges(
          scope: FixedScheduleEditScope.occurrence,
          selectedOccurrence: selected,
          existingSeries: series,
          editedTemplate: edited,
          recurrence: RecurrenceType.weekly,
          recurrenceEndDate: DateTime(2026, 11, 2),
        );

        final oldSlot = result.changes.firstWhere(
          (item) => item.id == selected.id,
        );
        final exception = result.refreshItem;
        expect(oldSlot.date, selected.date);
        expect(oldSlot.status, FixedScheduleStatus.cancelled);
        expect(oldSlot.recurrenceSeriesId, 'weekly-root');
        expect(exception.id, isNot(selected.id));
        expect(exception.date, '2026-11-05');
        expect(exception.recurrence, RecurrenceType.none);
        expect(exception.recurrenceSeriesId, isNull);
        expect(exception.relatedTodoIds, ['agenda-second']);
        expect(exception.externalId, isNull);
      },
    );

    test(
      'editing this and future splits the series and preserves its past',
      () {
        final selected = series[1];
        final edited = FixedScheduleItem.fromJson(selected.toJson())
          ..title = '新周会';

        final result = FixedScheduleEditService.buildChanges(
          scope: FixedScheduleEditScope.future,
          selectedOccurrence: selected,
          existingSeries: series,
          editedTemplate: edited,
          recurrence: RecurrenceType.weekly,
          recurrenceEndDate: DateTime(2026, 11, 9),
        );

        expect(result.affected.map((item) => item.date), [
          '2026-10-26',
          '2026-11-02',
          '2026-11-09',
        ]);
        expect(result.affected.map((item) => item.recurrenceSeriesId).toSet(), {
          selected.id,
        });
        expect(result.affected.map((item) => item.relatedTodoIds), [
          ['agenda-second'],
          ['agenda-third'],
          ['agenda-second'],
        ]);
        expect(
          result.changes.map((item) => item.id),
          isNot(contains(series[0].id)),
        );
        expect(series[0].title, '周会');
        expect(series[0].recurrenceSeriesId, 'weekly-root');
        expect(series[0].status, FixedScheduleStatus.finished);
      },
    );

    test(
      'editing the full series preserves per-occurrence identity and status',
      () {
        final selected = series[1];
        final edited = FixedScheduleItem.fromJson(selected.toJson())
          ..title = '全系列周会'
          ..date = series.first.date;

        final result = FixedScheduleEditService.buildChanges(
          scope: FixedScheduleEditScope.series,
          selectedOccurrence: selected,
          existingSeries: series,
          editedTemplate: edited,
          recurrence: RecurrenceType.weekly,
          recurrenceEndDate: DateTime(2026, 11, 2),
        );

        expect(
          result.affected.map((item) => item.id),
          series.map((item) => item.id),
        );
        expect(result.affected.map((item) => item.title).toSet(), {'全系列周会'});
        expect(result.affected[0].status, FixedScheduleStatus.finished);
        expect(result.affected[1].status, FixedScheduleStatus.cancelled);
        expect(result.affected.map((item) => item.externalId), [
          'event-root',
          'event-second',
          'event-third',
        ]);
        expect(result.affected.map((item) => item.relatedTodoIds), [
          ['agenda-root'],
          ['agenda-second'],
          ['agenda-third'],
        ]);
      },
    );

    test('applying related todos changes only the selected occurrence', () {
      final selected = series[1];
      final edited = FixedScheduleItem.fromJson(selected.toJson())
        ..relatedTodoIds = ['exam-review', 'bring-id'];

      final result = FixedScheduleEditService.buildChanges(
        scope: FixedScheduleEditScope.occurrence,
        selectedOccurrence: selected,
        existingSeries: series,
        editedTemplate: edited,
        recurrence: RecurrenceType.weekly,
        recurrenceEndDate: DateTime(2026, 11, 2),
        applyRelatedTodoIds: true,
      );

      expect(result.affected.single.relatedTodoIds, [
        'exam-review',
        'bring-id',
      ]);
      expect(series[0].relatedTodoIds, ['agenda-root']);
      expect(series[2].relatedTodoIds, ['agenda-third']);
    });

    test(
      'applying related todos to this and future preserves earlier links',
      () {
        final selected = series[1];
        final edited = FixedScheduleItem.fromJson(selected.toJson())
          ..relatedTodoIds = ['exam-review'];

        final result = FixedScheduleEditService.buildChanges(
          scope: FixedScheduleEditScope.future,
          selectedOccurrence: selected,
          existingSeries: series,
          editedTemplate: edited,
          recurrence: RecurrenceType.weekly,
          recurrenceEndDate: DateTime(2026, 11, 9),
          applyRelatedTodoIds: true,
        );

        expect(result.affected, hasLength(3));
        expect(
          result.affected.map((item) => item.relatedTodoIds),
          everyElement(['exam-review']),
        );
        expect(series[0].relatedTodoIds, ['agenda-root']);
      },
    );

    test(
      'applying related todos to the whole series replaces every link list',
      () {
        final selected = series[1];
        final edited = FixedScheduleItem.fromJson(selected.toJson())
          ..date = series.first.date
          ..relatedTodoIds = ['exam-review', 'bring-id'];

        final result = FixedScheduleEditService.buildChanges(
          scope: FixedScheduleEditScope.series,
          selectedOccurrence: selected,
          existingSeries: series,
          editedTemplate: edited,
          recurrence: RecurrenceType.weekly,
          recurrenceEndDate: DateTime(2026, 11, 2),
          applyRelatedTodoIds: true,
        );

        expect(result.affected, hasLength(3));
        expect(
          result.affected.map((item) => item.relatedTodoIds),
          everyElement(['exam-review', 'bring-id']),
        );
      },
    );
  });
}
