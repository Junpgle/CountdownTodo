import '../models.dart';

class WidgetService {
  static Future<void> dispose() async {}

  static Future<void> init() async {}

  static void setAppForeground(bool isForeground) {}

  static Future<void> updateAllWidgetData(
    String username,
    List<TodoItem> todos,
  ) async {}

  static Future<void> updateTodoWidget(List<TodoItem> todos) async {}
}
