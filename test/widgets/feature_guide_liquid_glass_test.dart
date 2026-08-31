import 'package:countdown_todo/screens/feature_guide_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setPowerSaveMode(false);
  });

  test('system power saver suppresses glass without losing the user choice',
      () async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setPowerSaveMode(true);

    expect(LiquidGlassEffectService.isEnabled, isFalse);
    expect(LiquidGlassEffectService.preferredConfiguration.enabled, isTrue);
    expect(await LiquidGlassEffectService.loadEnabled(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('enable_liquid_glass'), isTrue);

    await LiquidGlassEffectService.setPowerSaveMode(false);
    expect(LiquidGlassEffectService.isEnabled, isTrue);
  });

  testWidgets('guide appearance options offer the liquid glass toggle',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GuideAppearanceOptions()),
    ));
    // 等待组件异步读取当前主题与液态玻璃状态。
    await tester.pumpAndSettle();

    expect(find.text('液态玻璃效果'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-liquid-glass-switch')),
        findsOneWidget);
    final initialSwitch = tester.widget<LiquidGlassSwitchListTile>(
      find.byType(LiquidGlassSwitchListTile).first,
    );
    expect(initialSwitch.value, isFalse);
    expect(LiquidGlassEffectService.isEnabled, isFalse);

    // 打开开关后立即持久化并发布配置。
    await tester.tap(find.byKey(const ValueKey('guide-liquid-glass-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(LiquidGlassEffectService.isEnabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('enable_liquid_glass'), isTrue);
    final toggledSwitch = tester.widget<LiquidGlassSwitchListTile>(
      find.byType(LiquidGlassSwitchListTile).first,
    );
    expect(toggledSwitch.value, isTrue);
  });

  testWidgets(
      'the switch reflects a previously enabled liquid glass preference',
      (tester) async {
    // 服务为进程级单例，用 API 驱动前置状态而不是预设偏好。
    await LiquidGlassEffectService.setEnabled(true);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GuideAppearanceOptions()),
    ));
    await tester.pumpAndSettle();

    final switchWidget = tester.widget<LiquidGlassSwitchListTile>(
      find.byType(LiquidGlassSwitchListTile).first,
    );
    expect(switchWidget.value, isTrue);

    // 关闭开关同样立即持久化。
    await tester.tap(find.byKey(const ValueKey('guide-liquid-glass-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(LiquidGlassEffectService.isEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('enable_liquid_glass'), isFalse);
  });

  test('guide offer flag persists so the option is only shown once', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await LiquidGlassEffectService.isGuideOfferDone(), isFalse);

    await LiquidGlassEffectService.markGuideOffered();
    expect(await LiquidGlassEffectService.isGuideOfferDone(), isTrue);

    // 已展示过的用户重新走引导时不再受开关状态影响。
    await LiquidGlassEffectService.setEnabled(true);
    expect(await LiquidGlassEffectService.isGuideOfferDone(), isTrue);
  });
}
