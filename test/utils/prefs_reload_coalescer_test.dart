import 'package:countdown_todo/utils/prefs_reload_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsReloadCoalescer.reset();
  });

  tearDown(PrefsReloadCoalescer.reset);

  test(
    'coalesces concurrent reloads and throttles repeated calls within window',
    () async {
      var currentTime = DateTime(2026, 11, 26, 12, 0, 0);
      var reloadCount = 0;

      Future<void> fakeReload(SharedPreferences _) async {
        reloadCount++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final firstBatch = await Future.wait([
        PrefsReloadCoalescer.getFresh(
          bypassTestReload: true,
          reloadFn: fakeReload,
          clock: () => currentTime,
        ),
        PrefsReloadCoalescer.getFresh(
          bypassTestReload: true,
          reloadFn: fakeReload,
          clock: () => currentTime,
        ),
      ]);
      expect(firstBatch, hasLength(2));
      expect(reloadCount, 1);

      currentTime = currentTime.add(const Duration(milliseconds: 500));
      await PrefsReloadCoalescer.getFresh(
        bypassTestReload: true,
        reloadFn: fakeReload,
        clock: () => currentTime,
      );
      expect(reloadCount, 1);

      currentTime = currentTime.add(
        PrefsReloadCoalescer.defaultMinReloadInterval,
      );
      await PrefsReloadCoalescer.getFresh(
        bypassTestReload: true,
        reloadFn: fakeReload,
        clock: () => currentTime,
      );
      expect(reloadCount, 2);

      // markFresh refreshes the throttle window without running reloadFn.
      currentTime = currentTime.add(const Duration(seconds: 5));
      PrefsReloadCoalescer.markFresh(clock: () => currentTime);
      await PrefsReloadCoalescer.getFresh(
        bypassTestReload: true,
        reloadFn: fakeReload,
        clock: () => currentTime.add(const Duration(milliseconds: 100)),
      );
      expect(reloadCount, 2);

      await PrefsReloadCoalescer.getFresh(
        force: true,
        bypassTestReload: true,
        reloadFn: fakeReload,
        clock: () => currentTime.add(const Duration(milliseconds: 100)),
      );
      expect(reloadCount, 3);
    },
  );
}
