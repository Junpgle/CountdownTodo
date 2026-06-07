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
      if call.method == "saveWidgetSnapshot" {
        guard let args = call.arguments as? [String: Any],
              let jsonString = args["json"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing 'json' argument", details: nil))
          return
        }

        guard let containerURL = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.com.mathquiz.junpgle.countdowntodo"
        ) else {
          result(FlutterError(code: "APP_GROUP_UNAVAILABLE", message: "App Group container not available", details: nil))
          return
        }

        let fileURL = containerURL.appendingPathComponent("widget_snapshot.json")

        do {
          try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
          if #available(macOS 11.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          result(true)
        } catch {
          result(FlutterError(code: "WRITE_FAILED", message: "Failed to write snapshot: \(error.localizedDescription)", details: nil))
        }
      } else if call.method == "reloadWidgets" {
        if #available(macOS 11.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
