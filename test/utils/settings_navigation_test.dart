import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/utils/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': false,
    });
    PageTransitions.setPowerSaveMode(false);
    await PageTransitions.init();
  });

  for (final scenario in [
    'portrait',
    'landscape',
    'embedded',
    'root navigator',
    'animations disabled',
    'missing source',
  ]) {
    testWidgets('$scenario preserves settings routes and return values', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario == 'landscape'
          ? const Size(640, 360)
          : const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (scenario == 'animations disabled') {
        SharedPreferences.setMockInitialValues({'enable_animations': false});
        await PageTransitions.init();
      }

      final rootNavigator = GlobalKey<NavigatorState>();
      final innerNavigator = GlobalKey<NavigatorState>();
      final sourceKey = GlobalKey();
      final rootObserver = _RouteObserver();
      final innerObserver = _RouteObserver();
      final nested = scenario == 'embedded' || scenario == 'root navigator';
      bool? result;
      Widget sourceBuilder(BuildContext context) => Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 64,
            child: TextButton(
              key: sourceKey,
              onPressed: () async {
                result = await SettingsNavigation.push<bool>(
                  context: context,
                  page: const Scaffold(body: Text('settings detail')),
                  sourceKey: scenario == 'missing source'
                      ? GlobalKey()
                      : sourceKey,
                  isEmbedded: scenario == 'embedded',
                  rootNavigator: scenario == 'root navigator',
                  settings: const RouteSettings(name: '设置详情'),
                );
              },
              child: const Text('open settings'),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigator,
          navigatorObservers: [rootObserver],
          home: nested
              ? Navigator(
                  key: innerNavigator,
                  observers: [innerObserver],
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: sourceBuilder),
                )
              : Builder(builder: sourceBuilder),
        ),
      );
      await tester.pumpAndSettle();
      final sourceRect = tester.getRect(find.byKey(sourceKey));
      final rootCount = rootObserver.routes.length;
      final innerCount = innerObserver.routes.length;
      await tester.tap(find.text('open settings'));
      if (scenario == 'portrait') {
        await tester.tap(find.text('open settings'));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      final onInner = scenario == 'embedded';
      final observer = onInner ? innerObserver : rootObserver;
      final route = observer.routes.last;
      expect(rootObserver.routes, hasLength(rootCount + (onInner ? 0 : 1)));
      expect(innerObserver.routes, hasLength(innerCount + (onInner ? 1 : 0)));
      expect(route.settings.name, '设置详情');
      final useContainer =
          scenario == 'portrait' || scenario == 'root navigator';
      expect(route is ContainerTransformRoute<bool>, useContainer);
      if (useContainer) {
        expect((route as ContainerTransformRoute<bool>).sourceRect, sourceRect);
      }
      await tester.pumpAndSettle();
      expect(find.text('settings detail'), findsOneWidget);
      (onInner ? innerNavigator : rootNavigator).currentState!.pop(true);
      await tester.pump();
      if (useContainer) {
        expect(
          (route as ContainerTransformRoute<bool>).animation!.status,
          AnimationStatus.reverse,
        );
        await tester.pump(
          route.reverseTransitionDuration - const Duration(milliseconds: 1),
        );
        final container = tester.widget<Positioned>(
          find
              .byWidgetPredicate(
                (widget) => widget is Positioned && widget.child is ClipRRect,
              )
              .last,
        );
        expect(container.left, closeTo(sourceRect.left, 1));
        expect(container.top, closeTo(sourceRect.top, 1));
        expect(container.width, closeTo(sourceRect.width, 1));
        expect(container.height, closeTo(sourceRect.height, 1));
      }
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('open settings'), findsOneWidget);
    });
  }
}
