import 'package:countdown_todo/widgets/ai_water_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  testWidgets(
    'AiGeneratedTodoWaterBorder omits VisibilityDetector and settles cleanly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiGeneratedTodoWaterBorder(
              enabled: true,
              isLight: true,
              child: SizedBox(width: 240, height: 80),
            ),
          ),
        ),
      );

      expect(find.byType(VisibilityDetector), findsNothing);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.byType(AiGeneratedTodoWaterBorder), findsOneWidget);
    },
  );

  testWidgets('AiWaterRippleBorder settles after finite repeats', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiWaterRippleBorder(
            enabled: true,
            isLight: false,
            maxRepeats: 1,
            child: SizedBox(width: 200, height: 64),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.byType(AiWaterRippleBorder), findsOneWidget);
  });

  testWidgets(
    'AiWaterRippleBorder unmounts VisibilityDetector after finite motion settles',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AiWaterRippleBorder(
              enabled: true,
              isLight: false,
              visibleOnlyWhenInViewport: true,
              maxRepeats: 1,
              child: SizedBox(width: 200, height: 64),
            ),
          ),
        ),
      );

      expect(find.byType(VisibilityDetector), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.byType(VisibilityDetector), findsNothing);
      expect(find.byType(AiWaterRippleBorder), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
