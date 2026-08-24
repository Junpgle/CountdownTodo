import 'package:countdown_todo/utils/app_dialogs.dart';
import 'package:countdown_todo/utils/system_ui_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSystemUiStyle', () {
    test('uses dark system icons over a light background', () {
      final style = AppSystemUiStyle.forBrightness(Brightness.light);

      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isTrue);
    });

    test('uses light system icons over a dark background', () {
      final style = AppSystemUiStyle.forBrightness(Brightness.dark);

      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
    });
  });

  testWidgets('app bottom sheets protect content from the bottom system bar',
      (tester) async {
    const devicePixelRatio = 2.0;
    const navigationBarHeight = 54.0;
    const padding = FakeViewPadding(
      bottom: navigationBarHeight * devicePixelRatio,
    );
    addTearDown(tester.view.reset);
    tester.view
      ..viewPadding = padding
      ..padding = padding
      ..devicePixelRatio = devicePixelRatio
      ..physicalSize = const Size(960, 1920);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  showAppModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SizedBox(
                      key: Key('sheet-content'),
                      height: 80,
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final safeArea = tester.widget<SafeArea>(
      find.ancestor(
        of: find.byKey(const Key('sheet-content')),
        matching: find.byType(SafeArea),
      ),
    );
    expect(safeArea.top, isFalse);
    expect(safeArea.left, isFalse);
    expect(safeArea.right, isFalse);
    expect(safeArea.bottom, isTrue);
    expect(
      tester.getBottomRight(find.byKey(const Key('sheet-content'))).dy,
      960 - navigationBarHeight,
    );
  });

  testWidgets(
    'bottom sheet overrides an underlying wallpaper navigation style',
    (tester) async {
      const devicePixelRatio = 2.0;
      const navigationBarHeight = 54.0;
      const padding = FakeViewPadding(
        bottom: navigationBarHeight * devicePixelRatio,
      );
      addTearDown(tester.view.reset);
      tester.view
        ..viewPadding = padding
        ..padding = padding
        ..devicePixelRatio = devicePixelRatio
        ..physicalSize = const Size(960, 1920);

      await tester.pumpWidget(
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showAppModalBottomSheet<void>(
                      context: context,
                      builder: (_) => const SizedBox(height: 120),
                    ),
                    child: const Text('打开弹层'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开弹层'));
      await tester.pumpAndSettle();

      expect(
        SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.light,
      );

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(
        SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
        Brightness.light,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
