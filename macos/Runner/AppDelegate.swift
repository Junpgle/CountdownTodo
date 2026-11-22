import Cocoa
import FlutterMacOS
import QuickLookUI

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
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.scheme == "countdowntodo" {
        let targetWindow =
          mainFlutterWindow
          ?? application.mainWindow
          ?? application.windows.first(where: { $0.contentViewController is FlutterViewController })
        guard let controller = targetWindow?.contentViewController as? FlutterViewController else {
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

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    return true
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = MacPomodoroStatusBarController.shared
    panel.delegate = MacPomodoroStatusBarController.shared
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
  }
}
