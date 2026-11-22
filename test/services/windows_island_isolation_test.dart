import 'dart:io';

import 'package:countdown_todo/services/clipboard_service.dart';
import 'package:countdown_todo/services/float_window_service.dart';
import 'package:countdown_todo/services/system_control_service.dart';
import 'package:countdown_todo/services/windows_island_bootstrap.dart';
import 'package:countdown_todo/widgets/island_debug_host.dart';
import 'package:flutter_test/flutter_test.dart';

const bool _disableWindowsIsland = bool.fromEnvironment(
  'countdown.disable_windows_island',
);

void main() {
  test(
    'only designated *_io boundaries import windows_island, win32, or ffi',
    () {
      const allowedBoundaryFiles = <String>{
        'lib/services/float_window_service_io.dart',
        'lib/services/windows_island_bootstrap_io.dart',
        'lib/services/island_manager_bridge_io.dart',
        'lib/services/island_action_channel_io.dart',
        'lib/widgets/island_debug_host_io.dart',
        'lib/services/clipboard_service_io.dart',
        'lib/services/system_control_service_io.dart',
      };

      final importPattern = RegExp(
        r'''^\s*(?:import|export)\s+['"](?:[^'"]*windows_island/|package:win32/|dart:ffi)''',
        multiLine: true,
      );

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final violations = <String>[];
      for (final entity in libDir.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalizedPath = entity.path.replaceAll('\\', '/');
        if (normalizedPath.startsWith('lib/windows_island/')) continue;

        final content = entity.readAsStringSync();
        if (importPattern.hasMatch(content) &&
            !allowedBoundaryFiles.contains(normalizedPath)) {
          violations.add(normalizedPath);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Found non-boundary files importing lib/windows_island/, package:win32/, or dart:ffi',
      );
    },
  );

  test('conditional stub isolation matches countdown.disable_windows_island define', () async {
    if (_disableWindowsIsland) {
      expect(WindowsIslandBootstrap.isCompiledIn, isFalse);
      expect(FloatWindowService.getDebugInfo()['enabled'], isFalse);
      expect(IslandDebugHost.shouldShowOverlay, isFalse);
      expect(
        await WindowsIslandBootstrap.routeSecondaryWindow(['multi_window']),
        isFalse,
      );
      final clipboard = ClipboardService();
      clipboard.startListening();
      expect(clipboard.isListening, isFalse);
      clipboard.stopListening();
      expect(SystemControlService.mediaInfoListenable.value.isEmpty, isTrue);
    } else {
      expect(WindowsIslandBootstrap.isCompiledIn, isTrue);
    }
  });
}
