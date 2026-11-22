import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Probe extends StatefulWidget {
  const Probe({super.key, required this.builds});
  final List<int> builds;
  @override
  State<Probe> createState() => _ProbeState();
}

class PomodoroScreen extends StatelessWidget {
  const PomodoroScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _ProbeState extends State<Probe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.builds.add(1);
  }

  @override
  Widget build(BuildContext context) {
    widget.builds.add(0);
    return const SizedBox.expand();
  }
}

final Key placeholderKey = const ValueKey('page-lazy-placeholder');

Future<AnimationController> setupLazy(
  WidgetTester tester, {
  required bool lazyLoad,
}) async {
  SharedPreferences.setMockInitialValues({
    'enable_lazy_load': lazyLoad,
    'enable_animations': true,
    'animation_duration': 500,
  });
  await PageTransitions.init();
  final controller = AnimationController(
    vsync: tester,
    duration: const Duration(seconds: 1),
  );
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LazyPageReveal defers content until the entrance completes', (
    tester,
  ) async {
    final controller = await setupLazy(tester, lazyLoad: true);
    addTearDown(controller.dispose);
    final builds = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LazyPageReveal(
          animation: controller,
          child: Probe(builds: builds),
        ),
      ),
    );
    await tester.pump();

    // 动画未推进：只有占位遮罩层，目标页面完全不构建。
    expect(find.byKey(placeholderKey), findsOneWidget);
    expect(find.byIcon(Icons.blur_on_rounded), findsOneWidget);
    expect(builds, isEmpty);

    // 动画中段：仍在遮罩层。
    controller.forward();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(placeholderKey), findsOneWidget);
    final midBuilds = builds.length;

    // 动画完成：内容从中心展开揭示，遮罩淡出。
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byKey(placeholderKey), findsNothing);
    expect(builds.length, greaterThan(midBuilds));
  });

  testWidgets('LazyPageReveal accepts a semantic icon', (tester) async {
    final controller = await setupLazy(tester, lazyLoad: true);
    addTearDown(controller.dispose);
    controller.value = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: LazyPageReveal(
          animation: controller,
          icon: Icons.calendar_month_rounded,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
    expect(find.byIcon(Icons.blur_on_rounded), findsNothing);
  });

  testWidgets('LazyPageReveal reveals immediately when lazy load is off', (
    tester,
  ) async {
    final controller = await setupLazy(tester, lazyLoad: false);
    addTearDown(controller.dispose);
    final builds = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LazyPageReveal(
          animation: controller,
          child: Probe(builds: builds),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(placeholderKey), findsNothing);
    expect(builds, isNotEmpty);
  });

  testWidgets('an entrance that is already complete reveals instantly', (
    tester,
  ) async {
    final controller = await setupLazy(tester, lazyLoad: true);
    addTearDown(controller.dispose);
    controller.value = 1.0;
    final builds = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LazyPageReveal(
          animation: controller,
          child: Probe(builds: builds),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 挂载时入场已经结束（无进行中的转场）→ 不需要遮罩，直接显示内容。
    expect(find.byKey(placeholderKey), findsNothing);
    expect(builds, isNotEmpty);
  });

  testWidgets('container transform reveals its page (smoke)', (tester) async {
    await setupLazy(tester, lazyLoad: true);
    final builds = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                ContainerTransformRoute<void>(
                  page: Probe(builds: builds),
                  sourceRect: const Rect.fromLTWH(40, 40, 120, 80),
                  sourceColor: Colors.blue,
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    builds.clear();

    await tester.tap(find.text('go'));
    // 给足时间：入场转场 + 兜底定时器 + 揭示过渡全部完成。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(builds, isNotEmpty, reason: '容器变换结束后应构建并显示真实页面');
  });

  testWidgets('container transform uses the original page semantic icon', (
    tester,
  ) async {
    await setupLazy(tester, lazyLoad: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                ContainerTransformRoute<void>(
                  page: const PomodoroScreen(),
                  sourceRect: const Rect.fromLTWH(40, 40, 120, 80),
                  sourceColor: Colors.blue,
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('go'));
    await tester.pump();

    expect(
      find.byIcon(Icons.timer_outlined, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.blur_on_rounded, skipOffstage: false),
      findsNothing,
    );
  });
}
