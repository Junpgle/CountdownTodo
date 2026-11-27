import 'package:countdown_todo/features/habits/widgets/habit_guide_faq.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleItems = [
    HabitGuideFaqItem('问题一？', '这是第一条解答。'),
    HabitGuideFaqItem('问题二？', '这是第二条解答。'),
  ];

  testWidgets(
    'HabitGuideFaq renders collapsed title and expands items on tap',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HabitGuideFaq(items: sampleItems)),
        ),
      );

      expect(find.text('常见问题'), findsOneWidget);
      expect(find.text('问题一？'), findsNothing);
      expect(find.text('这是第一条解答。'), findsNothing);

      await tester.tap(find.text('常见问题'));
      await tester.pumpAndSettle();

      expect(find.text('问题一？'), findsOneWidget);
      expect(find.text('这是第一条解答。'), findsOneWidget);
      expect(find.text('问题二？'), findsOneWidget);
      expect(find.text('这是第二条解答。'), findsOneWidget);
    },
  );

  testWidgets('HabitGuideFaq supports custom title and initiallyExpanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HabitGuideFaq(
            title: '阅读常见疑问',
            initiallyExpanded: true,
            items: sampleItems,
          ),
        ),
      ),
    );

    expect(find.text('阅读常见疑问'), findsOneWidget);
    expect(find.text('问题一？'), findsOneWidget);
    expect(find.text('这是第二条解答。'), findsOneWidget);
  });
}
