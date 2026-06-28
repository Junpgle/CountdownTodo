import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupPomodoroStatusBarChannel()
  }

  private func setupPomodoroStatusBarChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "countdown_todo/macos_status_bar",
      binaryMessenger: controller.engine.binaryMessenger
    )
    MacPomodoroStatusBarController.shared.setFlutterChannel(channel)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.scheme == "countdowntodo" {
        guard let controller = application.mainWindow?.contentViewController as? FlutterViewController else {
          return
        }
        let channel = FlutterMethodChannel(
          name: "com.math_quiz_app/deep_links",
          binaryMessenger: controller.engine.binaryMessenger
        )
        channel.invokeMethod("openDeepLink", arguments: url.absoluteString)
      }
    }
  }
}
