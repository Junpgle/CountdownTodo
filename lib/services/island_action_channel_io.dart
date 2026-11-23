import '../windows_island/island_channel.dart';
import '../utils/app_platform.dart';
import 'windows_island_build_config.dart';

class IslandActionChannel {
  IslandActionChannel._();

  static Stream<Map<String, dynamic>> get actionStream =>
      (!kDisableWindowsIsland && AppPlatform.isWindows)
      ? IslandChannel.actionStream
      : Stream<Map<String, dynamic>>.empty();
}
