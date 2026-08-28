import 'package:countdown_todo/widgets/floating_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:countdown_todo/services/liquid_glass_effect_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
