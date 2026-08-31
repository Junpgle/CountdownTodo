import 'package:countdown_todo/utils/android_energy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidEnergyPolicy', () {
    test('uses a lower accelerometer sampling rate on Android', () {
      expect(
        AndroidEnergyPolicy.strictFocusSensorPeriodFor(isAndroid: true),
        const Duration(milliseconds: 200),
      );
      expect(
        AndroidEnergyPolicy.strictFocusSensorPeriodFor(isAndroid: false),
        const Duration(milliseconds: 100),
      );
    });

    test('limits decorative loops only on Android', () {
      expect(
        AndroidEnergyPolicy.decorativeRepeatCountFor(
          isAndroid: true,
          androidCount: 3,
        ),
        3,
      );
      expect(
        AndroidEnergyPolicy.decorativeRepeatCountFor(
          isAndroid: false,
          androidCount: 3,
        ),
        isNull,
      );
    });

    test('slows disconnected HTTP probes only on Android', () {
      expect(
        AndroidEnergyPolicy.disconnectedSyncProbeIntervalFor(
          isAndroid: true,
        ),
        const Duration(minutes: 2),
      );
      expect(
        AndroidEnergyPolicy.disconnectedSyncProbeIntervalFor(
          isAndroid: false,
        ),
        const Duration(minutes: 1),
      );
    });

    test('halves low-priority scroll wakeups only on Android', () {
      const defaultInterval = Duration(milliseconds: 50);
      expect(
        AndroidEnergyPolicy.decorativeScrollIntervalFor(
          isAndroid: true,
          defaultInterval: defaultInterval,
        ),
        const Duration(milliseconds: 100),
      );
      expect(
        AndroidEnergyPolicy.decorativeScrollIntervalFor(
          isAndroid: false,
          defaultInterval: defaultInterval,
        ),
        defaultInterval,
      );
    });

    test('uses an hourly Android foreground widget fallback', () {
      expect(
        AndroidEnergyPolicy.foregroundWidgetRefreshIntervalFor(
          isAndroid: true,
        ),
        const Duration(hours: 1),
      );
      expect(
        AndroidEnergyPolicy.foregroundWidgetRefreshIntervalFor(
          isAndroid: false,
        ),
        const Duration(minutes: 30),
      );
    });
  });
}
