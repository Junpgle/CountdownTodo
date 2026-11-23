import 'package:countdown_todo/screens/settings/handlers/permission_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android includes all 10 manageable app permissions', () {
    final defs = PermissionHandler.defsForPlatform(
      isWeb: false,
      isAndroid: true,
      isIOS: false,
      isMacOS: false,
      isWindows: false,
    );
    final keys = defs.map((def) => def['key'] as String).toList();
    expect(keys, [
      'notification',
      'exact_alarm',
      'battery_optimization',
      'storage',
      'usage_stats',
      'calendar',
      'location',
      'local_network',
      'live_updates',
      'request_install',
    ]);
  });

  test(
    'iOS and macOS show notification, calendar, and location permissions',
    () {
      for (final isIOS in [true, false]) {
        final defs = PermissionHandler.defsForPlatform(
          isWeb: false,
          isAndroid: false,
          isIOS: isIOS,
          isMacOS: !isIOS,
          isWindows: false,
        );
        expect(defs.map((def) => def['key']), [
          'notification',
          'calendar',
          'location',
        ]);
      }
    },
  );

  test('Windows only shows notification and Web shows none', () {
    final windowsDefs = PermissionHandler.defsForPlatform(
      isWeb: false,
      isAndroid: false,
      isIOS: false,
      isMacOS: false,
      isWindows: true,
    );
    expect(windowsDefs.map((def) => def['key']), ['notification']);

    final webDefs = PermissionHandler.defsForPlatform(
      isWeb: true,
      isAndroid: false,
      isIOS: false,
      isMacOS: false,
      isWindows: false,
    );
    expect(webDefs, isEmpty);
  });
}
