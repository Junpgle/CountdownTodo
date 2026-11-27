import 'dart:ui' as ui;

import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_surface.dart';
import 'package:countdown_todo/widgets/platform_backdrop_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets(
    'PreblurredWallpaperFill samples exact viewport region on scroll at 2x DPR without repainting card content',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final image = await tester.runAsync(_createSplitWallpaperImage);
      addTearDown(image!.dispose);
      final notifier = ValueNotifier<PreblurredWallpaperSnapshot?>(
        PreblurredWallpaperSnapshot(
          image: image,
          viewportSize: const Size(400, 300),
          blurSigma: 3.0,
        ),
      );
      addTearDown(notifier.dispose);
      final viewportKey = GlobalKey();
      final captureKey = GlobalKey();
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const cardKey = ValueKey<String>('aligned-scroll-card');
      var contentPaintCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: captureKey,
              child: Stack(
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
                        // Starts in bottom orange half (y = 180..260 logical).
                        const SizedBox(height: 180),
                        RepaintBoundary(
                          child: OptionalLiquidGlassPanel(
                            key: cardKey,
                            mode: OptionalLiquidGlassPanelMode.adaptiveRepeated,
                            staticMaterialOpacity: 0.0,
                            fallback: const SizedBox.shrink(),
                            child: _CountingPaintBox(
                              onPaint: () => contentPaintCount++,
                              child: const SizedBox(height: 80),
                            ),
                          ),
                        ),
                        const SizedBox(height: 600),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final fillRenderObject = tester.renderObject(
        find.descendant(
          of: find.byKey(cardKey),
          matching: find.byType(PreblurredWallpaperFill),
        ),
      );
      final initialContentPaints = contentPaintCount;
      final initialFillPaints = debugPreblurredWallpaperPaintCount(
        fillRenderObject,
      );

      Future<({int r, int g, int b})> sampleCardCenter(int physicalY) async {
        final rendered = await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final captured = await boundary.toImage(pixelRatio: 2.0);
          try {
            return await captured.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
          } finally {
            captured.dispose();
          }
        });
        final bytes = rendered!.buffer.asUint8List();
        final pixelOffset = (physicalY * 800 + 400) * 4;
        return (
          r: bytes[pixelOffset],
          g: bytes[pixelOffset + 1],
          b: bytes[pixelOffset + 2],
        );
      }

      // Before scroll: card sits at logical y=180..260 (physical y=440 center) -> orange half.
      final beforeScroll = await sampleCardCenter(440);
      expect(beforeScroll.r, greaterThan(220));
      expect(beforeScroll.r - beforeScroll.b, greaterThan(80));

      // Scrolling down 120 logical px moves card into logical y=60..140 (physical y=200 center)
      // in the top blue half and repaints ONLY the PreblurredWallpaperFill layer.
      controller.jumpTo(120);
      await tester.pump();
      expect(
        debugPreblurredWallpaperPaintCount(fillRenderObject),
        greaterThan(initialFillPaints),
      );
      expect(contentPaintCount, initialContentPaints);

      final afterScroll = await sampleCardCenter(200);
      expect(afterScroll.b, greaterThan(200));
      expect(afterScroll.b - afterScroll.r, greaterThan(80));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WallpaperTopFadeCap renders baked dimmed strip fading cleanly to zero across DPR boundaries',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final image = await tester.runAsync(_createTestWallpaperImage);
      addTearDown(image!.dispose);
      final rawBytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      );
      final provider = MemoryImage(rawBytes!.buffer.asUint8List());
      final captureKey = GlobalKey();
      const dimFactor = 1.0 - (0x66 / 255.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: captureKey,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(color: const Color(0xFFE53935)),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 120,
                    child: WallpaperTopFadeCap(
                      imageProvider: provider,
                      height: 120,
                      dimFactor: dimFactor,
                      fallbackBuilder: (_) => const ShaderMask(
                        shaderCallback: _dummyShader,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(WallpaperTopFadeCap), findsOneWidget);
      final leaf = find.descendant(
        of: find.byType(WallpaperTopFadeCap),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_WallpaperTopFadeRenderWidget',
        ),
      );
      expect(
        debugWallpaperTopFadeCapDidPaintBakedImage(tester.renderObject(leaf)),
        isTrue,
      );

      final rendered = await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final captured = await boundary.toImage(pixelRatio: 2.0);
        try {
          return await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          captured.dispose();
        }
      });
      final bytes = rendered!.buffer.asUint8List();

      int idx(int x, int y) => (y * 800 + x) * 4;
      // Top band (y = 8px): solid dimmed wallpaper (0x336699 * 0.6 -> ~31, 61, 92).
      final topOffset = idx(400, 8);
      expect(bytes[topOffset], inInclusiveRange(25, 40));
      expect(bytes[topOffset + 1], inInclusiveRange(55, 70));
      expect(bytes[topOffset + 2], inInclusiveRange(85, 102));

      // Bottom edge of the 120dp (=240px) cap (y = 238px) must seamlessly match
      // the red card immediately below the cap (y = 244px), with zero hard step.
      final justAboveBottom = idx(400, 238);
      final justBelowBottom = idx(400, 244);
      expect(
        (bytes[justAboveBottom] - bytes[justBelowBottom]).abs(),
        lessThanOrEqualTo(4),
      );
      expect(
        (bytes[justAboveBottom + 1] - bytes[justBelowBottom + 1]).abs(),
        lessThanOrEqualTo(4),
      );
      expect(
        (bytes[justAboveBottom + 2] - bytes[justBelowBottom + 2]).abs(),
        lessThanOrEqualTo(4),
      );
      expect(bytes[justAboveBottom], greaterThan(215));
      expect(tester.takeException(), isNull);
    },
  );
}

Shader _dummyShader(Rect bounds) =>
    const LinearGradient(colors: [Colors.white, Colors.transparent])
        .createShader(bounds);

Future<ui.Image> _createSplitWallpaperImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 100),
    Paint()..color = const Color(0xFF1E88E5),
  );
  canvas.drawRect(
    const Rect.fromLTWH(0, 100, 200, 100),
    Paint()..color = const Color(0xFFFF7043),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  picture.dispose();
  return image;
}

class _CountingPaintBox extends SingleChildRenderObjectWidget {
  const _CountingPaintBox({required this.onPaint, super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountingPaintBox(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCountingPaintBox renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderCountingPaintBox extends RenderProxyBox {
  _RenderCountingPaintBox(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
