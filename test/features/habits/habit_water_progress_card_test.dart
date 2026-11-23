import 'package:countdown_todo/features/habits/widgets/habit_water_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('水杯进度卡展示今日累计、目标和剩余量', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HabitWaterProgressCard(
            currentValue: 700,
            targetValue: 2000,
            recordCount: 2,
          ),
        ),
      ),
    );

    expect(find.text('今日饮水'), findsOneWidget);
    expect(find.text('700 ml'), findsOneWidget);
    expect(find.text('目标 2000 ml · 35%'), findsOneWidget);
    expect(find.text('还差 1300 ml 达标'), findsOneWidget);
    expect(find.text('今天已记录 2 次 · 建议少量多次'), findsOneWidget);

    // 水面是持续动画，不能用 pumpAndSettle 等待到“静止”。
    await tester.pump(const Duration(milliseconds: 180));
  });

  testWidgets('超过目标时水杯仍封顶但显示超额百分比', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HabitWaterProgressCard(currentValue: 2400, targetValue: 2000),
        ),
      ),
    );

    expect(find.text('2400 ml'), findsOneWidget);
    expect(find.text('目标 2000 ml · 120%'), findsOneWidget);
    expect(find.text('今日目标已完成，继续少量多次即可。'), findsOneWidget);
  });
}
