import 'package:countdown_todo/features/finance/widgets/finance_today_section.dart';
import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/utils/navigator_utils.dart';
import 'package:countdown_todo/widgets/home_sections.dart';
import 'package:countdown_todo/widgets/liquid_glass_live_preview_dock.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setPowerSaveMode(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    LiquidGlassEffectService.collapseFloatingPanel();
    LiquidGlassEffectService.isLivePreviewForced = false;
    LiquidGlassEffectService.isSettingsPageActive = false;
  });

  group('LiquidGlassEffectConfiguration & Calculations', () {
    test('default configuration has 70% scrim, 35% transparency, 3px blur', () {
      const config = LiquidGlassEffectConfiguration.disabled();
      expect(config.scrimCoveragePercent, 70);
      expect(config.transparencyPercent, 35);
      expect(config.blurSigma, 3.0);
    });

    test(
      'liquidGlassBackerOpacity behaves predictably with manual adjustments',
      () {
        const standardConfig = LiquidGlassEffectConfiguration(
          enabled: true,
          mode: LiquidGlassEffectMode.standard,
          scrimCoveragePercent: 70,
          transparencyPercent: 50,
          blurSigma: 16.0,
        );

        // Default (70% scrim, 50% transparency) preserves original opacity
        expect(
          liquidGlassBackerOpacity(0.75, standardConfig),
          closeTo(0.75, 0.001),
        );

        // Higher scrim coverage increases base opacity
        const heavyScrimConfig = LiquidGlassEffectConfiguration(
          enabled: true,
          mode: LiquidGlassEffectMode.standard,
          scrimCoveragePercent: 90,
          transparencyPercent: 50,
          blurSigma: 16.0,
        );
        expect(
          liquidGlassBackerOpacity(0.70, heavyScrimConfig),
          greaterThan(0.70),
        );

        // Lower scrim coverage decreases base opacity
        const lightScrimConfig = LiquidGlassEffectConfiguration(
          enabled: true,
          mode: LiquidGlassEffectMode.standard,
          scrimCoveragePercent: 35,
          transparencyPercent: 50,
          blurSigma: 16.0,
        );
        expect(
          liquidGlassBackerOpacity(0.70, lightScrimConfig),
          closeTo(0.35, 0.001),
        );

        // 100% transparency returns 0
        const fullTransparentConfig = LiquidGlassEffectConfiguration(
          enabled: true,
          mode: LiquidGlassEffectMode.standard,
          scrimCoveragePercent: 70,
          transparencyPercent: 100,
          blurSigma: 16.0,
        );
        expect(
          liquidGlassBackerOpacity(0.75, fullTransparentConfig),
          closeTo(0.0, 0.001),
        );

        // 0% transparency returns 1.0 (pure solid)
        const solidConfig = LiquidGlassEffectConfiguration(
          enabled: true,
          mode: LiquidGlassEffectMode.standard,
          scrimCoveragePercent: 70,
          transparencyPercent: 0,
          blurSigma: 16.0,
        );
        expect(
          liquidGlassBackerOpacity(0.75, solidConfig),
          closeTo(1.0, 0.001),
        );
      },
    );
  });

  group('LiquidGlassEffectService Live Preview & Persistence', () {
    test('previewAdjustments updates configuration and marks unsaved', () async {
      await LiquidGlassEffectService.setEnabled(true);
      expect(LiquidGlassEffectService.hasUnsavedChanges, isFalse);

      LiquidGlassEffectService.previewAdjustments(
        scrimCoveragePercent: 85,
        transparencyPercent: 65,
        blurSigma: 24.0,
      );

      expect(LiquidGlassEffectService.hasUnsavedChanges, isTrue);
      expect(LiquidGlassEffectService.configuration.scrimCoveragePercent, 85);
      expect(LiquidGlassEffectService.configuration.transparencyPercent, 65);
      expect(LiquidGlassEffectService.configuration.blurSigma, 24.0);

      // Save adjustments persists to SharedPreferences and clears unsaved flag
      await LiquidGlassEffectService.saveAdjustments();
      expect(LiquidGlassEffectService.hasUnsavedChanges, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('liquid_glass_scrim_coverage_percent'), 85);
      expect(prefs.getInt('liquid_glass_transparency_percent'), 65);
      expect(prefs.getDouble('liquid_glass_blur_sigma'), 24.0);
    });

    test('revertAdjustments restores persisted configuration', () async {
      await LiquidGlassEffectService.setEnabled(true);
      await LiquidGlassEffectService.saveAdjustments(); // save current as baseline

      final saved = LiquidGlassEffectService.persistedConfiguration;

      LiquidGlassEffectService.previewAdjustments(
        scrimCoveragePercent: 40,
        transparencyPercent: 90,
        blurSigma: 5.0,
      );
      expect(LiquidGlassEffectService.hasUnsavedChanges, isTrue);

      LiquidGlassEffectService.revertAdjustments();
      expect(LiquidGlassEffectService.hasUnsavedChanges, isFalse);
      expect(
        LiquidGlassEffectService.configuration.scrimCoveragePercent,
        saved.scrimCoveragePercent,
      );
      expect(
        LiquidGlassEffectService.configuration.transparencyPercent,
        saved.transparencyPercent,
      );
      expect(LiquidGlassEffectService.configuration.blurSigma, saved.blurSigma);
    });
  });

  group('LiquidGlassLivePreviewDock UI Flow', () {
    testWidgets('dock shows when unsaved changes exist outside settings page', (
      tester,
    ) async {
      await LiquidGlassEffectService.setEnabled(true);
      await LiquidGlassEffectService.saveAdjustments();

      LiquidGlassEffectService.isSettingsPageActive = false;
      LiquidGlassEffectService.previewAdjustments(scrimCoveragePercent: 88);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Home Dashboard Screen')),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LiquidGlassLivePreviewDock(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('效果实时预览中'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('还原'), findsOneWidget);

      // Tapping "保存" permanently saves and dismisses the dock
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(LiquidGlassEffectService.hasUnsavedChanges, isFalse);
      expect(find.text('效果实时预览中'), findsNothing);
    });

    testWidgets('dock is hidden while inside animation settings page', (
      tester,
    ) async {
      await LiquidGlassEffectService.setEnabled(true);
      LiquidGlassEffectService.isSettingsPageActive = true;
      LiquidGlassEffectService.previewAdjustments(scrimCoveragePercent: 88);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Settings Screen')),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LiquidGlassLivePreviewDock(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('效果实时预览中'), findsNothing);
    });

    testWidgets(
      'tapping adjustment button expands parameter sliders directly in-place without navigating away',
      (tester) async {
        await LiquidGlassEffectService.setEnabled(true);
        await LiquidGlassEffectService.saveAdjustments();

        LiquidGlassEffectService.isSettingsPageActive = false;
        LiquidGlassEffectService.previewAdjustments(scrimCoveragePercent: 92);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: appNavigatorKey,
            builder: (context, child) {
              return Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LiquidGlassLivePreviewDock(),
                  ),
                ],
              );
            },
            home: const Scaffold(
              body: Center(child: Text('Home Dashboard Screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('效果实时预览中'), findsOneWidget);
        final tuneButton = find.byKey(
          const ValueKey('liquid-glass-dock-tune-button'),
        );
        expect(tuneButton, findsOneWidget);

        // Tapping the tune button must expand the parameter panel directly in-place
        await tester.tap(tuneButton);
        await tester.pumpAndSettle();

        // Must NOT navigate away to AnimationSettingsPage; user stays on Home Dashboard Screen
        expect(find.byType(AnimationSettingsPage), findsNothing);
        expect(find.text('Home Dashboard Screen'), findsOneWidget);

        // Expanded in-place adjustment panel is now open
        expect(find.text('液态玻璃实时调节'), findsOneWidget);
        expect(find.text('即时生效'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('live-dock-liquid-glass-scrim-slider')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('live-dock-liquid-glass-transparency-slider'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('live-dock-liquid-glass-blur-slider')),
          findsOneWidget,
        );

        // Quick chips and bottom action bar are omitted when expanded to keep it slim and compact
        expect(find.text('35% 清透'), findsNothing);
        expect(find.text('0% 实体'), findsNothing);
        expect(find.text('还原上次'), findsNothing);
        expect(find.text('更多设置'), findsNothing);
        expect(find.text('保存效果'), findsNothing);

        // Tapping "恢复默认" resets values
        await tester.tap(find.text('恢复默认'));
        await tester.pumpAndSettle();
        expect(LiquidGlassEffectService.configuration.scrimCoveragePercent, 70);
        expect(LiquidGlassEffectService.configuration.transparencyPercent, 35);
        expect(LiquidGlassEffectService.configuration.blurSigma, 3.0);

        // Tapping collapse button collapses back to compact pill
        final collapseButton = find.byKey(
          const ValueKey('liquid-glass-dock-collapse-button'),
        );
        expect(collapseButton, findsOneWidget);
        await tester.tap(collapseButton);
        await tester.pumpAndSettle();

        expect(LiquidGlassEffectService.isFloatingPanelExpanded, isFalse);
        expect(find.text('液态玻璃实时调节'), findsNothing);
        expect(find.text('效果实时预览中'), findsOneWidget);

        // Compact pill supports "还原" and "保存"
        expect(
          find.byKey(const ValueKey('liquid-glass-dock-revert-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('liquid-glass-dock-save-button')),
          findsOneWidget,
        );
        expect(find.text('还原'), findsOneWidget);
        expect(find.text('保存'), findsOneWidget);

        // Tapping "保存" saves the adjustments permanently and dismisses live preview
        await tester.tap(
          find.byKey(const ValueKey('liquid-glass-dock-save-button')),
        );
        await tester.pumpAndSettle();

        expect(LiquidGlassEffectService.hasUnsavedChanges, isFalse);
        expect(find.text('效果实时预览中'), findsNothing);
      },
    );
  });

  group('AnimationSettingsPage UI Sliders & Actions', () {
    testWidgets(
      'renders all 3 adjustment sliders and allows real-time tuning',
      (tester) async {
        await LiquidGlassEffectService.setEnabled(true);
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(home: AnimationSettingsPage()),
        );
        await tester.pumpAndSettle();

        // Verify the 3 adjustment titles are present
        expect(find.text('底色遮蔽率'), findsOneWidget);
        expect(find.text('透光度'), findsOneWidget);
        expect(find.text('模糊程度'), findsOneWidget);

        // Verify quick chips
        expect(find.text('70% 默认'), findsOneWidget);
        expect(find.text('50% 平衡'), findsOneWidget);
        expect(find.text('16px 标准'), findsOneWidget);

        // Tap a quick chip (e.g. 50% 柔和)
        await tester.tap(find.text('50% 柔和'));
        await tester.pumpAndSettle();

        expect(LiquidGlassEffectService.configuration.scrimCoveragePercent, 50);
        expect(LiquidGlassEffectService.hasUnsavedChanges, isTrue);

        // Action card appears with Save button
        expect(find.text('效果已在全应用各界面实时生效'), findsOneWidget);
        expect(find.text('保存效果'), findsOneWidget);

        // Tap "保存效果"
        await tester.ensureVisible(find.text('保存效果'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存效果'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));

        expect(LiquidGlassEffectService.hasUnsavedChanges, isFalse);
      },
    );

    testWidgets(
      'tapping float adjustment button in AnimationSettingsPage starts live preview and expands floating panel',
      (tester) async {
        await LiquidGlassEffectService.setEnabled(true);
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: appNavigatorKey,
            home: const Scaffold(body: Center(child: Text('Home Screen'))),
          ),
        );
        await tester.pumpAndSettle();

        // Push AnimationSettingsPage
        appNavigatorKey.currentState!.push(
          MaterialPageRoute(builder: (_) => const AnimationSettingsPage()),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AnimationSettingsPage), findsOneWidget);
        final floatButton = find.byKey(
          const ValueKey('animation-settings-liquid-glass-float-button'),
        );
        expect(floatButton, findsOneWidget);

        // Tap float adjustment button
        await tester.ensureVisible(floatButton);
        await tester.pumpAndSettle();
        await tester.tap(floatButton);
        await tester.pumpAndSettle();

        // AnimationSettingsPage is popped, user is back on Home Screen
        expect(find.byType(AnimationSettingsPage), findsNothing);
        expect(find.text('Home Screen'), findsOneWidget);

        // Floating panel is now expanded and live preview is active
        expect(LiquidGlassEffectService.isFloatingPanelExpanded, isTrue);
        expect(LiquidGlassEffectService.isLivePreviewForced, isTrue);
      },
    );
  });

  group('Dashboard Sections Live Adjustment Participation', () {
    testWidgets(
      'Finance, ScreenTime, and Math cards participate in live parameter adjustments',
      (tester) async {
        await LiquidGlassEffectService.setEnabled(true);
        LiquidGlassEffectService.resetToDefaults();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ScreenTimeCard(
                      stats: const [],
                      isLight: true,
                      hasPermission: true,
                      onOpenSettings: () {},
                      onViewDetail: () {},
                    ),
                    MathStatsCard(stats: const {}, isLight: true, onTap: () {}),
                    FinanceTodaySection(username: 'test_user', isLight: true),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find static panels for these cards
        final initialPanels = tester
            .widgetList<Container>(
              find.byKey(
                const ValueKey<String>('optional-liquid-glass-static-panel'),
              ),
            )
            .toList();
        expect(initialPanels.length, greaterThanOrEqualTo(3));

        final initialDecorations = initialPanels
            .map((p) => p.decoration! as BoxDecoration)
            .toList();

        // Adjust parameters to extreme transparency and low scrim
        LiquidGlassEffectService.previewAdjustments(
          transparencyPercent: 95,
          scrimCoveragePercent: 20,
          blurSigma: 28,
        );
        await tester.pumpAndSettle();

        final updatedPanels = tester
            .widgetList<Container>(
              find.byKey(
                const ValueKey<String>('optional-liquid-glass-static-panel'),
              ),
            )
            .toList();
        expect(updatedPanels.length, greaterThanOrEqualTo(3));

        final updatedDecorations = updatedPanels
            .map((p) => p.decoration! as BoxDecoration)
            .toList();

        // Opacity of base colors in gradients must have noticeably reduced (more transparent)
        for (int i = 0; i < 3; i++) {
          final initGrad = initialDecorations[i].gradient! as LinearGradient;
          final updatedGrad = updatedDecorations[i].gradient! as LinearGradient;

          final initAlpha = initGrad.colors.last.a;
          final updatedAlpha = updatedGrad.colors.last.a;

          expect(updatedAlpha, lessThan(initAlpha));
        }

        // BackdropFilter blur must match adjusted 28 sigma
        final filters = tester.widgetList<BackdropFilter>(
          find.byType(BackdropFilter),
        );
        expect(filters, isNotEmpty);
      },
    );

    testWidgets(
      'fallback decorations have high opacity (>=0.90) in light wallpaper mode when Liquid Glass is disabled',
      (tester) async {
        await LiquidGlassEffectService.setEnabled(false);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
              useMaterial3: true,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ScreenTimeCard(
                      stats: const [],
                      isLight: true,
                      hasPermission: true,
                      onOpenSettings: () {},
                      onViewDetail: () {},
                    ),
                    MathStatsCard(stats: const {}, isLight: true, onTap: () {}),
                    FinanceTodaySection(username: 'test_user', isLight: true),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));

        final cards = tester.widgetList<OptionalLiquidGlassCard>(
          find.byType(OptionalLiquidGlassCard),
        );
        expect(cards, isNotEmpty);

        for (final card in cards) {
          final decoration = card.fallbackDecoration as BoxDecoration;
          final color = decoration.color!;
          // Must have high opacity (>= 0.90) so light-theme dark text remains readable on wallpaper
          expect(color.a, greaterThanOrEqualTo(0.90));
        }
      },
    );
  });
}
