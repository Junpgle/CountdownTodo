import '../windows_island/island_manager.dart';
import '../utils/app_platform.dart';
import 'windows_island_build_config.dart';

class IslandManagerBridge {
  IslandManagerBridge._();

  static void clearIslandCache(String islandId) {
    if (kDisableWindowsIsland || !AppPlatform.isWindows) return;
    IslandManager().clearIslandCache(islandId);
  }

  static Future<void> createIsland(String islandId) {
    if (kDisableWindowsIsland || !AppPlatform.isWindows) {
      return Future<void>.value();
    }
    return IslandManager().createIsland(islandId);
  }
}
