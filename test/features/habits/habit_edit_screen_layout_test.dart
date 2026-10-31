import 'package:countdown_todo/features/habits/screens/habit_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'HabitEditScreen next button floats at the bottom of the screen in mobile portrait',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: HabitEditScreen()));
      await tester.pumpAndSettle();

      // Step 0: "下一步" button should be near bottom right.
      final nextButtonFinder = find.widgetWithText(FilledButton, '下一步');
      expect(nextButtonFinder, findsOneWidget);

      final buttonRect = tester.getRect(nextButtonFinder);
      expect(buttonRect.top, greaterThan(700.0));
      expect(buttonRect.right, greaterThan(250.0));

      // Choose "手动自定义" and enter habit name.
      await tester.tap(find.text('手动自定义'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField).first;
      await tester.enterText(textField, '晨跑');
      await tester.pumpAndSettle();

      // Now tap "下一步" to go to step 1.
      await tester.tap(nextButtonFinder);
      await tester.pumpAndSettle();

      // Step 1: Both "上一步" and "下一步" should be present at the bottom.
      final prevButtonFinder = find.widgetWithText(OutlinedButton, '上一步');
      expect(prevButtonFinder, findsOneWidget);
      expect(find.widgetWithText(FilledButton, '下一步'), findsOneWidget);

      final prevRect = tester.getRect(prevButtonFinder);
      final nextRect = tester.getRect(find.widgetWithText(FilledButton, '下一步'));

      expect(prevRect.top, greaterThan(700.0));
      expect(nextRect.top, greaterThan(700.0));
      // "上一步" should be to the left of "下一步".
      expect(prevRect.right, lessThan(nextRect.left));
    },
  );

  testWidgets('HabitEditScreen renders properly on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: HabitEditScreen()));
    await tester.pumpAndSettle();

    final nextButtonFinder = find.widgetWithText(FilledButton, '下一步');
    expect(nextButtonFinder, findsOneWidget);
  });
}
