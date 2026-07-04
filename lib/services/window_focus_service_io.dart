import 'package:window_manager/window_manager.dart';

class WindowFocusService {
  WindowFocusService._();

  static Future<void> showAndFocus() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
