import '../windows_island/island_channel.dart';
import '../utils/app_platform.dart';

class IslandActionChannel {
  IslandActionChannel._();

  static Stream<Map<String, dynamic>> get actionStream => AppPlatform.isWindows
      ? IslandChannel.actionStream
      : Stream<Map<String, dynamic>>.empty();
}
