import Flutter
import UIKit
import EventKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let strictFocusHapticsChannel = "countdown_todo/strict_focus_haptics"
  private let deviceCalendarReadChannel = "countdown_todo/device_calendar_read"
  private let calendarStore = EKEventStore()

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

      let calendarChannel = FlutterMethodChannel(
        name: deviceCalendarReadChannel,
        binaryMessenger: controller.binaryMessenger
      )
      calendarChannel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterError(code: "UNAVAILABLE", message: "Calendar store is unavailable", details: nil))
          return
        }
        switch call.method {
        case "checkPermission":
          result(self.hasCalendarReadPermission())
        case "requestPermission":
          self.requestCalendarReadPermission(result)
        case "getSources":
          guard self.hasCalendarReadPermission() else {
            result(FlutterError(code: "NO_PERMISSION", message: "Calendar read permission is not granted", details: nil))
            return
          }
          result(self.calendarSources())
        case "readEvents":
          guard self.hasCalendarReadPermission(),
                let args = call.arguments as? [String: Any],
                let startMs = args["startMs"] as? NSNumber,
                let endMs = args["endMs"] as? NSNumber,
                endMs.int64Value > startMs.int64Value else {
            result(FlutterError(code: "INVALID_ARGS", message: "A valid startMs/endMs range is required", details: nil))
            return
          }
          result(self.calendarEvents(startMs: startMs.int64Value, endMs: endMs.int64Value))
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

  private func hasCalendarReadPermission() -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func requestCalendarReadPermission(_ result: @escaping FlutterResult) {
    if hasCalendarReadPermission() {
      result(true)
      return
    }
    if #available(iOS 17.0, *) {
      calendarStore.requestFullAccessToEvents { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    } else {
      calendarStore.requestAccess(to: .event) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    }
  }

  private func calendarSources() -> [[String: Any]] {
    calendarStore.calendars(for: .event).map { calendar in
      [
        "id": calendar.calendarIdentifier,
        "name": calendar.title,
        "account": calendar.source.title,
        "color": calendar.cgColor?.toArgb() ?? NSNull()
      ]
    }
  }

  private func calendarEvents(startMs: Int64, endMs: Int64) -> [[String: Any]] {
    let start = Date(timeIntervalSince1970: TimeInterval(startMs) / 1000)
    let end = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000)
    let predicate = calendarStore.predicateForEvents(
      withStart: start,
      end: end,
      calendars: calendarStore.calendars(for: .event)
    )
    return calendarStore.events(matching: predicate).compactMap { event in
      guard event.endDate >= event.startDate else { return nil }
      return [
        "id": "\(event.eventIdentifier ?? event.calendarItemIdentifier)_\(Int64(event.startDate.timeIntervalSince1970 * 1000))",
        "calendarId": event.calendar.calendarIdentifier,
        "title": event.title ?? "未命名日程",
        "startMs": Int64(event.startDate.timeIntervalSince1970 * 1000),
        "endMs": Int64(event.endDate.timeIntervalSince1970 * 1000),
        "allDay": event.isAllDay,
        "location": event.location ?? "",
        "color": event.calendar.cgColor?.toArgb() ?? NSNull()
      ]
    }
  }
}

private extension CGColor {
  func toArgb() -> Int? {
    guard let components = components, components.count >= 3 else { return nil }
    let red = Int((components[0] * 255).rounded()) & 0xff
    let green = Int((components[1] * 255).rounded()) & 0xff
    let blue = Int((components[2] * 255).rounded()) & 0xff
    let alpha = Int(((components.count >= 4 ? components[3] : 1) * 255).rounded()) & 0xff
    return (alpha << 24) | (red << 16) | (green << 8) | blue
  }
}
