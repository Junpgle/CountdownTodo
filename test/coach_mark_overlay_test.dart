import 'package:CountDownTodo/widgets/coach_mark_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('show completes only after the guide finishes', (tester) async {
    final targetKey = GlobalKey();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 100),
                  SizedBox(
                    key: targetKey,
                    width: 80,
                    height: 40,
                    child: const Text('target'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    var completed = false;
    final result = CoachMarkOverlay.show(
      context: pageContext,
      steps: [
        CoachMarkStep(
          targetKey: targetKey,
          title: '首页指引',
          description: '操作说明',
        ),
      ],
      onFinish: () {},
      onSkip: () {},
    );
    result.then((_) => completed = true);

    await tester.pumpAndSettle();
    expect(completed, isFalse);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(completed, isTrue);
    expect(find.text('首页指引'), findsNothing);
  });

  testWidgets('show reports when the guide is skipped', (tester) async {
    final targetKey = GlobalKey();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 100),
                  SizedBox(
                    key: targetKey,
                    width: 80,
                    height: 40,
                    child: const Text('target'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final result = CoachMarkOverlay.show(
      context: pageContext,
      steps: [
        CoachMarkStep(
          targetKey: targetKey,
          title: '首页指引',
          description: '操作说明',
        ),
      ],
      onFinish: () {},
      onSkip: () {},
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过教程'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
    expect(find.text('首页指引'), findsNothing);
  });
}
