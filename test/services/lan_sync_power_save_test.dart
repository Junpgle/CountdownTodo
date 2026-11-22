import 'dart:io';

import 'package:countdown_todo/services/lan_sync_service.dart';
import 'package:countdown_todo/services/power_save_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    LanSyncService.instance.powerSaveModeOverrideForTesting = null;
    await LanSyncService.instance.stop();
    PowerSaveModeService.updateFromPlatformForTesting(false);
  });

  test('PowerSaveModeService reports enabled on macOS when platform updates', () {
    PowerSaveModeService.updateFromPlatformForTesting(true);
    expect(
      PowerSaveModeService.isEnabled,
      Platform.isAndroid || Platform.isMacOS,
    );

    PowerSaveModeService.updateFromPlatformForTesting(false);
    expect(PowerSaveModeService.isEnabled, isFalse);
  });

  test(
    'LanSyncService does not auto-start or auto-probe when power save mode is enabled',
    () async {
      SharedPreferences.setMockInitialValues({
        'lan_sync_desktop_daemon_enabled': false,
        'lan_sync_auto_sync_enabled': true,
      });

      final service = LanSyncService.instance;
      service.powerSaveModeOverrideForTesting = true;

      await service.initFromPreferences();
      expect(service.isRunning, isFalse);

      await service.triggerBackgroundAutoSync();
      expect(service.isRunning, isFalse);
    },
  );
}
