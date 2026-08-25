import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/screens/animation_settings_page.dart';
import 'package:countdown_todo/models.dart';
import 'package:countdown_todo/theme/app_liquid_glass_theme.dart';
import 'package:countdown_todo/widgets/app_settings_widgets.dart';
import 'package:countdown_todo/widgets/course_section_widget.dart';
import 'package:countdown_todo/widgets/home_sections.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(GlassPerformanceMonitor.stop);

  testWidgets('keeps the existing surface when Liquid Glass is disabled',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OptionalLiquidGlassSurface(
            height: 64,
            margin: EdgeInsets.zero,
            borderRadius: 32,
            tint: Colors.blue.withValues(alpha: 0.1),
            isDark: false,
            fallback: const SizedBox(key: Key('fallback')),
            child: const SizedBox(key: Key('glass-child')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('fallback')), findsOneWidget);
    expect(find.byKey(const Key('glass-child')), findsNothing);
  });

  testWidgets('offers Liquid Glass as an optional effect', (tester) async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: AnimationSettingsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Liquid Glass'), findsOneWidget);
    expect(find.text('全应用玻璃材质、折射与半透明层次 (可选)'), findsOneWidget);
    expect(find.text('Liquid Glass 模式'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('增强'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });

  testWidgets('uses static glass material for repeated settings surfaces',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              AppSettingsCard(child: Text('Shared settings content')),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(OptionalLiquidGlassPanel), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('optional-liquid-glass-static-panel'),
      ),
      findsOneWidget,
    );
    expect(find.byType(GlassContainer), findsNothing);
    expect(find.text('Shared settings content'), findsOneWidget);
  });

  testWidgets(
      'wallpaper cards use a translucent dark material in standard mode',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
        home: Scaffold(
          body: OptionalLiquidGlassCard(
            isDark: true,
            tint: colorScheme.scrim.withValues(alpha: 0.16),
            fallbackDecoration: const BoxDecoration(),
            child: const Text('Wallpaper card'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final container = tester.widget<Container>(
      find.byKey(
        const ValueKey<String>('optional-liquid-glass-static-panel'),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;

    expect(gradient.colors, hasLength(2));
    for (final color in gradient.colors) {
      expect(color.computeLuminance(), lessThan(0.08));
      expect(color.a, lessThan(0.5));
    }
  });

  testWidgets('wallpaper dashboard cards share one dark glass treatment',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.green);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
        home: Scaffold(
          body: Column(
            children: [
              ScreenTimeCard(
                stats: const [],
                hasPermission: false,
                isLight: true,
                onOpenSettings: () {},
                onViewDetail: () {},
              ),
              MathStatsCard(
                stats: const {},
                isLight: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final cards = tester
        .widgetList<Container>(
          find.byKey(
            const ValueKey<String>('optional-liquid-glass-static-panel'),
          ),
        )
        .toList();
    expect(cards, hasLength(2));
    for (final card in cards) {
      final decoration = card.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      expect(decoration.borderRadius, BorderRadius.circular(24));
      expect(gradient.colors.first.computeLuminance(), lessThan(0.08));
      expect(gradient.colors.last.a, lessThan(0.5));
    }

    final screenTimeTitle = tester.widget<Text>(
      find.text('未开启屏幕时间统计'),
    );
    final mathTitle = tester.widget<Text>(find.text('今日还未完成测验'));
    expect(screenTimeTitle.style?.color, colorScheme.onPrimary);
    expect(mathTitle.style?.color, colorScheme.onPrimary);
  });

  testWidgets('wallpaper cards keep fallback foregrounds when glass is off',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.green);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
        home: Scaffold(
          body: Column(
            children: [
              ScreenTimeCard(
                stats: const [],
                hasPermission: false,
                isLight: true,
                onOpenSettings: () {},
                onViewDetail: () {},
              ),
              MathStatsCard(
                stats: const {},
                isLight: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(GlassContainer), findsNothing);
    final screenTimeTitle = tester.widget<Text>(
      find.text('未开启屏幕时间统计'),
    );
    final mathTitle = tester.widget<Text>(find.text('今日还未完成测验'));
    expect(screenTimeTitle.style?.color, colorScheme.onPrimary);
    expect(mathTitle.style?.color, colorScheme.onSurface);
  });

  testWidgets('math fallback keeps its rounded outline in dark mode',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.dark,
    );
    final theme = ThemeData(colorScheme: colorScheme, useMaterial3: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: MathStatsCard(
            stats: const {},
            onTap: () {},
          ),
        ),
      ),
    );

    final card = tester.widget<OptionalLiquidGlassCard>(
      find.byType(OptionalLiquidGlassCard),
    );
    final decoration = card.fallbackDecoration as BoxDecoration;
    final border = decoration.border! as Border;
    expect(decoration.borderRadius, BorderRadius.circular(24));
    expect(border.top.width, 1);
    expect(border.top.color, theme.dividerColor.withValues(alpha: 0.5));
  });

  testWidgets('course cards use the shared optional glass shell',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    final course = CourseItem(
      uuid: 'liquid-glass-course',
      courseName: '高等数学',
      teacherName: '测试教师',
      date: '2026-08-25',
      weekday: 2,
      startTime: 800,
      endTime: 950,
      weekIndex: 1,
      roomName: '测试教室',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseSectionWidget(
            dashboardCourseData: {
              'title': '今日课程',
              'courses': [course],
            },
            isLight: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(OptionalLiquidGlassCard), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('optional-liquid-glass-static-panel'),
      ),
      findsOneWidget,
    );
    expect(find.text('高等数学'), findsOneWidget);
  });

  test('glass theme changes stock Material surfaces only while enabled', () {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    );

    expect(
      identical(
        applyAppLiquidGlassTheme(
          base,
          enabled: false,
          mode: LiquidGlassEffectMode.standard,
        ),
        base,
      ),
      isTrue,
    );

    final glass = applyAppLiquidGlassTheme(
      base,
      enabled: true,
      mode: LiquidGlassEffectMode.enhanced,
    );
    expect(glass.cardTheme.color, isNotNull);
    expect(glass.cardTheme.color!.a, lessThan(1));
    expect(glass.dialogTheme.backgroundColor, isNotNull);
    expect(glass.bottomSheetTheme.showDragHandle, isTrue);
    expect(glass.inputDecorationTheme.filled, isTrue);
  });

  test('maps standard and enhanced modes to distinct renderer tiers', () {
    expect(
      liquidGlassPanelQualityFor(LiquidGlassEffectMode.standard),
      GlassQuality.minimal,
    );
    expect(
      liquidGlassPanelQualityFor(LiquidGlassEffectMode.enhanced),
      GlassQuality.standard,
    );
    expect(
      liquidGlassSurfaceQualityFor(LiquidGlassEffectMode.standard),
      GlassQuality.standard,
    );
    expect(
      liquidGlassSurfaceQualityFor(LiquidGlassEffectMode.enhanced),
      GlassQuality.premium,
    );
    expect(
      liquidGlassPanelBackerOpacityFor(
        LiquidGlassEffectMode.enhanced,
        isDark: false,
      ),
      greaterThan(
        liquidGlassPanelBackerOpacityFor(
          LiquidGlassEffectMode.standard,
          isDark: false,
        ),
      ),
    );
    expect(
      liquidGlassPanelBackerOpacityFor(
        LiquidGlassEffectMode.standard,
        isDark: true,
      ),
      lessThan(0.35),
    );
    expect(
      liquidGlassAdaptiveStaticOpacityFor(isDark: true),
      lessThan(liquidGlassAdaptiveStaticOpacityFor(isDark: false)),
    );
    expect(
      liquidGlassSurfaceBackerOpacityFor(
        LiquidGlassEffectMode.enhanced,
        isDark: true,
      ),
      greaterThan(
        liquidGlassSurfaceBackerOpacityFor(
          LiquidGlassEffectMode.standard,
          isDark: true,
        ),
      ),
    );
  });

  test('persists the user-selected Liquid Glass mode', () async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('liquid_glass_effect_mode'),
      LiquidGlassEffectMode.enhanced.name,
    );
    expect(
      LiquidGlassEffectService.configuration.mode,
      LiquidGlassEffectMode.enhanced,
    );
  });

  test('latest rapid preference changes win without stale writes', () async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    final enabling = LiquidGlassEffectService.setEnabled(true);
    final disabling = LiquidGlassEffectService.setEnabled(false);
    await Future.wait([enabling, disabling]);

    var prefs = await SharedPreferences.getInstance();
    expect(LiquidGlassEffectService.configuration.enabled, isFalse);
    expect(prefs.getBool('enable_liquid_glass'), isFalse);

    final enhancing =
        LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);
    final standardizing =
        LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await Future.wait([enhancing, standardizing]);

    prefs = await SharedPreferences.getInstance();
    expect(
      LiquidGlassEffectService.configuration.mode,
      LiquidGlassEffectMode.standard,
    );
    expect(
      prefs.getString('liquid_glass_effect_mode'),
      LiquidGlassEffectMode.standard.name,
    );
  });

  test('enhanced mode is published after Premium preloading', () async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);

    expect(LiquidGlassEffectService.configuration.enabled, isTrue);
    expect(
      LiquidGlassEffectService.configuration.mode,
      LiquidGlassEffectMode.enhanced,
    );
  });
}
