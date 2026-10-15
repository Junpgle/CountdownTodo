import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/widgets/ai_settings_navigation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'enable_animations': false});
    PageTransitions.setPowerSaveMode(false);
    await PageTransitions.init();
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setPowerSaveMode(false);
  });
  tearDown(GlassPerformanceMonitor.stop);

  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    testWidgets(
      'card opens and locates transparency at $size, then returns to chat',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final navigator = GlobalKey<NavigatorState>();
        final observer = _RouteObserver();
        final before = LiquidGlassEffectService.configuration;
        var returned = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 340,
                  child: AiSettingsNavigationCard(
                    target: 'liquid_glass_transparency',
                    username: 'test',
                    onReturned: () async {
                      returned++;
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AnimationSettingsPage), findsNothing);
        expect(find.text('一键直达'), findsOneWidget);
        expect(find.text('设置 > 动画与特效 > 玻璃底色透明度'), findsOneWidget);
        await tester.tap(find.text('一键直达'));
        await tester.pumpAndSettle();
        expect(find.byType(AnimationSettingsPage), findsOneWidget);
        expect(observer.routes.last.settings.name, '设置 > 动画与特效 > 玻璃底色透明度');
        final slider = find.byKey(
          const ValueKey('animation-settings-liquid-glass-transparency'),
        );
        expect(slider.hitTestable(), findsOneWidget);
        expect(find.text('玻璃底色透明度').hitTestable(), findsOneWidget);
        expect(LiquidGlassEffectService.configuration.enabled, before.enabled);
        expect(
          LiquidGlassEffectService.configuration.transparencyPercent,
          before.transparencyPercent,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('一键直达'), findsOneWidget);
        expect(returned, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('unknown target has no clickable card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AiSettingsNavigationCard(target: 'unknown', username: 'test'),
      ),
    );
    expect(find.text('一键直达'), findsNothing);
  });
  testWidgets('Liquid Glass entry reveals its switch without enabling it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(
        home: AnimationSettingsPage(initialTarget: 'liquid_glass'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find
          .byKey(const ValueKey('animation-settings-liquid-glass-switch'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(LiquidGlassEffectService.configuration.enabled, false);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
