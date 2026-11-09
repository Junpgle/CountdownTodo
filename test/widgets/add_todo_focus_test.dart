import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/screens/add_todo_screen.dart';

void main() {
  testWidgets(
    'Selecting options in AddTodoScreen does not refocus title text field',
    (tester) async {
      final groups = [
        TodoGroup(id: 'group-1', name: '工作'),
        TodoGroup(id: 'group-2', name: '生活'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddTodoScreen(username: 'test_user', todoGroups: groups),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.byKey(const ValueKey('manual-todo-title'));
      expect(titleFinder, findsOneWidget);

      // 1. Focus title and enter text
      await tester.tap(titleFinder);
      await tester.enterText(titleFinder, '测试待办标题');
      await tester.pump();

      final titleEditable = find.descendant(
        of: titleFinder,
        matching: find.byType(EditableText),
      );
      final titleFocusNode =
          (tester.widget(titleEditable) as EditableText).focusNode;
      expect(titleFocusNode.hasFocus, isTrue);

      // 2. Tap "提醒"
      final reminderFinder = find.text('提醒');
      await tester.ensureVisible(reminderFinder);
      await tester.tap(reminderFinder);
      await tester.pumpAndSettle();

      // Select "提前 15 分钟"
      final option15 = find.text('提前 15 分钟');
      expect(option15, findsOneWidget);
      await tester.tap(option15);
      await tester.pumpAndSettle();

      // Verify title did NOT regain focus
      expect(titleFocusNode.hasFocus, isFalse);

      // 3. Focus title again
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 4. Tap "重复规则"
      final recurrenceFinder = find.text('重复规则');
      await tester.ensureVisible(recurrenceFinder);
      await tester.tap(recurrenceFinder);
      await tester.pumpAndSettle();

      // Select "每天重复"
      final optionDaily = find.text('每天重复');
      expect(optionDaily, findsOneWidget);
      await tester.tap(optionDaily);
      await tester.pumpAndSettle();

      // Verify title did NOT regain focus
      expect(titleFocusNode.hasFocus, isFalse);

      // 5. Focus title again
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 6. Tap "归属文件夹"
      final groupFinder = find.text('归属文件夹');
      await tester.ensureVisible(groupFinder);
      await tester.tap(groupFinder);
      await tester.pumpAndSettle();

      // Select "工作"
      final groupOption = find.text('工作');
      expect(groupOption, findsOneWidget);
      await tester.tap(groupOption);
      await tester.pumpAndSettle();

      // Verify title did NOT regain focus
      expect(titleFocusNode.hasFocus, isFalse);

      // 7. Focus title again
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 8. Tap "截止时间"
      final deadlineFinder = find.text('截止时间');
      await tester.ensureVisible(deadlineFinder);
      await tester.tap(deadlineFinder);
      await tester.pumpAndSettle();

      // Date picker dialog is showing -> tap OK button
      final okFinder = find.text('OK');
      expect(okFinder, findsOneWidget);
      await tester.tap(okFinder);
      await tester.pumpAndSettle();

      // Time picker dialog is showing -> tap OK button
      final okTimeFinder = find.text('OK');
      expect(okTimeFinder, findsOneWidget);
      await tester.tap(okTimeFinder);
      await tester.pumpAndSettle();

      // Verify title did NOT regain focus after picking date and time!
      expect(titleFocusNode.hasFocus, isFalse);

      // 9. Focus title again
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 10. Tap empty space at bottom of scroll view
      final scrollFinder = find.byType(SingleChildScrollView);
      final scrollRect = tester.getRect(scrollFinder);
      await tester.tapAt(Offset(scrollRect.center.dx, scrollRect.bottom - 10));
      await tester.pumpAndSettle();

      // Verify title is unfocused after tapping outside
      expect(titleFocusNode.hasFocus, isFalse);
    },
  );
}
