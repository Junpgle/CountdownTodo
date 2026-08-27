import 'package:countdown_todo/widgets/home_bottom_navigation_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  test('bottom bar uses compact responsive margins', () {
    expect(homeBottomBarHorizontalMarginFor(320), 40);
    expect(homeBottomBarHorizontalMarginFor(390), 64);
    expect(homeBottomBarHorizontalMarginFor(512), 78);
    expect(homeBottomBarHorizontalMarginFor(700), 160);
  });

  test('dark mode ignores a stale wallpaper color', () {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );

    expect(
      homeBottomBarPrimaryColor(
        colorScheme: colorScheme,
        hasWallpaper: false,
        wallpaperDominantColor: const Color(0xFF102000),
      ),
      colorScheme.primary,
    );
  });

  test('selected capsule stays neutral over a wallpaper color', () {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
    const wallpaperColor = Color(0xFF796322);

    final selected = homeBottomBarSelectedBackgroundColor(
      colorScheme: colorScheme,
      primaryColor: wallpaperColor,
      isDark: false,
    );

    expect(selected.a, closeTo(0.72, 0.001));
    expect(
      (selected.r - colorScheme.surface.r).abs(),
      lessThan((wallpaperColor.r - colorScheme.surface.r).abs()),
    );
  });

  testWidgets('keeps the home, calendar, and focus layout', (tester) async {
    final semantics = tester.ensureSemantics();
    final calendarKey = GlobalKey();
    var selectedIndex = 0;
    var calendarPressed = false;
    const primary = Colors.green;
    const inactive = Colors.black87;
    const selectedBackground = Color(0x339E9E9E);

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  height: 60,
                  child: HomeBottomNavigationContent(
                    selectedIndex: selectedIndex,
                    primaryColor: primary,
                    inactiveColor: inactive,
                    selectedBackgroundColor: selectedBackground,
                    calendarButtonKey: calendarKey,
                    onTabSelected: (index) {
                      setState(() => selectedIndex = index);
                    },
                    onCalendarPressed: () => calendarPressed = true,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    // The icon row is rendered twice so the jelly clip can reveal the active
    // colors only inside the moving lens. The selected copy is excluded from
    // semantics and pointer handling.
    expect(find.text('首页'), findsNWidgets(2));
    expect(find.byIcon(Icons.calendar_today_rounded), findsNWidgets(2));
    expect(find.text('专注'), findsNWidgets(2));
    expect(find.bySemanticsLabel('首页'), findsOneWidget);
    expect(find.bySemanticsLabel('专注'), findsOneWidget);

    final indicatorFinder = find.byKey(
      const ValueKey<String>('home-bottom-selection-indicator'),
    );
    final indicatorFillFinder = find.byKey(
      const ValueKey<String>('home-bottom-selection-indicator-fill'),
    );
    final indicator = tester.widget<AnimatedGlassIndicator>(indicatorFinder);
    final indicatorFill =
        tester.widget<AnimatedGlassIndicator>(indicatorFillFinder);
    expect(indicator.alignment, const Alignment(-1, 0));
    expect(indicator.thickness, 0);
    expect(indicatorFill.indicatorColor, selectedBackground);
    expect(indicatorFill.paintBackground, isTrue);
    expect(indicatorFill.paintGlass, isFalse);
    expect(
      indicator.expansion,
      const EdgeInsets.symmetric(horizontal: 30, vertical: 11),
    );
    expect(indicator.pinchStrength, 0.85);

    final overflowLayer = tester.widget<Transform>(
      find.byKey(
        const ValueKey<String>('home-bottom-selection-overflow-layer'),
      ),
    );
    expect(overflowLayer.transform.getTranslation().y, 0);
    expect(overflowLayer.transform.storage[0], closeTo(1.1, 0.001));
    expect(overflowLayer.transform.storage[5], closeTo(1.02, 0.001));

    final gestureFinder = find.byKey(
      const ValueKey<String>('home-bottom-navigation-gesture-layer'),
    );
    final selectedClipFinder = find
        .descendant(of: gestureFinder, matching: find.byType(ClipPath))
        .last;
    final selectedClip = tester.widget<ClipPath>(selectedClipFinder);
    final selectedClipBounds = selectedClip.clipper!
        .getClip(tester.getSize(selectedClipFinder))
        .getBounds();
    expect(selectedClipBounds.top, greaterThan(0));
    expect(selectedClipBounds.bottom,
        lessThan(tester.getSize(selectedClipFinder).height));
    expect(
      selectedClipBounds.width / selectedClipBounds.height,
      greaterThan(1.35),
    );

    final calendarButton = tester.widget<Container>(find.byKey(calendarKey));
    final calendarDecoration = calendarButton.decoration! as BoxDecoration;
    expect(tester.getSize(find.byKey(calendarKey)), const Size(56, 44));
    expect(calendarDecoration.borderRadius, BorderRadius.circular(22));

    final gestureRect = tester.getRect(gestureFinder);
    await tester.tapAt(
      Offset(gestureRect.right - gestureRect.width / 6, gestureRect.center.dy),
    );
    // Page selection is committed only after the liquid lens reaches its tab.
    expect(selectedIndex, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final movingIndicator =
        tester.widget<AnimatedGlassIndicator>(indicatorFinder);
    final movingAlignment =
        movingIndicator.alignment.resolve(TextDirection.ltr).x;
    expect(movingAlignment, greaterThan(-1));
    expect(movingAlignment, lessThan(1));
    expect(movingIndicator.thickness, greaterThan(0));
    final movingSelectedClip = tester.widget<ClipPath>(selectedClipFinder);
    final movingClipSize = tester.getSize(selectedClipFinder);
    final movingClipBounds = movingSelectedClip.clipper!
        .getClip(movingClipSize)
        .getBounds();
    expect(movingClipBounds.top, lessThan(0));
    expect(movingClipBounds.bottom, greaterThan(movingClipSize.height));
    await tester.pump(const Duration(milliseconds: 100));
    // The selection commits within the short snap, without waiting for the
    // spring's barely visible settling tail.
    expect(selectedIndex, 2);
    await tester.pumpAndSettle();
    expect(selectedIndex, 2);
    expect(
      tester.widget<AnimatedGlassIndicator>(indicatorFinder).alignment,
      const Alignment(1, 0),
    );
    await tester.tap(find.byKey(calendarKey));
    expect(calendarPressed, isTrue);

    await tester.drag(
      gestureFinder,
      const Offset(-180, 0),
    );
    expect(selectedIndex, 2);
    await tester.pumpAndSettle();
    expect(selectedIndex, 0);
    expect(
      tester.widget<AnimatedGlassIndicator>(indicatorFinder).alignment,
      const Alignment(-1, 0),
    );
    semantics.dispose();
  });
}
