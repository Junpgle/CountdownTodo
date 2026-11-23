import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/recognized_todo_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 31, 14, 30);

  group('RecognizedTodoAdapter', () {
    test('promotes an image pickup without a date to today date-only', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'title': '顺丰取件',
        'remark': '取件码 1234',
        'itemKind': 'todo',
        'timeMode': 'unscheduled',
        'isAllDay': false,
      }, now: now);

      expect(result['timeMode'], 'dateOnly');
      expect(result['isAllDay'], isTrue);
      expect(
        DateTime.parse(result['startTime'] as String),
        DateTime(2026, 8, 31),
      );
      expect(
        DateTime.parse(result['endTime'] as String),
        DateTime(2026, 8, 31, 23, 59),
      );
    });

    test('keeps an explicit special-todo deadline as a deadline', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'title': '取餐',
        'timeMode': 'deadline',
        'endTime': '2026-09-01T18:00:00',
      });

      expect(result['timeMode'], 'deadline');
      expect(result['isAllDay'], isFalse);
      expect(
        DateTime.parse(result['endTime'] as String),
        DateTime(2026, 9, 1, 18),
      );
    });

    test('does not turn an explicitly timed special todo into all-day', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'title': '外卖取餐',
        'startTime': '2026-09-01T18:00:00',
        'endTime': '2026-09-01T19:00:00',
      });

      expect(result['isAllDay'], isFalse);
      expect(result['timeMode'], TodoTimeMode.deadline.name);
      expect(result['startTime'], '2026-09-01T19:00:00.000');
      expect(result['endTime'], '2026-09-01T19:00:00.000');
    });

    test('preserves a fixed-schedule range while it is being confirmed', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'itemKind': 'fixedSchedule',
        'title': '项目会议',
        'timeMode': 'range',
        'startTime': '2026-09-01T09:00:00',
        'endTime': '2026-09-01T11:00:00',
      });

      expect(result['itemKind'], 'fixedSchedule');
      expect(result['timeMode'], 'range');
      expect(result['startTime'], '2026-09-01T09:00:00');
      expect(result['endTime'], '2026-09-01T11:00:00');
    });

    test('migrates the old midnight range to the date-only protocol', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'title': '外卖取餐',
        'startTime': '2026-08-31T00:00:00',
        'endTime': '2026-08-31T23:59:00',
      });

      expect(result['timeMode'], 'dateOnly');
      expect(result['isAllDay'], isTrue);
      expect(result['startTime'], '2026-08-31T00:00:00.000');
      expect(result['endTime'], '2026-08-31T23:59:00.000');
    });

    test('does not change a normal unscheduled todo', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'title': '买牛奶',
        'timeMode': 'unscheduled',
      });

      expect(result['timeMode'], 'unscheduled');
      expect(result['isAllDay'], false);
      expect(result['startTime'], isNull);
      expect(result['endTime'], isNull);
    });

    test(
      'normalizes a text todo deadline from the current dueDate protocol',
      () {
        final result = RecognizedTodoAdapter.normalizeResult({
          'title': '提交报告',
          'itemKind': 'todo',
          'timeMode': 'deadline',
          'dueDate': '2026-09-01T18:00:00',
        });

        expect(result['timeMode'], TodoTimeMode.deadline.name);
        expect(result['isAllDay'], isFalse);
        expect(result['dueDate'], '2026-09-01T18:00:00.000');
        expect(result['startTime'], '2026-09-01T18:00:00.000');
        expect(result['endTime'], '2026-09-01T18:00:00.000');
      },
    );

    test('normalizes a text todo date-only result without image promotion', () {
      final result = RecognizedTodoAdapter.normalizeResult({
        'title': '缴费',
        'itemKind': 'todo',
        'timeMode': 'dateOnly',
        'dueDate': '2026-09-02T23:59:00',
      });

      expect(result['timeMode'], TodoTimeMode.dateOnly.name);
      expect(result['isAllDay'], isTrue);
      expect(result['dueDate'], '2026-09-02T23:59:00.000');
    });

    test('recognizes numeric timestamps and snake_case fields', () {
      final result = RecognizedTodoAdapter.normalizeImageResult({
        'content': '取快递',
        'item_kind': 'todo',
        'time_mode': 'dateOnly',
        'start_time': DateTime(2026, 9, 2).toUtc().millisecondsSinceEpoch,
      });

      expect(result['title'], '取快递');
      expect(result['itemKind'], 'todo');
      expect(result['timeMode'], TodoTimeMode.dateOnly.name);
      expect(result['isAllDay'], isTrue);
      expect(
        DateTime.parse(result['startTime'] as String),
        DateTime(2026, 9, 2),
      );
    });
  });
}
