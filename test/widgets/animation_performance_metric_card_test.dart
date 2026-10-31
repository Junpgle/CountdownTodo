import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/animation_performance_metric_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoadPressureEvaluation Unit Tests', () {
    test('power save mode clamps load pressure to minimal', () {
      final evaluation = evaluateLoadPressure(
        powerSaveModeEnabled: true,
        animationsEnabled: true,
        motionBlurEnabled: true,
        layerBlurEnabled: true,
        liquidGlassEnabled: true,
        liquidGlassMode: LiquidGlassEffectMode.enhanced,
        liquidGlassBlur: 20,
        liquidGlassTransparency: 80,
        screenRadiusEnabled: true,
        lazyLoadEnabled: false,
      );

      expect(evaluation.scorePercent, 12);
      expect(evaluation.levelLabel, '极低');
      expect(evaluation.isHighPressure, isFalse);
      expect(evaluation.cautionTitle, '开启较多特效可能会导致卡顿');
      expect(evaluation.factors.first, contains('系统省电模式已介入'));
    });

    test('all effects disabled yields minimal load pressure', () {
      final evaluation = evaluateLoadPressure(
        powerSaveModeEnabled: false,
        animationsEnabled: false,
        motionBlurEnabled: false,
        layerBlurEnabled: false,
        liquidGlassEnabled: false,
        liquidGlassMode: LiquidGlassEffectMode.standard,
        liquidGlassBlur: 0,
        liquidGlassTransparency: 0,
        screenRadiusEnabled: false,
        lazyLoadEnabled: true,
      );

      expect(evaluation.scorePercent, lessThanOrEqualTo(28));
      expect(evaluation.levelLabel, '极低');
      expect(evaluation.isHighPressure, isFalse);
      expect(evaluation.cautionTitle, '开启较多特效可能会导致卡顿');
    });

    test('balanced effects yields moderate or light pressure', () {
      final evaluation = evaluateLoadPressure(
        powerSaveModeEnabled: false,
        animationsEnabled: true,
        motionBlurEnabled: false,
        layerBlurEnabled: false,
        liquidGlassEnabled: true,
        liquidGlassMode: LiquidGlassEffectMode.standard,
        liquidGlassBlur: 3,
        liquidGlassTransparency: 35,
        screenRadiusEnabled: true,
        lazyLoadEnabled: true,
      );

      expect(evaluation.scorePercent, inInclusiveRange(35, 55));
      expect(evaluation.isHighPressure, isFalse);
      expect(evaluation.factors, anyElement(contains('Liquid Glass 标准模式')));
    });

    test('enabling many heavy effects produces high load pressure', () {
      final evaluation = evaluateLoadPressure(
        powerSaveModeEnabled: false,
        animationsEnabled: true,
        motionBlurEnabled: true,
        layerBlurEnabled: true,
        liquidGlassEnabled: true,
        liquidGlassMode: LiquidGlassEffectMode.enhanced,
        liquidGlassBlur: 24,
        liquidGlassTransparency: 75,
        screenRadiusEnabled: true,
        lazyLoadEnabled: false,
      );

      expect(evaluation.scorePercent, greaterThanOrEqualTo(85));
      expect(evaluation.isHighPressure, isTrue);
      expect(evaluation.cautionTitle, '开启较多特效可能会导致卡顿');
      expect(evaluation.cautionDescription, contains('卡顿'));
    });

    test('color getters derive strictly from Theme colorScheme', () {
      const colorScheme = ColorScheme.light(
        primary: Color(0xFF112233),
        primaryContainer: Color(0xFF223344),
        secondary: Color(0xFF334455),
        secondaryContainer: Color(0xFF445566),
        tertiary: Color(0xFF556677),
        tertiaryContainer: Color(0xFF667788),
        error: Color(0xFF778899),
        errorContainer: Color(0xFF8899AA),
      );

      final lowEval = evaluateLoadPressure(
        powerSaveModeEnabled: true,
        animationsEnabled: false,
        motionBlurEnabled: false,
        layerBlurEnabled: false,
        liquidGlassEnabled: false,
        liquidGlassMode: LiquidGlassEffectMode.standard,
        liquidGlassBlur: 0,
        liquidGlassTransparency: 0,
        screenRadiusEnabled: false,
        lazyLoadEnabled: true,
      );
      expect(lowEval.getLevelColor(colorScheme), colorScheme.primary);
      expect(
        lowEval.getLevelContainerColor(colorScheme),
        colorScheme.primaryContainer,
      );

      final highEval = evaluateLoadPressure(
        powerSaveModeEnabled: false,
        animationsEnabled: true,
        motionBlurEnabled: true,
        layerBlurEnabled: true,
        liquidGlassEnabled: true,
        liquidGlassMode: LiquidGlassEffectMode.enhanced,
        liquidGlassBlur: 20,
        liquidGlassTransparency: 80,
        screenRadiusEnabled: true,
        lazyLoadEnabled: false,
      );
      expect(highEval.getLevelColor(colorScheme), colorScheme.error);
      expect(
        highEval.getLevelContainerColor(colorScheme),
        colorScheme.errorContainer,
      );
    });
  });

  group('AnimationPerformanceMetricCard Widget Tests', () {
    testWidgets(
      'initially collapsed showing only load pressure, expands to show all metrics',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnimationPerformanceMetricCard(
                  animationsEnabled: true,
                  motionBlurEnabled: false,
                  layerBlurEnabled: false,
                  liquidGlassEnabled: true,
                  liquidGlassMode: LiquidGlassEffectMode.standard,
                  liquidGlassBlur: 3,
                  liquidGlassTransparency: 35,
                  screenRadiusEnabled: true,
                  lazyLoadEnabled: true,
                  powerSaveModeEnabled: false,
                  testRefreshRate: 60.0,
                ),
              ),
            ),
          ),
        );

        // 验证初始状态：仅展示标题、刷新率以及综合负载压力指标
        expect(find.text('流畅度与负载压力'), findsOneWidget);
        expect(find.text('60 Hz 刷新率'), findsOneWidget);
        expect(find.text('综合负载压力'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('animation-performance-pressure-text')),
          findsOneWidget,
        );

        // 验证未展开时详细数值与卡顿提示处于收起状态
        expect(find.text('实时帧率'), findsNothing);
        expect(find.text('渲染耗时'), findsNothing);
        expect(find.text('流畅度达标率'), findsNothing);
        expect(find.text('开启较多特效可能会导致卡顿'), findsNothing);

        // 验证滑动滑块已按需求移除，不再存在
        expect(
          find.byKey(const ValueKey('animation-performance-test-slider')),
          findsNothing,
        );

        // 点击展开按钮
        final expandBtn = find.byKey(
          const ValueKey('animation-performance-expand-btn'),
        );
        expect(expandBtn, findsOneWidget);
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();

        // 验证展开后所有详细数值与卡顿警示完全展示
        expect(find.text('实时帧率'), findsOneWidget);
        expect(find.text('渲染耗时'), findsOneWidget);
        expect(find.text('流畅度达标率'), findsOneWidget);
        expect(find.text('开启较多特效可能会导致卡顿'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('animation-performance-caution-text')),
          findsOneWidget,
        );

        // 点击收起按钮，回到仅展示综合负载压力状态
        await tester.tap(expandBtn);
        await tester.pumpAndSettle();
        expect(find.text('实时帧率'), findsNothing);
        expect(find.text('综合负载压力'), findsOneWidget);
      },
    );

    testWidgets('accurately reflects live frame timings and jank detection', (
      tester,
    ) async {
      // 构造两帧：第一帧平稳 (2ms build, 3ms raster = 5ms < 16.6ms)
      // 第二帧严重卡顿 (15ms build, 12ms raster = 27ms > 16.6ms)
      final timingGood = FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 2000,
        rasterStart: 2100,
        rasterFinish: 5100,
        rasterFinishWallTime: 5100,
      );
      final timingBad = FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 15000,
        rasterStart: 15100,
        rasterFinish: 27100,
        rasterFinishWallTime: 27100,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimationPerformanceMetricCard(
                animationsEnabled: true,
                motionBlurEnabled: false,
                layerBlurEnabled: false,
                liquidGlassEnabled: false,
                liquidGlassMode: LiquidGlassEffectMode.standard,
                liquidGlassBlur: 0,
                liquidGlassTransparency: 0,
                screenRadiusEnabled: false,
                lazyLoadEnabled: true,
                powerSaveModeEnabled: false,
                initiallyExpanded: true,
                testRefreshRate: 60.0,
                initialTimingsForTesting: [timingGood, timingBad],
              ),
            ),
          ),
        ),
      );

      // 等待 Timer.periodic 或触发更新
      await tester.pump(const Duration(milliseconds: 700));

      // 验证流畅度达标率计算：2 帧中有 1 帧超时，达标率为 50.0%
      final smoothnessTextFinder = find.byKey(
        const ValueKey('animation-performance-smoothness-text'),
      );
      expect(smoothnessTextFinder, findsOneWidget);
      final Text smoothnessText = tester.widget(smoothnessTextFinder);
      expect(smoothnessText.data, '50.0%');

      // 验证超标帧提示
      expect(find.text('1 帧超出预算'), findsOneWidget);
    });

    testWidgets(
      'high pressure configuration turns caution banner to high alert',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnimationPerformanceMetricCard(
                  animationsEnabled: true,
                  motionBlurEnabled: true,
                  layerBlurEnabled: true,
                  liquidGlassEnabled: true,
                  liquidGlassMode: LiquidGlassEffectMode.enhanced,
                  liquidGlassBlur: 24,
                  liquidGlassTransparency: 80,
                  screenRadiusEnabled: true,
                  lazyLoadEnabled: false,
                  powerSaveModeEnabled: false,
                  initiallyExpanded: true,
                  testRefreshRate: 120.0,
                ),
              ),
            ),
          ),
        );

        expect(find.text('120 Hz 刷新率'), findsOneWidget);
        expect(find.text('开启较多特效可能会导致卡顿'), findsOneWidget);

        final cautionTextFinder = find.byKey(
          const ValueKey('animation-performance-caution-text'),
        );
        expect(cautionTextFinder, findsOneWidget);
        final Text cautionText = tester.widget(cautionTextFinder);
        expect(cautionText.data, contains('卡顿'));
      },
    );
  });

  group('AnimationSettingsPage Power Save Mode Banner Tests', () {
    testWidgets(
      'power save mode banner is hidden when power save is disabled',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: AnimationSettingsPage(powerSaveModeOverride: false),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('应用省电模式'), findsNothing);
      },
    );

    testWidgets(
      'power save mode banner is shown only when power save is enabled',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: AnimationSettingsPage(powerSaveModeOverride: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('应用省电模式'), findsOneWidget);
        expect(find.text('已开启'), findsOneWidget);
      },
    );
  });
}
