import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/app_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MissionControl keeps scheduled and unscheduled task labels', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 18, 8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MissionControl(
            todos: [
              TodoItem(
                title: '有截止时间',
                creatorName: '小明',
                dueDate: DateTime(2026, 10, 18, 9, 5),
              ),
              TodoItem(title: '无截止时间'),
            ],
            activeTab: 'active',
            onTabChanged: (_) {},
            onTaskClick: (_) {},
            clock: () => now,
          ),
        ),
      ),
    );

    expect(find.text('小明 · 09:05'), findsOneWidget);
    expect(find.text('用户 · 无时间'), findsOneWidget);
  });
}
