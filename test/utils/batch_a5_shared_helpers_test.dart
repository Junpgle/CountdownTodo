import 'dart:convert';

import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_tool_chat/ai_cdt_action_labels.dart';
import 'package:countdown_todo/services/time_estimation_service.dart';
import 'package:countdown_todo/utils/digest_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TimeEstimationService exposes non-empty canonical complexity keywords',
    () {
      expect(TimeEstimationService.highComplexityKeywords, contains('架构'));
      expect(TimeEstimationService.mediumComplexityKeywords, contains('整理'));
      expect(TimeEstimationService.lowComplexityKeywords, contains('打卡'));
    },
  );

  test('cdtActionDisplayLabel maps known actions and falls back cleanly', () {
    expect(cdtActionDisplayLabel('create_todo'), '新建待办');
    expect(cdtActionDisplayLabel('delete_pomodoro_tag'), '删除番茄标签');
    expect(cdtActionDisplayLabel('unknown_action'), 'unknown_action');
  });

  test(
    'parseRecurrenceType handles strings, enum values, indices, and null',
    () {
      expect(parseRecurrenceType('daily'), RecurrenceType.daily);
      expect(parseRecurrenceType('weekly'), RecurrenceType.weekly);
      expect(parseRecurrenceType('monthly'), RecurrenceType.monthly);
      expect(parseRecurrenceType('yearly'), RecurrenceType.yearly);
      expect(parseRecurrenceType('weekdays'), RecurrenceType.weekdays);
      expect(parseRecurrenceType('customDays'), RecurrenceType.customDays);
      expect(
        parseRecurrenceType(RecurrenceType.monthly),
        RecurrenceType.monthly,
      );
      expect(
        parseRecurrenceType(RecurrenceType.weekly.index),
        RecurrenceType.weekly,
      );
      expect(
        parseRecurrenceType('${RecurrenceType.yearly.index}'),
        RecurrenceType.yearly,
      );
      expect(parseRecurrenceType('unknown'), RecurrenceType.none);
      expect(parseRecurrenceType(-1), RecurrenceType.none);
      expect(parseRecurrenceType(null), RecurrenceType.none);
    },
  );

  test('SingleDigestSink captures chunked sha256 digest', () {
    final sink = SingleDigestSink();
    final input = sha256.startChunkedConversion(sink);
    input.add(utf8.encode('countdown-todo'));
    input.close();

    expect(
      sink.requireValue.toString(),
      sha256.convert(utf8.encode('countdown-todo')).toString(),
    );
  });
}
