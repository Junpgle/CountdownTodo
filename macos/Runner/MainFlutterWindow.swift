import Cocoa
import FlutterMacOS
import WidgetKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let nativeChannel = FlutterMethodChannel(
      name: "com.math_quiz_app/window_native",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    nativeChannel.setMethodCallHandler { (call, result) in
      if call.method == "showNativeCloseDialog" {
        let alert = NSAlert()
        alert.messageText = "关闭确认"
        alert.informativeText = "选择操作："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "退出程序")
        alert.addButton(withTitle: "最小化到托盘")
        alert.buttons.last?.keyEquivalent = "\r"
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
          result(6)
        } else {
          result(7)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let widgetChannel = FlutterMethodChannel(
      name: "com.countdowntodo/widget",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    widgetChannel.setMethodCallHandler { (call, result) in
      if call.method == "writeWidgetSnapshot" || call.method == "saveWidgetSnapshot" {
        guard let args = call.arguments as? [String: Any],
              let jsonString = args["json"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing 'json' argument", details: nil))
          return
        }

        let appGroupId = "group.com.junpgle.countdowntodo"

        // Write to UserDefaults for Widget Extension
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
          userDefaults.set(jsonString, forKey: "widget_snapshot_json")
          userDefaults.synchronize()
        }

        // Also write to file (backward compatibility)
        if let containerURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: appGroupId
        ) {
          let fileURL = containerURL.appendingPathComponent("widget_snapshot.json")
          try? jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        if #available(macOS 11.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(true)
      } else if call.method == "reloadWidgets" {
        if #available(macOS 11.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Setup status bar controller
    MacPomodoroStatusBarController.shared.setup()

    // Status bar MethodChannel
    let statusBarChannel = FlutterMethodChannel(
      name: "countdown_todo/macos_status_bar",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    statusBarChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "updatePomodoroStatus":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }
        MacPomodoroStatusBarController.shared.updatePomodoroStatus(args: args)
        result(true)
      case "clearPomodoroStatus":
        MacPomodoroStatusBarController.shared.clearPomodoroStatus()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
