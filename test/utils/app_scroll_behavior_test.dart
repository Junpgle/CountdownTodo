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
      expect(physics.frictionFactor(0.0), greaterThan(0));
      expect(physics.frictionFactor(1.0), equals(0.0));
    });
  });
}
