import 'dart:ui' as ui;

import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_surface.dart';
import 'package:countdown_todo/widgets/platform_backdrop_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ui.Image> _createTestWallpaperImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 120, 180),
    Paint()..color = const Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 180);
  picture.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setPowerSaveMode(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
  });

  tearDown(GlassPerformanceMonitor.stop);

  testWidgets(
    'OptionalLiquidGlassBackdropScope bypasses BackdropFilter on solid backgrounds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionalLiquidGlassBackdropScope(
              isSolidBackground: true,
              child: Column(
                children: [
                  const OptionalLiquidGlassCard(
                    fallbackDecoration: BoxDecoration(),
                    child: Text('Solid standard card'),
                  ),
                  PlatformBackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    clipBorderRadius: BorderRadius.circular(16),
                    child: const Text('Solid platform filter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(PreblurredWallpaperFill), findsNothing);
      expect(find.text('Solid standard card'), findsOneWidget);
      expect(find.text('Solid platform filter'), findsOneWidget);

      // Premium warm-up loads real shader assets that the test asset bundle
      // does not ship; silence those environment-only reports.
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {};
      try {
        await LiquidGlassEffectService.setEnabled(true);
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);
      } finally {
        FlutterError.onError = previousErrorHandler;
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionalLiquidGlassBackdropScope(
              isSolidBackground: true,
              child: const OptionalLiquidGlassCard(
                fallbackDecoration: BoxDecoration(),
                child: Text('Solid enhanced card'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Solid enhanced card'), findsOneWidget);
    },
  );

  testWidgets(
    'OptionalLiquidGlassBackdropScope paints PreblurredWallpaperFill instead of BackdropFilter when snapshot is ready',
    (tester) async {
      final notifier = ValueNotifier<PreblurredWallpaperSnapshot?>(null);
      addTearDown(notifier.dispose);
      final viewportKey = GlobalKey();
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              key: viewportKey,
              fit: StackFit.expand,
              children: [
                OptionalLiquidGlassBackdropScope(
                  isSolidBackground: false,
                  blurredWallpaperListenable: notifier,
                  viewportKey: viewportKey,
                  child: ListView(
                    controller: controller,
                    children: [
                      const OptionalLiquidGlassCard(
                        fallbackDecoration: BoxDecoration(),
                        child: SizedBox(height: 120, child: Text('Glass card')),
                      ),
                      PlatformBackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        clipBorderRadius: BorderRadius.circular(16),
                        child: const SizedBox(
                          height: 80,
                          child: Text('Platform card'),
                        ),
                      ),
                      const SizedBox(height: 1000),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Before the snapshot is ready, cards fall back cleanly to BackdropFilter.
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      expect(find.byType(PreblurredWallpaperFill), findsNothing);

      final image = await tester.runAsync(_createTestWallpaperImage);
      addTearDown(image!.dispose);
      notifier.value = PreblurredWallpaperSnapshot(
        image: image,
        viewportSize: const Size(800, 600),
        blurSigma: 3.0,
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(PreblurredWallpaperFill), findsNWidgets(2));
      expect(find.text('Glass card'), findsOneWidget);
      expect(find.text('Platform card'), findsOneWidget);

      controller.jumpTo(120);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PreblurredWallpaperFill repaints on outer vertical scroll even inside nested Scrollables',
    (tester) async {
      final image = await tester.runAsync(_createTestWallpaperImage);
      addTearDown(image!.dispose);
      final notifier = ValueNotifier<PreblurredWallpaperSnapshot?>(
        PreblurredWallpaperSnapshot(
          image: image,
          viewportSize: const Size(800, 600),
          blurSigma: 3.0,
        ),
      );
      addTearDown(notifier.dispose);
      final viewportKey = GlobalKey();
      final outerController = ScrollController();
      final horizontalController = ScrollController();
      addTearDown(outerController.dispose);
      addTearDown(horizontalController.dispose);

      const countdownCardKey = ValueKey<String>('nested-countdown-card');
      const todoCardKey = ValueKey<String>('nested-todo-card');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              key: viewportKey,
              fit: StackFit.expand,
              children: [
                OptionalLiquidGlassBackdropScope(
                  isSolidBackground: false,
                  blurredWallpaperListenable: notifier,
                  viewportKey: viewportKey,
                  child: ListView(
                    controller: outerController,
                    children: [
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          controller: horizontalController,
                          scrollDirection: Axis.horizontal,
                          itemCount: 4,
                          itemBuilder: (context, index) => SizedBox(
                            width: 240,
                            child: OptionalLiquidGlassCard(
                              key: index == 0 ? countdownCardKey : null,
                              fallbackDecoration: const BoxDecoration(),
                              child: Text('Countdown $index'),
                            ),
                          ),
                        ),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 2,
                        itemBuilder: (context, index) =>
                            OptionalLiquidGlassCard(
                              key: index == 0 ? todoCardKey : null,
                              fallbackDecoration: const BoxDecoration(),
                              child: SizedBox(
                                height: 80,
                                child: Text('Todo $index'),
                              ),
                            ),
                      ),
                      const SizedBox(height: 1200),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final countdownFillFinder = find.descendant(
        of: find.byKey(countdownCardKey),
        matching: find.byType(PreblurredWallpaperFill),
      );
      final todoFillFinder = find.descendant(
        of: find.byKey(todoCardKey),
        matching: find.byType(PreblurredWallpaperFill),
      );

      final initialCountdownRect = debugPreblurredWallpaperLastDstRect(
        tester.renderObject(countdownFillFinder),
      )!;
      final initialTodoRect = debugPreblurredWallpaperLastDstRect(
        tester.renderObject(todoFillFinder),
      )!;

      // Scroll outer vertical list: BOTH nested cards must shift vertically.
      outerController.jumpTo(50);
      await tester.pump();

      final scrolledCountdownRect = debugPreblurredWallpaperLastDstRect(
        tester.renderObject(countdownFillFinder),
      )!;
      final scrolledTodoRect = debugPreblurredWallpaperLastDstRect(
        tester.renderObject(todoFillFinder),
      )!;
      expect(
        scrolledCountdownRect.top - initialCountdownRect.top,
        moreOrLessEquals(50, epsilon: 0.1),
      );
      expect(
        scrolledTodoRect.top - initialTodoRect.top,
        moreOrLessEquals(50, epsilon: 0.1),
      );

      // Scroll inner horizontal countdown list: horizontal offset must shift too.
      horizontalController.jumpTo(80);
      await tester.pump();

      final horizontallyScrolledRect = debugPreblurredWallpaperLastDstRect(
        tester.renderObject(countdownFillFinder),
      )!;
      expect(
        horizontallyScrolledRect.left - scrolledCountdownRect.left,
        moreOrLessEquals(80, epsilon: 0.1),
      );
    },
  );
}
