import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countdown_todo/utils/app_scroll_behavior.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppScrollBehavior tests', () {
    test('supports all major pointer device kinds', () {
      const behavior = AppScrollBehavior();
      final devices = behavior.dragDevices;

      expect(devices, contains(PointerDeviceKind.touch));
      expect(devices, contains(PointerDeviceKind.mouse));
      expect(devices, contains(PointerDeviceKind.trackpad));
      expect(devices, contains(PointerDeviceKind.stylus));
    });

    testWidgets('getScrollPhysics returns AppFluidScrollPhysics', (
      tester,
    ) async {
      const behavior = AppScrollBehavior();

      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: behavior,
          home: Builder(
            builder: (context) {
              final physics = behavior.getScrollPhysics(context);
              expect(physics, isA<AppFluidScrollPhysics>());
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('AppFluidScrollPhysics spring and friction parameters', () {
      const physics = AppFluidScrollPhysics();
      expect(physics.spring.damping, greaterThan(0));
      expect(physics.spring.stiffness, greaterThan(0));
      // Ensure spring is overdamped (damping >= 2 * sqrt(mass * stiffness))
      // so lists never oscillate back and forth or fly off-screen.
      final criticalDamping =
          2.0 *
          (physics.spring.mass * physics.spring.stiffness)
              .clamp(0.0, double.infinity)
              .toDouble();
      expect(
        physics.spring.damping * physics.spring.damping,
        greaterThanOrEqualTo(criticalDamping * 2.0),
      );
      expect(physics.spring.mass, lessThanOrEqualTo(1.0));
      expect(physics.frictionFactor(0.0), greaterThan(0));
      expect(physics.frictionFactor(1.0), equals(0.0));

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0.0,
        maxScrollExtent: 500.0,
        pixels: 0.0,
        viewportDimension: 800.0,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 3.0,
      );
      final sim = physics.createBallisticSimulation(metrics, -2000.0);
      expect(sim, isNotNull);
      // Max overscroll at -2000 px/s should stay tightly bounded (< 50px)
      // and settle back to 0 within 0.5s without bouncing positive.
      for (var t = 0.0; t <= 1.0; t += 0.02) {
        final x = sim!.x(t);
        expect(x, greaterThan(-50.0));
        expect(x, lessThanOrEqualTo(0.5));
      }
      expect(sim!.x(0.5).abs(), lessThan(1.0));
    });
  });
}
