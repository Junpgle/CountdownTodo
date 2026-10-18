import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/fixed_schedule_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the date and known fixed schedule times', (tester) async {
    final item = FixedScheduleItem(
      title: '考试',
      date: '2026-12-04',
      startTime: DateTime(2026, 12, 4, 9, 15).millisecondsSinceEpoch,
      endTime: DateTime(2026, 12, 4, 10, 45).millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(username: 'tester', item: item),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月4日 · 09:15 - 10:45'), findsOneWidget);
    expect(find.text('2026年12月4日'), findsOneWidget);
    expect(find.text('09:15'), findsOneWidget);
    expect(find.text('10:45'), findsOneWidget);
  });

  testWidgets('preserves the time-undetermined labels', (tester) async {
    final item = FixedScheduleItem(title: '待定日程', date: '2026-12-04');

    await tester.pumpWidget(
      MaterialApp(
        home: FixedScheduleDetailScreen(username: 'tester', item: item),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月4日 · 时间待定'), findsOneWidget);
    expect(find.text('待定'), findsNWidgets(2));
  });
}
