import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/widgets/celebration/confetti_particle_canvas.dart';
import 'package:countdown_todo/widgets/celebration/liquid_glass_celebration_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfettiParticleCanvas', () {
    testWidgets('renders CustomPaint with particles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConfettiParticleCanvas(particleCount: 20)),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ConfettiParticleCanvas),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });
  });

  group('LiquidGlassCelebrationDialog', () {
    testWidgets(
      'renders header badge, title, content, description and dismisses',
      (tester) async {
        var dismissed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LiquidGlassCelebrationDialog(
                headerBadge: LiquidGlassCelebrationDialog.buildGradientBadge(
                  icon: Icons.star_rounded,
                ),
                title: '庆祝大标题',
                content: const Text('中间业务槽内容'),
                description: '这是一段励志名言或说明描述',
                actionLabel: '好的',
                actionKey: const ValueKey('dialog_action_btn'),
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        );

        // Verify components render
        expect(find.byIcon(Icons.star_rounded), findsOneWidget);
        expect(find.text('庆祝大标题'), findsOneWidget);
        expect(find.text('中间业务槽内容'), findsOneWidget);
        expect(find.text('这是一段励志名言或说明描述'), findsOneWidget);
        expect(find.text('好的'), findsOneWidget);

        // Tap action button
        await tester.tap(find.byKey(const ValueKey('dialog_action_btn')));
        await tester.pump();
        expect(dismissed, isTrue);
      },
    );

    testWidgets('show helper displays and closes dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  LiquidGlassCelebrationDialog.show(
                    context: context,
                    builder: (dialogCtx) => LiquidGlassCelebrationDialog(
                      title: '弹窗测试',
                      onDismiss: () => Navigator.of(dialogCtx).pop(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('弹窗测试'), findsOneWidget);

      // Tap default action button
      await tester.tap(find.text('太棒了'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('弹窗测试'), findsNothing);
    });
  });
}
