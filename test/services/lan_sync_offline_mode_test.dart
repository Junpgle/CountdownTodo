import 'dart:io';

import 'package:countdown_todo/services/lan_sync_service.dart';
import 'package:countdown_todo/services/power_save_mode_service.dart';
import 'package:countdown_todo/services/storage/app_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    LanSyncService.instance.powerSaveModeOverrideForTesting = null;
    await LanSyncService.instance.stop();
    PowerSaveModeService.updateFromPlatformForTesting(false);
  });

  test(
    'LanSyncService does not enable or start discovery by default when offline mode is off',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = LanSyncService.instance;

      await service.initFromPreferences();

      expect(service.autoSyncEnabled, isFalse);
      expect(service.isDaemonMode, isFalse);
      expect(service.isRunning, isFalse);
    },
  );

  test(
    'LanSyncService defaults discovery on when offline mode is enabled',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettingsStorage.setOfflineModeEnabled(true);
      final service = LanSyncService.instance;
      service.powerSaveModeOverrideForTesting = true;

      await service.initFromPreferences();

      final isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
      expect(service.autoSyncEnabled, isTrue);
      expect(service.isDaemonMode, isDesktop);
    },
  );

  test(
    'onOfflineModeChanged enables discovery on true and disables + stops on false',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = LanSyncService.instance;
      final isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;

      await service.onOfflineModeChanged(true);

      final prefs = await SharedPreferences.getInstance();
      expect(service.autoSyncEnabled, isTrue);
      expect(prefs.getBool('lan_sync_auto_sync_enabled'), isTrue);
      expect(service.isDaemonMode, isDesktop);
      if (isDesktop) {
        expect(prefs.getBool('lan_sync_desktop_daemon_enabled'), isTrue);
      }

      await service.onOfflineModeChanged(false);

      expect(service.autoSyncEnabled, isFalse);
      expect(service.isDaemonMode, isFalse);
      expect(service.isRunning, isFalse);
      expect(service.daemonRunningNotifier.value, isFalse);
      expect(prefs.getBool('lan_sync_auto_sync_enabled'), isFalse);
      expect(prefs.getBool('lan_sync_desktop_daemon_enabled'), isFalse);
    },
  );

  test(
    'user can manually re-enable discovery switches after turning off offline mode',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettingsStorage.setOfflineModeEnabled(false);
      final service = LanSyncService.instance;

      await service.onOfflineModeChanged(false);
      expect(service.autoSyncEnabled, isFalse);
      expect(service.isDaemonMode, isFalse);
      expect(service.isRunning, isFalse);

      await service.setAutoSyncEnabled(true);
      expect(service.autoSyncEnabled, isTrue);

      await service.setDesktopDaemonEnabled(true);
      expect(service.isDaemonMode, isTrue);

      await service.stop();
      await service.initFromPreferences();
      expect(service.autoSyncEnabled, isTrue);
      expect(service.isDaemonMode, isTrue);
    },
  );
}
