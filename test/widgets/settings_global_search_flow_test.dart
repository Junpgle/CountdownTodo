import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/models/search_scope.dart';
import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/search_service.dart';
import 'package:countdown_todo/utils/page_transitions.dart';
import 'package:countdown_todo/widgets/global_search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Routes extends NavigatorObserver {
  Route<dynamic>? lastPushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      lastPushed = route;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'enable_animations': true,
      'enable_lazy_load': false,
      'animation_duration': 300,
    });
    PageTransitions.setPowerSaveMode(false);
    await PageTransitions.init();
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setPowerSaveMode(false);
  });
  tearDown(GlassPerformanceMonitor.stop);

  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    testWidgets(
      'actual global search result locates transparency and returns at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final observer = Routes();
        final before = LiquidGlassEffectService.configuration;
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: GlobalSearchOverlay(
              warmupRemote: () async {},
              search: (query, {required scope, required recordHistory}) =>
                  query.isEmpty
                  ? Future.value(<SearchResult>[])
                  : SearchService.instance.search(
                      query,
                      scope: scope,
                      recordHistory: false,
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final more = find.byKey(const ValueKey('search_scope_more'));
        await tester.ensureVisible(more);
        await tester.tap(more);
        await tester.pumpAndSettle();
        final settingsScope = find.widgetWithText(
          CheckedPopupMenuItem<SearchScope>,
          SearchScope.settings.label,
        );
        await tester.ensureVisible(settingsScope);
        await tester.tap(settingsScope);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '液态玻璃透明度');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final result = find.text('玻璃底色透明度', findRichText: true);
        expect(result.hitTestable(), findsOneWidget);
        await tester.tap(result);
        await tester.pumpAndSettle();
        expect(find.byType(AnimationSettingsPage), findsOneWidget);
        expect(observer.lastPushed, isA<ContainerTransformRoute>());
        expect(observer.lastPushed!.settings.name, '设置 > 动画与特效 > 玻璃底色透明度');
        expect(
          find
              .byKey(
                const ValueKey('animation-settings-liquid-glass-transparency'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          LiquidGlassEffectService.configuration.transparencyPercent,
          before.transparencyPercent,
        );
        expect(LiquidGlassEffectService.configuration.enabled, before.enabled);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '液态玻璃透明度',
        );
        expect(find.text('搜索范围：${SearchScope.settings.label}'), findsOneWidget);
        expect(find.text('玻璃底色透明度', findRichText: true), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
