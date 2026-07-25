import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/todo_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodoParserService time semantics', () {
    test('plain text stays unscheduled', () {
      final result = TodoParserService.parse('买牛奶');

      expect(result.startTime, isNull);
      expect(result.endTime, isNull);
      expect(result.isAllDay, isFalse);
    });

    test('a date without a clock becomes a date-only todo', () {
      final result = TodoParserService.parse('明天取快递');

      expect(result.isAllDay, isTrue);
      expect(result.startTime, isNotNull);
      expect(result.startTime!.hour, 0);
      expect(result.endTime, isNull);
    });

    test('a single clock time is a deadline and does not gain one hour', () {
      final result = TodoParserService.parse('明天18点前交作业');

      expect(result.isAllDay, isFalse);
      expect(result.startTime, isNotNull);
      expect(result.startTime!.hour, 0);
      expect(result.endTime, isNotNull);
      expect(result.endTime!.hour, 18);
      expect(result.endTime!.minute, 0);
    });

    test('recurrence words still describe a recurring todo', () {
      final result = TodoParserService.parse('每天9点吃药');

      expect(result.recurrence, RecurrenceType.daily);
      expect(result.startTime!.hour, 0);
      expect(result.endTime!.hour, 9);
    });
  });
}
