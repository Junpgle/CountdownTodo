import '../utils/app_platform.dart';
import '../windows_island/island_entry.dart' as island_entry;
import '../windows_island/island_ipc_paths.dart';
import 'windows_island_build_config.dart';

class WindowsIslandBootstrap {
  WindowsIslandBootstrap._();

  static const bool isCompiledIn = kWindowsIslandEnabledInBuild;

  static Future<bool> routeSecondaryWindow(List<String> args) async {
    if (kDisableWindowsIsland || !AppPlatform.isWindows) return false;
    if (args.isNotEmpty && args[0] == 'multi_window') {
      await appendIslandIpcLog(
        'main routed multi_window args=${args.join('|')}',
      );
      await island_entry.islandMain(args);
      return true;
    }
    return false;
  }
}
