import Cocoa
import FlutterMacOS
import WidgetKit
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    super.awakeFromNib()

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

    // Launch at startup channel
    let launchAtStartupChannel = FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    launchAtStartupChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(LaunchAtLogin.isEnabled)
      case "launchAtStartupSetEnabled":
        if let arguments = call.arguments as? [String: Any] {
          LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Native macOS app status bar icon. This avoids relying on Flutter asset
    // decoding inside tray_manager for the primary menu bar entry.
    let appStatusBarChannel = FlutterMethodChannel(
      name: "countdown_todo/macos_app_status_bar",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MacAppStatusBarController.shared.setup(channel: appStatusBarChannel)
    appStatusBarChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setVisible":
        let args = call.arguments as? [String: Any]
        let visible = args?["visible"] as? Bool ?? true
        let iconSize = args?["iconSize"] as? Int ?? 18
        MacAppStatusBarController.shared.setVisible(visible, iconSize: iconSize)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Setup status bar controller
    MacPomodoroStatusBarController.shared.setup()
    NSLog("[MainFlutterWindow] MacPomodoroStatusBarController setup done")

    // Status bar MethodChannel
    let statusBarChannel = FlutterMethodChannel(
      name: "countdown_todo/macos_status_bar",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MacAppStatusBarController.shared.setPomodoroChannel(statusBarChannel)
    statusBarChannel.setMethodCallHandler { (call, result) in
      NSLog("[MainFlutterWindow] statusBarChannel received: %@", call.method)
      switch call.method {
      case "updatePomodoroStatus":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }
        MacAppStatusBarController.shared.updatePomodoroStatus(args: args)
        result(true)
      case "clearPomodoroStatus":
        MacAppStatusBarController.shared.clearPomodoroStatus()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
