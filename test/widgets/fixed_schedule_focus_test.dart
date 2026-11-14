import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:countdown_todo/screens/fixed_schedule_editor_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Selecting options in FixedScheduleEditorScreen does not refocus title text field',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: FixedScheduleEditorScreen(
            username: 'test_user',
            loadTeams: () async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find title TextField (hintText "日程名称 (例如：算法设计与分析实验)")
      final titleFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText?.contains('日程名称') == true,
      );
      expect(titleFinder, findsOneWidget);

      // 1. Focus title and enter text
      await tester.tap(titleFinder);
      await tester.enterText(titleFinder, '高数课');
      await tester.pump();

      final titleEditable = find.descendant(
        of: titleFinder,
        matching: find.byType(EditableText),
      );
      final titleFocusNode =
          (tester.widget(titleEditable) as EditableText).focusNode;
      expect(titleFocusNode.hasFocus, isTrue);

      // 2. Open "重复规则" popup menu
      final recurrenceFinder = find.text('重复规则');
      expect(recurrenceFinder, findsOneWidget);
      await tester.tap(recurrenceFinder);
      await tester.pumpAndSettle();

      // Select "每天"
      final optionDaily = find.text('每天');
      expect(optionDaily, findsOneWidget);
      await tester.tap(optionDaily);
      await tester.pumpAndSettle();

      // Verify title field is NOT focused
      expect(titleFocusNode.hasFocus, isFalse);

      // 3. Focus title again
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 4. Toggle "时间待定" switch
      final timeTbdSwitch = find.byKey(
        const ValueKey('fixed-schedule-time-tbd'),
      );
      expect(timeTbdSwitch, findsOneWidget);
      await tester.tap(timeTbdSwitch);
      await tester.pumpAndSettle();

      // Verify title field is NOT focused
      expect(titleFocusNode.hasFocus, isFalse);

      // Toggle back to enable time pickers
      await tester.tap(timeTbdSwitch);
      await tester.pumpAndSettle();

      // 5. Focus title again
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 6. Tap "开始时间" tile
      final startTimeFinder = find.byKey(
        const ValueKey('fixed-schedule-start-time'),
      );
      expect(startTimeFinder, findsOneWidget);
      await tester.tap(startTimeFinder);
      await tester.pumpAndSettle();

      // Time picker dialog is open. Tap "确定" (or OK)
      final okButton = find.text('确定');
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton);
      } else {
        await tester.tap(find.text('OK'));
      }
      await tester.pumpAndSettle();

      // Verify title field is NOT focused
      expect(titleFocusNode.hasFocus, isFalse);

      // 7. Focus title again
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      // 8. Tap "首次日期" / "日期" tile
      final dateFinder = find.byKey(const ValueKey('fixed-schedule-date'));
      expect(dateFinder, findsOneWidget);
      await tester.tap(dateFinder);
      await tester.pumpAndSettle();

      // Date picker dialog is open. Tap "确定" (or OK)
      final dateOkButton = find.text('确定');
      if (dateOkButton.evaluate().isNotEmpty) {
        await tester.tap(dateOkButton);
      } else {
        await tester.tap(find.text('OK'));
      }
      await tester.pumpAndSettle();

      // Verify title field is NOT focused
      expect(titleFocusNode.hasFocus, isFalse);

      // 9. Focus title again and tap blank background
      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      await tester.tapAt(const Offset(750, 950));
      await tester.pump();
      expect(titleFocusNode.hasFocus, isFalse);

      // 10. Test scroll drag dismiss under constrained viewport
      tester.view.physicalSize = const Size(400, 500);
      await tester.pump();

      await tester.tap(titleFinder);
      await tester.pump();
      expect(titleFocusNode.hasFocus, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(titleFocusNode.hasFocus, isFalse);
    },
  );
}
