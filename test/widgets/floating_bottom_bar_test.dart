import 'dart:async';

import 'package:countdown_todo/widgets/floating_bottom_bar.dart';
import 'package:countdown_todo/widgets/home_app_bar.dart';
import 'package:countdown_todo/widgets/home_quick_action_button.dart';
import 'package:countdown_todo/widgets/home_sections.dart';
import 'package:countdown_todo/theme/app_liquid_glass_theme.dart';
import 'package:countdown_todo/services/android_window_rendering_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/services/liquid_glass_effect_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(GlassPerformanceMonitor.stop);

  test('limits the floating treatment to mobile portrait phone layouts', () {
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: true,
        width: 390,
        height: 844,
      ),
      isTrue,
    );
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: true,
        width: 844,
        height: 390,
      ),
      isFalse,
    );
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: true,
        width: 800,
        height: 1280,
      ),
      isFalse,
    );
    expect(
      floatingBottomBarShouldFloatFor(
        isMobile: false,
        width: 390,
        height: 844,
      ),
      isFalse,
    );
  });

  test('scales the capsule width with the number of destinations', () {
    final threeItemWidth = floatingBottomNavigationWidthFor(
      390,
      itemCount: 3,
    );

    expect(threeItemWidth, closeTo(262, 0.001));
    expect(
      floatingBottomNavigationWidthFor(390, itemCount: 2),
      closeTo(threeItemWidth * 2 / 3, 0.001),
    );
    expect(
      floatingBottomNavigationWidthFor(390, itemCount: 4),
      closeTo(threeItemWidth * 4 / 3, 0.001),
    );
    expect(
      floatingBottomNavigationWidthFor(390, itemCount: 5),
      closeTo(358, 0.001),
    );
  });

  testWidgets('keeps the bar child when the effect is disabled',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    const childKey = Key('floating-bottom-bar-child');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingBottomBar(
            mobilePortraitOnly: false,
            height: 72,
            margin: EdgeInsets.zero,
            child: SizedBox(key: childKey),
          ),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    final childSize = tester.getSize(find.byKey(childKey));
    expect(childSize.width, lessThanOrEqualTo(800));
    expect(childSize.height, lessThanOrEqualTo(72));
    expect(childSize.height, greaterThan(68));
  });

  testWidgets('supports content-sized floating controls', (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassControl(
            height: null,
            margin: EdgeInsets.zero,
            mobilePortraitOnly: false,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Content-sized control'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.text('Content-sized control'), findsOneWidget);
  });

  testWidgets('does not add a second glass layer to stock buttons',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final theme = applyAppLiquidGlassTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      enabled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: FloatingGlassControl(
            height: 64,
            margin: EdgeInsets.zero,
            mobilePortraitOnly: false,
            child: FilledButton(
              onPressed: () {},
              child: const Text('Action'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('can keep interactive content on the native fallback',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    const childKey = Key('native-fallback-control-child');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassControl(
            height: null,
            margin: EdgeInsets.zero,
            mobilePortraitOnly: false,
            useLiquidGlass: false,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Native fallback control', key: childKey),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byType(GlassContainer), findsNothing);
  });

  test('resolves the shared top-bar title reveal progress', () {
    expect(
      floatingGlassTopBarTitleProgress(
        scrollOffset: 0,
        contentOffset: 60,
      ),
      0,
    );
    expect(
      floatingGlassTopBarTitleProgress(
        scrollOffset: 47,
        contentOffset: 60,
      ),
      closeTo(0.5, 0.001),
    );
    expect(
      floatingGlassTopBarTitleProgress(
        scrollOffset: 70,
        contentOffset: 60,
      ),
      1,
    );
  });

  testWidgets('fades scroll content without adding a blur layer',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassTopBarContentFade(
            topBarHeight: 80,
            child: ListView(
              children: const [
                SizedBox(height: 240, child: Text('Faded content')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Faded content'), findsOneWidget);
  });

  testWidgets('keeps content visible when Android 17 disables shader fades',
      (tester) async {
    final previousPolicy =
        AndroidWindowRenderingPolicy.disableShaderContentFade.value;
    addTearDown(() {
      AndroidWindowRenderingPolicy.disableShaderContentFade.value =
          previousPolicy;
    });
    AndroidWindowRenderingPolicy.disableShaderContentFade.value = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassTopBarContentFade(
            topBarHeight: 80,
            child: ListView(
              children: const [
                SizedBox(height: 240, child: Text('Unmasked content')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('Unmasked content'), findsOneWidget);
  });

  test('clamps a malformed Android 17 freeform top inset', () {
    final previousPolicy =
        AndroidWindowRenderingPolicy.disableShaderContentFade.value;
    addTearDown(() {
      AndroidWindowRenderingPolicy.disableShaderContentFade.value =
          previousPolicy;
    });
    AndroidWindowRenderingPolicy.disableShaderContentFade.value = true;

    const malformed = MediaQueryData(
      size: Size(360, 760),
      padding: EdgeInsets.only(top: 760),
      viewPadding: EdgeInsets.only(top: 760, bottom: 24),
      viewInsets: EdgeInsets.only(top: 760),
    );

    final normalized =
        AndroidWindowRenderingPolicy.normalizeCompactWindowMediaQuery(
            malformed);

    expect(normalized.padding.top, 64);
    expect(normalized.viewPadding.top, 64);
    expect(normalized.viewInsets.top, 64);
    expect(normalized.viewPadding.bottom, 24);
  });

  test('clamps an oversized top inset even before native mode detection', () {
    final previousPolicy =
        AndroidWindowRenderingPolicy.disableShaderContentFade.value;
    addTearDown(() {
      AndroidWindowRenderingPolicy.disableShaderContentFade.value =
          previousPolicy;
    });
    AndroidWindowRenderingPolicy.disableShaderContentFade.value = false;

    const malformed = MediaQueryData(
      size: Size(360, 760),
      padding: EdgeInsets.only(top: 760),
      viewPadding: EdgeInsets.only(top: 760, bottom: 24),
    );

    final normalized =
        AndroidWindowRenderingPolicy.normalizeCompactWindowMediaQuery(
            malformed);

    expect(normalized.padding.top, 64);
    expect(normalized.viewPadding.top, 64);
    expect(normalized.viewPadding.bottom, 24);
  });

  testWidgets('fades grouped sliver content beneath a pinned top bar',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar(
                pinned: true,
                title: Text('Sliver top bar'),
              ),
              FloatingGlassSliverContentFadeGroup(
                topBarHeight: 80,
                slivers: const [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 480,
                      child: Text('Sliver content'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sliver top bar'), findsOneWidget);
    expect(find.text('Sliver content'), findsOneWidget);
  });

  testWidgets('uses the shared top fade on AppBars', (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            flexibleSpace: const FloatingGlassTopBarBackground(),
            title: const Text('Top fade'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Top fade'), findsOneWidget);
  });

  testWidgets('keeps an embedded AppBar finite with the shared top fade',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppBar(
                toolbarHeight: 86,
                flexibleSpace: const FloatingGlassTopBarBackground(
                  unboundedHeight: 86,
                ),
                title: const Text('Embedded top fade'),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final appBarSize = tester.getSize(find.byType(AppBar));
    expect(appBarSize.height.isFinite, isTrue);
    expect(appBarSize.height, greaterThan(0));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Embedded top fade'), findsOneWidget);
  });

  testWidgets('wraps AppBar controls with the shared floating shell',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    final actionKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: FloatingGlassAppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {},
              icon: const Icon(Icons.arrow_back),
            ),
            title: const Text('Floating controls'),
            actions: [
              IconButton(
                key: actionKey,
                tooltip: 'Action',
                onPressed: () {},
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(FloatingGlassAppBarAction), findsNWidgets(2));
    expect(find.byKey(actionKey), findsOneWidget);
    expect(find.text('Floating controls'), findsOneWidget);
  });

  testWidgets('keeps text actions at their intrinsic width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: FloatingGlassAppBar(
            title: const Text('Text action'),
            actions: [
              TextButton(
                onPressed: () {},
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.byType(FloatingGlassAppBarAction), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps composite segmented actions out of circular shells',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: FloatingGlassAppBar(
            title: const Text('Segmented action'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.list)),
                    ButtonSegment(value: true, icon: Icon(Icons.grid_view)),
                  ],
                  selected: const {false},
                  onSelectionChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.byType(FloatingGlassAppBarAction), findsNothing);
  });

  testWidgets('animates an AppBar control into its glass shell',
      (tester) async {
    final collapseProgress = ValueNotifier<double>(0);

    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassAppBarAction(
            collapseProgress: collapseProgress,
            child: IconButton(
              tooltip: 'Animated action',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FloatingGlassControl), findsNothing);

    collapseProgress.value = 1;
    await tester.pump();
    expect(find.byType(FloatingGlassControl), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FloatingGlassControl), findsOneWidget);
    collapseProgress.dispose();
  });

  testWidgets('does not nest a second glass circle inside an AppBar action',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final collapseProgress = ValueNotifier<double>(1);
    final theme = applyAppLiquidGlassTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      enabled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: FloatingGlassAppBarAction(
            collapseProgress: collapseProgress,
            child: IconButton(
              tooltip: 'Action',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byType(FloatingGlassControl), findsOneWidget);
    expect(find.byType(GlassContainer), findsOneWidget);
    collapseProgress.dispose();
  });

  testWidgets('keeps the implicit settings back button plain at rest',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final theme = applyAppLiquidGlassTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      enabled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const SizedBox.shrink(),
          ),
          onGenerateInitialRoutes: (_, __) => [
            MaterialPageRoute<void>(
              builder: (_) => const SizedBox.shrink(),
            ),
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: const FloatingGlassAppBar(
                  title: Text('设置'),
                ),
                body: ListView.builder(
                  itemCount: 20,
                  itemBuilder: (context, index) => SizedBox(
                    height: 80,
                    child: Text('Setting $index'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final backButton = tester.widget<BackButton>(find.byType(BackButton));
    expect(backButton.style?.backgroundBuilder, isNotNull);
    expect(find.byType(FloatingGlassControl), findsNothing);
    expect(find.byType(GlassContainer), findsNothing);
  });

  testWidgets('home AppBar icon layers stay transparent inside the shell',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final theme = applyAppLiquidGlassTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      enabled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: HomeAppBar(
            username: 'Test user',
            timeSalutation: '晚上好',
            currentGreeting: '祝你今天一切顺利！',
            isLight: false,
            isSyncing: false,
            onSync: () {},
            onSettings: () {},
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final iconButtons =
        tester.widgetList<IconButton>(find.byType(IconButton)).toList();
    expect(iconButtons, isNotEmpty);
    expect(
      iconButtons.every((button) => button.style?.backgroundBuilder != null),
      isTrue,
    );
  });

  testWidgets('uses the shared draggable glass action for home content',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    final theme = applyAppLiquidGlassTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      enabled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              SectionHeader(
                title: '重要日',
                icon: Icons.timer_outlined,
                onAdd: () {},
              ),
              HomeQuickActionButton.compact(
                heroTag: 'home-content-action-test',
                onPressed: () {},
                tooltip: '快速操作',
                tint: Colors.deepPurple,
                foregroundColor: Colors.white,
                isDark: false,
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final iconButtons =
        tester.widgetList<IconButton>(find.byType(IconButton)).toList();
    expect(iconButtons, hasLength(1));
    expect(iconButtons.single.style?.backgroundBuilder, isNotNull);
    expect(find.byType(GlassContainer), findsNothing);
    expect(find.byType(GlassButton), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('uses the current theme primary for the active glass tint',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.deepPurple);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: colorScheme),
        home: Scaffold(
          body: LiquidGlassSwitch(value: true, onChanged: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      liquidGlassSwitchActiveColorFor(colorScheme),
      colorScheme.primary,
    );
    expect(
      liquidGlassSwitchActiveColorFor(colorScheme),
      isNot(Colors.blue),
    );
    expect(find.byType(GlassEffect), findsOneWidget);
    expect(find.byType(GlassSwitch), findsOneWidget);
    expect(
      tester.widget<GlassSwitch>(find.byType(GlassSwitch)).activeColor,
      colorScheme.primary,
    );
    expect(find.byType(LiquidGlassSwitch), findsOneWidget);
  });

  testWidgets('updates the glass switch before an async callback completes',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    final callbackCompleter = Completer<void>();
    bool? changedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidGlassSwitch(
            value: false,
            onChanged: (value) async {
              changedValue = value;
              await callbackCompleter.future;
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byType(LiquidGlassSwitch));
    await tester.pump();

    expect(changedValue, isTrue);
    expect(
      tester.widget<GlassSwitch>(find.byType(GlassSwitch)).value,
      isTrue,
    );
    expect(
        tester.widget<LiquidGlassSwitch>(find.byType(LiquidGlassSwitch)).value,
        isFalse);
    callbackCompleter.complete();
  });

  testWidgets('keeps list tile switches on the trailing edge on macOS',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          platform: TargetPlatform.macOS,
        ),
        home: Scaffold(
          body: LiquidGlassSwitchListTile(
            title: const Text('Glass setting'),
            value: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.leading, isNull);
    expect(tile.trailing, isNotNull);
  });

  testWidgets('keeps the LiquidGlassSwitch drag-to-toggle interaction',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    bool? changedValue;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: Scaffold(
          body: LiquidGlassSwitch(
            value: false,
            onChanged: (value) => changedValue = value,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.drag(find.byType(LiquidGlassSwitch), const Offset(48, 0));
    await tester.pumpAndSettle();

    expect(changedValue, isTrue);
  });

  testWidgets('uses the canonical liquid-glass capsule geometry',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidGlassSwitch(value: false, onChanged: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.getSize(find.byType(LiquidGlassSwitch)),
      const Size(58, 26),
    );
    expect(tester.getSize(find.byType(GlassEffect)), const Size(35.2, 22));
  });

  testWidgets('keeps switch list tiles draggable', (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    bool? changedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidGlassSwitchListTile(
            title: const Text('Glass setting'),
            value: false,
            onChanged: (value) => changedValue = value,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(LiquidGlassSwitch), findsOneWidget);
    await tester.drag(find.byType(LiquidGlassSwitch), const Offset(48, 0));
    await tester.pumpAndSettle();

    expect(changedValue, isTrue);
  });

  testWidgets('renders an inert glass switch when disabled', (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiquidGlassSwitch(
            value: true,
            onChanged: null,
            semanticLabel: 'Disabled setting',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.getSemantics(find.byType(LiquidGlassSwitch)),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasToggledState: true,
        isToggled: true,
        label: 'Disabled setting',
      ),
    );
  });

  testWidgets('keeps the top-bar shell on the real Liquid Glass renderer',
      (tester) async {
    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FloatingGlassControl(
            height: 48,
            borderRadius: 24,
            useTopBarGlass: true,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final container = tester.widget<GlassContainer>(
      find.byType(GlassContainer),
    );
    expect(container.quality, GlassQuality.standard);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('supports an explicitly requested top blur', (tester) async {
    final controller = ScrollController();

    await LiquidGlassEffectService.setEnabled(true);
    await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView.builder(
                controller: controller,
                itemCount: 20,
                itemBuilder: (context, index) => SizedBox(
                  height: 80,
                  child: Text('Content $index'),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FloatingGlassTopBarOverlay(
                  height: 80,
                  overlapStart: 20,
                  blur: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BackdropFilter), findsNothing);

    controller.jumpTo(40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(BackdropFilter), findsOneWidget);
    controller.dispose();
  });
}
