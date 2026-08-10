import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let strictFocusHapticsChannel = "countdown_todo/strict_focus_haptics"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: strictFocusHapticsChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "start":
          Self.emitStrictFocusHaptic(style: .medium)
          result(nil)
        case "pause":
          Self.emitStrictFocusHaptic(style: .light)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private static func emitStrictFocusHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let feedback = UIImpactFeedbackGenerator(style: style)
    feedback.prepare()
    feedback.impactOccurred()
  }
}
