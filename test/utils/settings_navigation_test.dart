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

class _MixinNavigationHost extends StatefulWidget {
  const _MixinNavigationHost({
    this.customStore,
    this.keyPrefix = 'settings-custom',
  });

  final Map<String, GlobalKey>? customStore;
  final String keyPrefix;

  @override
  State<_MixinNavigationHost> createState() => _MixinNavigationHostState();
}

class _MixinNavigationHostState extends State<_MixinNavigationHost>
    with SettingsNavigationMixin<_MixinNavigationHost> {
  @override
  Map<String, GlobalKey> get settingsNavigationKeyStore =>
      widget.customStore ?? super.settingsNavigationKeyStore;

  @override
  String get settingsNavigationKeyPrefix => widget.keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: settingsNavigationKey('item'),
          onPressed: () {
            openSettingsPage<void>(
              'item',
              const Scaffold(body: Text('mixin detail')),
              settings: const RouteSettings(name: '混入详情'),
            );
          },
          child: const Text('open mixin'),
        ),
      ),
    );
  }
}

class _MixinHighlightHost extends StatefulWidget {
  const _MixinHighlightHost({
    this.initialTarget,
    this.highlight = true,
    this.highlightDuration = const Duration(milliseconds: 200),
  });

  final String? initialTarget;
  final bool highlight;
  final Duration highlightDuration;

  @override
  State<_MixinHighlightHost> createState() => _MixinHighlightHostState();
}

class _MixinHighlightHostState extends State<_MixinHighlightHost>
    with SettingsTargetHighlightMixin<_MixinHighlightHost> {
  final Map<String, GlobalKey> _keys = {
    'first': GlobalKey(),
    'second': GlobalKey(),
  };

  @override
  GlobalKey? resolveSettingsTargetKey(String target) => _keys[target];

  @override
  void initState() {
    super.initState();
    scheduleInitialSettingsTarget(
      widget.initialTarget,
      highlight: widget.highlight,
      highlightDuration: widget.highlightDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              key: _keys['first'],
              height: 900,
              color: highlightTarget == 'first'
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              child: const Text('first target'),
            ),
            Container(
              key: _keys['second'],
              height: 200,
              color: highlightTarget == 'second'
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              child: Text(
                highlightTarget == 'second'
                    ? 'highlighted:second'
                    : 'idle:second',
              ),
            ),
          ],
        ),
      ),
    );
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

  testWidgets(
    'SettingsNavigationMixin reuses keys, respects custom store/prefix, and pushes once',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final customStore = <String, GlobalKey>{'preset': GlobalKey()};
      final observer = _RouteObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: _MixinNavigationHost(
            customStore: customStore,
            keyPrefix: 'settings-demo',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<_MixinNavigationHostState>(
        find.byType(_MixinNavigationHost),
      );
      expect(
        state.settingsNavigationKey('preset'),
        same(customStore['preset']),
      );
      final generated = state.settingsNavigationKey('item');
      expect(state.settingsNavigationKey('item'), same(generated));
      expect(generated.toString(), contains('settings-demo-item'));

      final routeCount = observer.routes.length;
      await tester.tap(find.text('open mixin'));
      await tester.tap(find.text('open mixin'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(observer.routes, hasLength(routeCount + 1));
      expect(observer.routes.last.settings.name, '混入详情');
      expect(find.text('mixin detail'), findsOneWidget);
    },
  );

  testWidgets(
    'SettingsTargetHighlightMixin highlights, scrolls, clears after duration, and cancels cleanly on dispose',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: _MixinHighlightHost(
            initialTarget: 'second',
            highlightDuration: Duration(milliseconds: 250),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('highlighted:second'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('idle:second'), findsOneWidget);

      // Re-trigger highlight and dispose before timer fires: must not throw.
      final state = tester.state<_MixinHighlightHostState>(
        find.byType(_MixinHighlightHost),
      );
      state.scrollToSettingsTarget(
        'second',
        highlightDuration: const Duration(seconds: 3),
      );
      await tester.pump();
      expect(find.text('highlighted:second'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SettingsTargetHighlightMixin supports highlight: false for scroll-only targets',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: _MixinHighlightHost(initialTarget: 'second', highlight: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('idle:second'), findsOneWidget);
      expect(find.text('highlighted:second'), findsNothing);
    },
  );
}
