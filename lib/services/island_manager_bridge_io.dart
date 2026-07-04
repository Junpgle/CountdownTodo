import '../windows_island/island_manager.dart';

class IslandManagerBridge {
  IslandManagerBridge._();

  static void clearIslandCache(String islandId) {
    IslandManager().clearIslandCache(islandId);
  }

  static Future<void> createIsland(String islandId) {
    return IslandManager().createIsland(islandId);
  }
}
