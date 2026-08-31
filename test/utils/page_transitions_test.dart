import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _sendBackGesture(
  WidgetTester tester,
  String method, {
  double progress = 0.0,
}) async {
  final ByteData message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, <String, Object?>{
      'touchOffset': <double>[10.0, 50.0],
      'progress': progress,
      'swipeEdge': 0,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    message,
    (ByteData? _) {},
  );
}

Iterable<double> _clipRadii(
  WidgetTester tester, {
  bool skipOffstage = true,
}) {
  return tester
      .widgetList<ClipRRect>(
        find.byType(ClipRRect, skipOffstage: skipOffstage),
      )
      .map((ClipRRect clip) =>
          clip.borderRadius.resolve(TextDirection.ltr).topLeft.x);
}

bool _hasRadius(WidgetTester tester, double value) {
  return _clipRadii(tester).any((r) => (r - value).abs() < 0.01);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GlobalKey<NavigatorState> navigatorKey;

  Future<void> pumpApp(
    WidgetTester tester, {
    BorderRadius? displayCornerRadii,
  }) async {
    navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).applyDisplayCornerRadii(
            displayCornerRadii,
          ),
          child: child!,
        ),
        theme: ThemeData(
          pageTransitionsTheme: PageTransitions.theme,
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    navigatorKey.currentState!.push(
      PageTransitions.material(
          builder: (_) => const Scaffold(body: Text('page B'))),
    );
    await tester.pumpAndSettle();
  }

  group('system power saver override', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'enable_animations': true,
      });
      PageTransitions.setPowerSaveMode(false);
      await PageTransitions.init();
    });

    tearDown(() {
      PageTransitions.setPowerSaveMode(false);
    });

    test('temporarily removes route animation without changing preferences',
        () {
      PageTransitions.setPowerSaveMode(true);

      final route = PageTransitions.material<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(PageTransitions.isPowerSaveMode, isTrue);

      PageTransitions.setPowerSaveMode(false);
      final restoredRoute = PageTransitions.material<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      expect(restoredRoute.transitionDuration, isNot(Duration.zero));
    });
  });

  group('predictive back gesture rounded corners', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      PageTransitions.setPowerSaveMode(false);
      await PageTransitions.init();
    });

    testWidgets('drag grows the foreground corner to the screen radius',
        (WidgetTester tester) async {
      await pumpApp(tester);

      // Raw gesture progress 0.3 -> corner factor 0.6 (12 * 0.6 = 7.2).
      await _sendBackGesture(tester, 'startBackGesture', progress: 0.3);
      await _sendBackGesture(tester, 'updateBackGestureProgress',
          progress: 0.3);
      await tester.pump();
      expect(_hasRadius(tester, 7.2), isTrue);

      // Half drag already reaches the full screen radius.
      await _sendBackGesture(tester, 'updateBackGestureProgress',
          progress: 0.5);
      await tester.pump();
      expect(_hasRadius(tester, 12.0), isTrue);
    });

    testWidgets('committed pop keeps corners through the exit animation',
        (WidgetTester tester) async {
      await pumpApp(tester);

      await _sendBackGesture(tester, 'startBackGesture', progress: 1.0);
      await _sendBackGesture(tester, 'updateBackGestureProgress',
          progress: 1.0);
      await tester.pump();
      expect(_clipRadii(tester), isNotEmpty);

      // Commit: the route pops and the status flips to reverse, but the
      // gesture flag keeps the clip alive until the route is disposed.
      await _sendBackGesture(tester, 'commitBackGesture');
      await tester.pump(const Duration(milliseconds: 40));
      expect(_hasRadius(tester, 12.0), isTrue);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_hasRadius(tester, 12.0), isTrue);

      await tester.pumpAndSettle();
      expect(find.text('page B'), findsNothing);
      expect(_clipRadii(tester), isEmpty);
    });

    testWidgets('cancel restores the page without clipping',
        (WidgetTester tester) async {
      await pumpApp(tester);

      await _sendBackGesture(tester, 'startBackGesture', progress: 0.8);
      await _sendBackGesture(tester, 'updateBackGestureProgress',
          progress: 0.8);
      await tester.pump();
      expect(_clipRadii(tester), isNotEmpty);

      await _sendBackGesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('page B'), findsOneWidget);
      expect(_clipRadii(tester), isEmpty);
    });

    testWidgets('no corners when the screen radius setting is disabled',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'enable_screen_radius': false,
      });
      await PageTransitions.init();

      await pumpApp(tester);

      await _sendBackGesture(tester, 'startBackGesture', progress: 1.0);
      await _sendBackGesture(tester, 'updateBackGestureProgress',
          progress: 1.0);
      await tester.pump();
      expect(_clipRadii(tester), isEmpty);

      await _sendBackGesture(tester, 'commitBackGesture');
      await tester.pump(const Duration(milliseconds: 40));
      expect(_clipRadii(tester), isEmpty);

      await tester.pumpAndSettle();
      expect(find.text('page B'), findsNothing);
    });

    testWidgets('uses the reported display corner radii',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await PageTransitions.init();

      await pumpApp(
        tester,
        displayCornerRadii: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(22),
          bottomLeft: Radius.circular(20),
        ),
      );

      await _sendBackGesture(tester, 'startBackGesture', progress: 0.5);
      await _sendBackGesture(tester, 'updateBackGestureProgress',
          progress: 0.5);
      await tester.pump();

      expect(_hasRadius(tester, 28.0), isTrue);
    });

    testWidgets('container transform adopts the display corner radii',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'enable_lazy_load': false,
      });
      await PageTransitions.init();
      const displayCornerRadii = BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(24),
        bottomRight: Radius.circular(22),
        bottomLeft: Radius.circular(20),
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).applyDisplayCornerRadii(
              displayCornerRadii,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  ContainerTransformRoute<void>(
                    page: const SizedBox.expand(),
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
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        _clipRadii(tester, skipOffstage: false),
        contains(28.0),
      );
    });

    testWidgets('container transform renders a source-specific placeholder',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'enable_lazy_load': true,
      });
      await PageTransitions.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(pageTransitionsTheme: PageTransitions.theme),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  ContainerTransformRoute<void>(
                    page: const SizedBox.expand(),
                    sourceRect: const Rect.fromLTWH(40, 40, 120, 80),
                    sourceColor: Colors.blue,
                    placeholderBuilder: (_) => const Text('📖'),
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

      expect(find.text('📖', skipOffstage: false), findsOneWidget);
    });
  });
}
