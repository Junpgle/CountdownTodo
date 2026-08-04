import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:countdown_todo/features/habits/widgets/habit_time_point_chart.dart';

void main() {
  testWidgets('时间点折线图可以渲染记录、目标线和缺失日期', (tester) async {
    final baseDate = DateTime(2026, 8, 4);
    final data = [
      HabitTimePointChartData(
        date: baseDate,
        actualTime: DateTime(2026, 8, 4, 7, 10),
        onTime: true,
        targetTimeMinute: 7 * 60,
      ),
      HabitTimePointChartData(
        date: baseDate.add(const Duration(days: 1)),
        actualTime: null,
        onTime: false,
        targetTimeMinute: 7 * 60,
      ),
      HabitTimePointChartData(
        date: baseDate.add(const Duration(days: 2)),
        actualTime: DateTime(2026, 8, 6, 8, 5),
        onTime: false,
        targetTimeMinute: 7 * 60,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HabitTimePointChart(data: data),
        ),
      ),
    );

    expect(find.byType(HabitTimePointChart), findsOneWidget);
    expect(
      find.byKey(const ValueKey('habit-time-point-chart-canvas')),
      findsOneWidget,
    );
    expect(data[0].actualTimeMinute, 7 * 60 + 10);
    expect(data[1].actualTimeMinute, isNull);

    final bedtimeTarget = HabitTimePointChartData(
      date: DateTime(2026, 8, 4),
      actualTime: DateTime(2026, 8, 5, 0, 30),
      onTime: true,
      targetTimeMinute: 23 * 60,
    );
    expect(bedtimeTarget.displayTargetTimeMinute, 23 * 60);
    expect(bedtimeTarget.displayActualTimeMinute, 24 * 60 + 30);
  });
}
