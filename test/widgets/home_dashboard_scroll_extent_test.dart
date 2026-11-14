import 'package:countdown_todo/screens/home_dashboard.dart';
import 'package:countdown_todo/widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone homepage tail reserves the pinned header and bottom inset', () {
    expect(
      homeDashboardPhoneScrollTailExtent(headerExtent: 112, bottomInset: 24),
      236,
    );
  });

  test('phone homepage tail remains usable without a pinned header', () {
    expect(
      homeDashboardPhoneScrollTailExtent(headerExtent: 0, bottomInset: 0),
      100,
    );
  });

  testWidgets(
    'pinned header layout updates headerExtent when an internal banner collapses',
    (tester) async {
      final showBanner = ValueNotifier<bool>(true);
      double? latestExtent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingGlassPinnedHeaderLayout(
              initialHeaderExtent: 78,
              fadeContent: false,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 78, width: double.infinity),
                  ValueListenableBuilder<bool>(
                    valueListenable: showBanner,
                    builder: (context, visible, _) => visible
                        ? const SizedBox(height: 40, width: double.infinity)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              bodyBuilder: (context, headerExtent) {
                latestExtent = headerExtent;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(latestExtent, 118);

      showBanner.value = false;
      await tester.pump();
      await tester.pump();
      expect(latestExtent, 78);

      showBanner.dispose();
    },
  );

  testWidgets('pinned header layout wraps body with top-bar fade by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassPinnedHeaderLayout(
            initialHeaderExtent: 78,
            header: const SizedBox(height: 78, width: double.infinity),
            bodyBuilder: (context, headerExtent) {
              return ListView(
                children: const [
                  SizedBox(height: 200, child: Text('Dashboard scroll body')),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FloatingGlassTopBarContentFade), findsOneWidget);
    expect(find.text('Dashboard scroll body'), findsOneWidget);
  });

  testWidgets(
    'dual-layer wallpaper architecture keeps top-bar fade and body backdrop',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: KeyedSubtree(
                    key: ValueKey<String>('outer-wallpaper'),
                    child: SizedBox.expand(),
                  ),
                ),
                FloatingGlassPinnedHeaderLayout(
                  initialHeaderExtent: 78,
                  fadeContent: true,
                  header: const SizedBox(height: 78, width: double.infinity),
                  bodyBuilder: (context, headerExtent) {
                    return Stack(
                      fit: StackFit.expand,
                      children: const [
                        Positioned.fill(
                          child: KeyedSubtree(
                            key: ValueKey<String>('inner-wallpaper'),
                            child: SizedBox.expand(),
                          ),
                        ),
                        SizedBox(height: 200, child: Text('Dashboard cards')),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FloatingGlassTopBarContentFade), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('outer-wallpaper')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('inner-wallpaper')),
        findsOneWidget,
      );
      expect(find.text('Dashboard cards'), findsOneWidget);

      // Verify that inner-wallpaper is an ancestor of the fade box, while outer-wallpaper is not
      final fadeFinder = find.byType(FloatingGlassTopBarContentFade);
      expect(
        find.descendant(
          of: fadeFinder,
          matching: find.byKey(const ValueKey<String>('inner-wallpaper')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: fadeFinder,
          matching: find.byKey(const ValueKey<String>('outer-wallpaper')),
        ),
        findsNothing,
      );
    },
  );
}
