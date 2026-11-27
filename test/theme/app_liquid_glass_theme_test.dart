import 'package:countdown_todo/theme/app_liquid_glass_theme.dart';
import 'package:countdown_todo/services/liquid_glass_effect_service.dart';
import 'package:countdown_todo/widgets/optional_liquid_glass_backdrop.dart';
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

  test('installs a glass layer for every Material button family', () {
    final theme = applyAppLiquidGlassTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      enabled: true,
    );

    final styles = <ButtonStyle?>[
      theme.elevatedButtonTheme.style,
      theme.filledButtonTheme.style,
      theme.outlinedButtonTheme.style,
      theme.textButtonTheme.style,
      theme.iconButtonTheme.style,
      theme.segmentedButtonTheme.style,
    ];

    for (final style in styles) {
      expect(style, isNotNull);
      expect(style!.backgroundBuilder, isNotNull);
      expect(
        style.backgroundColor!.resolve(const <WidgetState>{}),
        Colors.transparent,
      );
    }
  });

  test('leaves the stock Material theme untouched when disabled', () {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    );

    final theme = applyAppLiquidGlassTheme(base, enabled: false);

    expect(theme, same(base));
  });

  testWidgets('renders a glass layer behind themed buttons', (tester) async {
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
          body: Row(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Save')),
              IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassContainer), findsNWidgets(2));
  });

  testWidgets(
    'skips per-button backdrop blur unless enhanced over non-solid backdrop',
    (tester) async {
      await LiquidGlassEffectService.setEnabled(true);
      await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.standard);

      Widget buildThemed({
        required LiquidGlassEffectMode mode,
        bool? isSolidBackground,
      }) {
        final theme = applyAppLiquidGlassTheme(
          ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          enabled: true,
          mode: mode,
        );
        Widget body = Center(
          child: FilledButton(onPressed: () {}, child: const Text('Save')),
        );
        if (isSolidBackground != null) {
          body = OptionalLiquidGlassBackdropScope(
            isSolidBackground: isSolidBackground,
            child: body,
          );
        }
        return MaterialApp(
          theme: theme,
          home: Scaffold(body: body),
        );
      }

      await tester.pumpWidget(
        buildThemed(mode: LiquidGlassEffectMode.standard),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GlassContainer>(find.byType(GlassContainer))
            .settings
            ?.blur,
        0.0,
      );

      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {};
      try {
        await LiquidGlassEffectService.setMode(LiquidGlassEffectMode.enhanced);
      } finally {
        FlutterError.onError = previousErrorHandler;
      }

      await tester.pumpWidget(
        buildThemed(
          mode: LiquidGlassEffectMode.enhanced,
          isSolidBackground: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GlassContainer>(find.byType(GlassContainer))
            .settings
            ?.blur,
        0.0,
      );

      await tester.pumpWidget(
        buildThemed(
          mode: LiquidGlassEffectMode.enhanced,
          isSolidBackground: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GlassContainer>(find.byType(GlassContainer))
            .settings
            ?.blur,
        greaterThan(0.0),
      );
    },
  );
}
