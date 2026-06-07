import Cocoa
import FlutterMacOS

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

    super.awakeFromNib()
  }
}
