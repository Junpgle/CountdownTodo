import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/animation_config_service.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('performance preset disables the liquid glass effect', () async {
    await LiquidGlassEffectService.setEnabled(true);

    await AnimationConfigService.setPreset(AnimationPreset.performance);

    expect(LiquidGlassEffectService.isEnabled, isFalse);
    expect(
      await AnimationConfigService.getPreset(),
      AnimationPreset.performance,
    );
  });

  test('balanced preset enables liquid glass in standard mode', () async {
    await AnimationConfigService.setPreset(AnimationPreset.balanced);

    expect(LiquidGlassEffectService.isEnabled, isTrue);
    expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.standard);
  });

  test('expressive preset enables liquid glass in enhanced mode', () async {
    await AnimationConfigService.setPreset(AnimationPreset.expressive);

    expect(LiquidGlassEffectService.isEnabled, isTrue);
    expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.enhanced);
  });

  test('manual glass tweaks clear the active preset selection', () async {
    await AnimationConfigService.setPreset(AnimationPreset.balanced);
    expect(await AnimationConfigService.getPreset(), AnimationPreset.balanced);

    // 模拟用户在下方手动切换液态玻璃开关/模式后的行为。
    await LiquidGlassEffectService.setEnabled(false);
    await AnimationConfigService.clearActivePreset();

    expect(await AnimationConfigService.getPreset(), isNull);
    expect(LiquidGlassEffectService.isEnabled, isFalse);
  });

  testWidgets(
    'AnimationSettingsPage exposes lazy load and skeleton screen independently',
    (tester) async {
      addTearDown(() async {
        await AnimationConfigService.setLazyLoadEnabled(true);
        await AnimationConfigService.setSkeletonScreenEnabled(true);
      });

      await tester.pumpWidget(const MaterialApp(home: AnimationSettingsPage()));
      await tester.pumpAndSettle();

      final lazySwitch = find.byKey(
        const ValueKey<String>('animation-settings-lazy-load-switch'),
      );
      final skeletonSwitch = find.byKey(
        const ValueKey<String>('animation-settings-skeleton-screen-switch'),
      );

      expect(lazySwitch, findsOneWidget);
      expect(skeletonSwitch, findsOneWidget);
      expect(find.text('懒加载优化'), findsOneWidget);
      expect(find.text('骨架屏加载'), findsOneWidget);

      await Scrollable.ensureVisible(
        tester.element(lazySwitch),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(lazySwitch);
      await tester.pumpAndSettle();

      expect(await AnimationConfigService.isLazyLoadEnabled(), isFalse);
      expect(await AnimationConfigService.isSkeletonScreenEnabled(), isTrue);
      expect(AnimationConfigService.skeletonScreenEnabled, isTrue);

      await Scrollable.ensureVisible(
        tester.element(skeletonSwitch),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(skeletonSwitch);
      await tester.pumpAndSettle();

      expect(await AnimationConfigService.isSkeletonScreenEnabled(), isFalse);
      expect(AnimationConfigService.skeletonScreenEnabled, isFalse);
    },
  );
}
