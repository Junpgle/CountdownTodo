import '../windows_island/island_channel.dart';

class IslandActionChannel {
  IslandActionChannel._();

  static Stream<Map<String, dynamic>> get actionStream =>
      IslandChannel.actionStream;
}
