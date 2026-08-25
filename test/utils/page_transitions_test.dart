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

Iterable<double> _clipRadii(WidgetTester tester) {
  return tester
      .widgetList<ClipRRect>(find.byType(ClipRRect))
      .map((ClipRRect clip) => clip.borderRadius.resolve(TextDirection.ltr).topLeft.x);
}

bool _hasRadius(WidgetTester tester, double value) {
  return _clipRadii(tester).any((r) => (r - value).abs() < 0.01);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GlobalKey<NavigatorState> navigatorKey;

  Future<void> pumpApp(WidgetTester tester) async {
    navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          pageTransitionsTheme: PageTransitions.theme,
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    navigatorKey.currentState!.push(
      PageTransitions.material(builder: (_) => const Scaffold(body: Text('page B'))),
    );
    await tester.pumpAndSettle();
  }

  group('predictive back gesture rounded corners', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await PageTransitions.init();
    });

    testWidgets('drag grows the foreground corner to the screen radius',
        (WidgetTester tester) async {
      await pumpApp(tester);

      // Raw gesture progress 0.3 -> corner factor 0.6 (12 * 0.6 = 7.2).
      await _sendBackGesture(tester, 'startBackGesture', progress: 0.3);
      await _sendBackGesture(tester, 'updateBackGestureProgress', progress: 0.3);
      await tester.pump();
      expect(_hasRadius(tester, 7.2), isTrue);

      // Half drag already reaches the full screen radius.
      await _sendBackGesture(tester, 'updateBackGestureProgress', progress: 0.5);
      await tester.pump();
      expect(_hasRadius(tester, 12.0), isTrue);
    });

    testWidgets('committed pop keeps corners through the exit animation',
        (WidgetTester tester) async {
      await pumpApp(tester);

      await _sendBackGesture(tester, 'startBackGesture', progress: 1.0);
      await _sendBackGesture(tester, 'updateBackGestureProgress', progress: 1.0);
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
      await _sendBackGesture(tester, 'updateBackGestureProgress', progress: 0.8);
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
      await _sendBackGesture(tester, 'updateBackGestureProgress', progress: 1.0);
      await tester.pump();
      expect(_clipRadii(tester), isEmpty);

      await _sendBackGesture(tester, 'commitBackGesture');
      await tester.pump(const Duration(milliseconds: 40));
      expect(_clipRadii(tester), isEmpty);

      await tester.pumpAndSettle();
      expect(find.text('page B'), findsNothing);
    });
  });
}
