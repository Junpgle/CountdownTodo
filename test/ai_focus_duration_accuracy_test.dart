import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/services/ai_todo_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'efficiency totals add exact focus seconds before rounding to minutes',
    () {
      final firstStart = DateTime(2026, 9, 1, 9);
      final timeLogs = [
        for (var index = 0; index < 30; index++)
          TimeLogItem(
            id: 'short-$index',
            title: '短时专注 $index',
            startTime: firstStart
                .add(Duration(seconds: index * 20))
                .millisecondsSinceEpoch,
            endTime: firstStart
                .add(Duration(seconds: index * 20 + 20))
                .millisecondsSinceEpoch,
          ),
      ];

      final context = AiTodoContextBuilder.buildContextInjection(
        userMessage: '分析2026-09-01的效率',
        courses: const [],
        timeLogs: timeLogs,
        conflicts: const [],
        teams: const [],
        now: DateTime(2026, 10, 2, 12),
      )!;

      expect(context, contains('2026-09-01合计: 10分钟'));
      expect(context, contains('本时段计入20秒'));
    },
  );
}
