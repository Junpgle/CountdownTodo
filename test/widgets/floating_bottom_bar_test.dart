import 'package:countdown_todo/widgets/floating_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/services/liquid_glass_effect_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(GlassPerformanceMonitor.stop);

  test('limits the floating treatment to mobile portrait phone layouts', () {
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: true,
        width: 390,
        height: 844,
      ),
      isTrue,
    );
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: true,
        width: 844,
        height: 390,
      ),
      isFalse,
    );
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: true,
        width: 800,
        height: 1280,
      ),
      isFalse,
    );
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: false,
        width: 390,
        height: 844,
      ),
      isFalse,
    );
  });

  test('scales the capsule width with the number of destinations', () {
    final threeItemWidth = floatingBottomNavigationWidthFor(
      390,
      itemCount: 3,
    );

    expect(threeItemWidth, closeTo(262, 0.001));
    expect(
      floatingBottomNavigationWidthFor(390, itemCount: 2),
      closeTo(threeItemWidth * 2 / 3, 0.001),
    );
    expect(
      floatingBottomNavigationWidthFor(390, itemCount: 4),
      closeTo(threeItemWidth * 4 / 3, 0.001),
    );
    expect(
      floatingBottomNavigationWidthFor(390, itemCount: 5),
      closeTo(358, 0.001),
    );
  });

  testWidgets('keeps the bar child when the effect is disabled',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    const childKey = Key('floating-bottom-bar-child');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingBottomBar(
            mobilePortraitOnly: false,
            height: 72,
            margin: EdgeInsets.zero,
            child: SizedBox(key: childKey),
          ),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    final childSize = tester.getSize(find.byKey(childKey));
    expect(childSize.width, lessThanOrEqualTo(800));
    expect(childSize.height, lessThanOrEqualTo(72));
    expect(childSize.height, greaterThan(68));
  });

  testWidgets('supports content-sized floating controls', (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassControl(
            height: null,
            margin: EdgeInsets.zero,
            mobilePortraitOnly: false,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Content-sized control'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.text('Content-sized control'), findsOneWidget);
  });

  testWidgets('uses the shared top fade on AppBars', (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            flexibleSpace: const FloatingGlassTopBarBackground(),
            title: const Text('Top fade'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Top fade'), findsOneWidget);
  });

  testWidgets('keeps an embedded AppBar finite with the shared top fade',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppBar(
                toolbarHeight: 86,
                flexibleSpace: const FloatingGlassTopBarBackground(
                  unboundedHeight: 86,
                ),
                title: const Text('Embedded top fade'),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final appBarSize = tester.getSize(find.byType(AppBar));
    expect(appBarSize.height.isFinite, isTrue);
    expect(appBarSize.height, greaterThan(0));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Embedded top fade'), findsOneWidget);
  });

  testWidgets('wraps AppBar controls with the shared floating shell',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    final actionKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: FloatingGlassAppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {},
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('Floating controls'),
            actions: [
              IconButton(
                key: actionKey,
                tooltip: 'Action',
                onPressed: () {},
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(FloatingGlassAppBarAction), findsNWidgets(2));
    expect(find.byKey(actionKey), findsOneWidget);
    expect(find.text('Floating controls'), findsOneWidget);
  });

  testWidgets('animates an AppBar control into its glass shell',
      (tester) async {
    final collapseProgress = ValueNotifier<double>(0);

    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassAppBarAction(
            collapseProgress: collapseProgress,
            child: IconButton(
              tooltip: 'Animated action',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FloatingGlassControl), findsNothing);

    collapseProgress.value = 1;
    await tester.pump();
    expect(find.byType(FloatingGlassControl), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FloatingGlassControl), findsOneWidget);
    collapseProgress.dispose();
  });

  testWidgets('starts the top blur when content overlaps the toolbar',
      (tester) async {
    final controller = ScrollController();

    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView.builder(
                controller: controller,
                itemCount: 20,
                itemBuilder: (context, index) => SizedBox(
                  height: 80,
                  child: Text('Content $index'),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FloatingGlassTopBarOverlay(
                  height: 80,
                  overlapStart: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);

    controller.jumpTo(40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(BackdropFilter), findsOneWidget);
    controller.dispose();
  });
}
