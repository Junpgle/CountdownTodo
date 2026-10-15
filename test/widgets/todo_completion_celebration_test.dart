import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/services/todo_completion_celebration_service.dart';
import 'package:countdown_todo/widgets/todo_completion_celebration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TodoCelebrationOverlay', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await TodoCompletionCelebrationService.ensureInitialized();
      await TodoCompletionCelebrationService.setCelebrationEnabled(true);
    });

    testWidgets(
      'renders celebration title, completed count, and dismisses on button tap',
      (tester) async {
        var dismissed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TodoCelebrationOverlay(
                completedTodayCount: 5,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        );

        // Verify header and content
        expect(find.text('今日待办全部达成！'), findsOneWidget);
        expect(find.textContaining('今日已完成 5 项任务'), findsOneWidget);
        expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);

        // Tap dismiss button
        final btn = find.byKey(const ValueKey('celebration_dismiss_btn'));
        expect(btn, findsOneWidget);
        await tester.tap(btn);
        await tester.pump();

        expect(dismissed, isTrue);
      },
    );

    testWidgets('showTodoAllDoneCelebration shows dialog when enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showTodoAllDoneCelebration(context, completedTodayCount: 3);
                },
                child: const Text('Show Celebration'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Celebration'));
      await tester.pump(); // Start dialog transition
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // Complete dialog open

      expect(find.text('今日待办全部达成！'), findsOneWidget);
      expect(find.textContaining('今日已完成 3 项任务'), findsOneWidget);

      // Tap dismiss
      await tester.tap(find.byKey(const ValueKey('celebration_dismiss_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('今日待办全部达成！'), findsNothing);
    });

    testWidgets(
      'showTodoAllDoneCelebration does nothing when celebration is disabled',
      (tester) async {
        await TodoCompletionCelebrationService.setCelebrationEnabled(false);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showTodoAllDoneCelebration(context, completedTodayCount: 4);
                  },
                  child: const Text('Show Celebration'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Celebration'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('今日待办全部达成！'), findsNothing);
      },
    );
  });
}
