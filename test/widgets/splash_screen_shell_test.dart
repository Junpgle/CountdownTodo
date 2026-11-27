import 'package:countdown_todo/widgets/splash_screen_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplashScreenShell', () {
    for (final afterFirstFrame in [false, true]) {
      testWidgets(
        'auto-completes once after displayDuration (afterFirstFrame=$afterFirstFrame)',
        (tester) async {
          var completions = 0;

          await tester.pumpWidget(
            MaterialApp(
              home: SplashScreenShell(
                onComplete: () => completions++,
                displayDuration: const Duration(milliseconds: 300),
                fadeDuration: const Duration(milliseconds: 100),
                startTimerAfterFirstFrame: afterFirstFrame,
                contentBuilder: (_, _, _, _, _) => const SizedBox(),
              ),
            ),
          );

          await tester.pump();
          expect(completions, 0);

          await tester.pump(const Duration(milliseconds: 250));
          expect(completions, 0);

          await tester.pump(const Duration(milliseconds: 100));
          expect(completions, 1);

          await tester.pump(const Duration(seconds: 1));
          expect(completions, 1);
        },
      );
    }

    testWidgets(
      'tapping skip completes immediately and prevents duplicate callback',
      (tester) async {
        var completions = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: SplashScreenShell(
              onComplete: () => completions++,
              displayDuration: const Duration(milliseconds: 500),
              contentBuilder: (_, _, _, _, _) => const SizedBox(),
            ),
          ),
        );

        await tester.tap(find.text('跳过'));
        await tester.pump();
        expect(completions, 1);

        await tester.pump(const Duration(seconds: 1));
        expect(completions, 1);
      },
    );

    testWidgets('disposing cancels pending completion timer', (tester) async {
      var completions = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreenShell(
            onComplete: () => completions++,
            displayDuration: const Duration(milliseconds: 500),
            contentBuilder: (_, _, _, _, _) => const SizedBox(),
          ),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 1));
      expect(completions, 0);
    });
  });
}
