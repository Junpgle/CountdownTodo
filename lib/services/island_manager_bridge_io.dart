import '../windows_island/island_manager.dart';
import '../utils/app_platform.dart';

class IslandManagerBridge {
  IslandManagerBridge._();

  static void clearIslandCache(String islandId) {
    if (!AppPlatform.isWindows) return;
    IslandManager().clearIslandCache(islandId);
  }

  static Future<void> createIsland(String islandId) {
    if (!AppPlatform.isWindows) return Future<void>.value();
    return IslandManager().createIsland(islandId);
  }
}
