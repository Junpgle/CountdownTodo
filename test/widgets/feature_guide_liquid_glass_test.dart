import 'package:countdown_todo/screens/feature_guide_screen.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/services/device_calendar_read_service.dart';
import 'package:countdown_todo/widgets/floating_glass_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setPowerSaveMode(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
  });

  tearDown(GlassPerformanceMonitor.stop);

  test(
    'system power saver suppresses glass without losing the user choice',
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
    },
  );

  testWidgets('guide appearance options offer the liquid glass toggle', (
    tester,
  ) async {
    await LiquidGlassEffectService.setEnabled(false);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GuideAppearanceOptions())),
    );
    // 等待组件异步读取当前主题与液态玻璃状态。
    await tester.pumpAndSettle();

    expect(find.text('液态玻璃效果'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guide-liquid-glass-switch')),
      findsOneWidget,
    );
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

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GuideAppearanceOptions())),
      );
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
    },
  );

  test('guide offer flag persists so the option is only shown once', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await LiquidGlassEffectService.isGuideOfferDone(), isFalse);

    await LiquidGlassEffectService.markGuideOffered();
    expect(await LiquidGlassEffectService.isGuideOfferDone(), isTrue);

    // 已展示过的用户重新走引导时不再受开关状态影响。
    await LiquidGlassEffectService.setEnabled(true);
    expect(await LiquidGlassEffectService.isGuideOfferDone(), isTrue);
  });

  test(
    'calendar read guide offer persists independently of its switch',
    () async {
      expect(await DeviceCalendarReadService.isGuideOfferDone(), isFalse);

      await DeviceCalendarReadService.markGuideOffered();
      expect(await DeviceCalendarReadService.isGuideOfferDone(), isTrue);

      // The feature remains off unless the user explicitly turns it on.
      expect(await DeviceCalendarReadService.isEnabled(), isFalse);
    },
  );

  group('default Standard Liquid Glass upgrade migration', () {
    test('enables Standard Liquid Glass on fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      await LiquidGlassEffectService.reloadForTesting();

      expect(LiquidGlassEffectService.isEnabled, isTrue);
      expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.standard);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('enable_liquid_glass'), isTrue);
      expect(prefs.getString('liquid_glass_effect_mode'), 'standard');
      expect(
        prefs.getBool('liquid_glass_default_standard_v725_migrated'),
        isTrue,
      );
    });

    test(
      'enables Standard Liquid Glass for upgrading users who had it off',
      () async {
        SharedPreferences.setMockInitialValues({
          'enable_liquid_glass': false,
          'liquid_glass_effect_mode': 'enhanced',
        });
        await LiquidGlassEffectService.reloadForTesting();

        expect(LiquidGlassEffectService.isEnabled, isTrue);
        expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.standard);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('enable_liquid_glass'), isTrue);
        expect(prefs.getString('liquid_glass_effect_mode'), 'standard');
      },
    );

    test(
      'preserves Enhanced Liquid Glass when user already had it enabled',
      () async {
        SharedPreferences.setMockInitialValues({
          'enable_liquid_glass': true,
          'liquid_glass_effect_mode': 'enhanced',
        });

        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {};
        try {
          await LiquidGlassEffectService.reloadForTesting();
        } finally {
          FlutterError.onError = previousErrorHandler;
        }

        expect(LiquidGlassEffectService.isEnabled, isTrue);
        expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.enhanced);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('liquid_glass_effect_mode'), 'enhanced');

        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
      },
    );

    test(
      'migration only runs once so subsequent opt-out is respected',
      () async {
        SharedPreferences.setMockInitialValues({});
        await LiquidGlassEffectService.reloadForTesting();
        expect(LiquidGlassEffectService.isEnabled, isTrue);

        await LiquidGlassEffectService.setEnabled(false);
        await LiquidGlassEffectService.reloadForTesting();

        expect(LiquidGlassEffectService.isEnabled, isFalse);
      },
    );
  });

  group('GuideLiquidGlassDefaultCard', () {
    testWidgets(
      'shows default-enabled notice and switches off/standard/enhanced in-page',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await LiquidGlassEffectService.reloadForTesting();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: GuideLiquidGlassDefaultCard()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('已默认启用「标准液态玻璃」'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('guide-changelog-liquid-glass-toggle')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('guide-changelog-liquid-glass-off')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(LiquidGlassEffectService.isEnabled, isFalse);
        expect(find.text('液态玻璃已关闭'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('guide-changelog-liquid-glass-standard')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(LiquidGlassEffectService.isEnabled, isTrue);
        expect(LiquidGlassEffectService.mode, LiquidGlassEffectMode.standard);
        expect(find.text('已默认启用「标准液态玻璃」'), findsOneWidget);
      },
    );

    testWidgets('shows preserved Enhanced notice when Enhanced is active', (
      tester,
    ) async {
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {};
      try {
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);
        await LiquidGlassEffectService.setEnabled(true);
      } finally {
        FlutterError.onError = previousErrorHandler;
      }

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GuideLiquidGlassDefaultCard())),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('已保留「增强液态玻璃」'), findsOneWidget);

      await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    });

    testWidgets(
      'changelog update guide page embeds GuideLiquidGlassDefaultCard',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await LiquidGlassEffectService.reloadForTesting();

        await tester.pumpWidget(
          const MaterialApp(
            home: FeatureGuideScreen(mode: FeatureGuideMode.changelog),
          ),
        );
        await tester.pump();

        expect(find.byType(GuideLiquidGlassDefaultCard), findsOneWidget);
        expect(
          find.byKey(const ValueKey('guide-changelog-liquid-glass-toggle')),
          findsOneWidget,
        );
      },
    );
  });
}
