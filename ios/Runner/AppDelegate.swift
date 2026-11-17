import Flutter
import UIKit
import EventKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private let strictFocusHapticsChannel = "countdown_todo/strict_focus_haptics"
  private let deviceCalendarReadChannel = "countdown_todo/device_calendar_read"
  private let deviceContextChannel = "com.math_quiz_app/device_context"
  private let calendarStore = EKEventStore()
  private lazy var locationManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    return manager
  }()
  private var pendingLocationResult: FlutterResult?
  private var locationTimeoutTimer: Timer?

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

      let contextChannel = FlutterMethodChannel(
        name: deviceContextChannel,
        binaryMessenger: controller.binaryMessenger
      )
      contextChannel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(nil)
          return
        }
        switch call.method {
        case "getLocation":
          self.readDeviceLocationForAi(result)
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

  private func readDeviceLocationForAi(_ result: @escaping FlutterResult) {
    let status: CLAuthorizationStatus
    if #available(iOS 14.0, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    guard status == .authorizedWhenInUse || status == .authorizedAlways else {
      result(FlutterError(code: "LOCATION_DENIED", message: "位置权限未授权", details: nil))
      return
    }
    if let cached = locationManager.location,
       Date().timeIntervalSince(cached.timestamp) <= 600 {
      deliverLocation(cached, result: result)
      return
    }
    if let existing = pendingLocationResult {
      existing(nil)
      pendingLocationResult = nil
    }
    locationTimeoutTimer?.invalidate()
    pendingLocationResult = result
    locationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
      guard let self, let pending = self.pendingLocationResult else { return }
      self.pendingLocationResult = nil
      self.locationManager.stopUpdatingLocation()
      if let cached = self.locationManager.location {
        self.deliverLocation(cached, result: pending)
      } else {
        pending(nil)
      }
    }
    locationManager.requestLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let pending = pendingLocationResult else { return }
    pendingLocationResult = nil
    locationTimeoutTimer?.invalidate()
    locationTimeoutTimer = nil
    if let loc = locations.last {
      deliverLocation(loc, result: pending)
    } else {
      pending(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard let pending = pendingLocationResult else { return }
    pendingLocationResult = nil
    locationTimeoutTimer?.invalidate()
    locationTimeoutTimer = nil
    if let cached = manager.location {
      deliverLocation(cached, result: pending)
    } else {
      pending(nil)
    }
  }

  private func deliverLocation(_ location: CLLocation, result: @escaping FlutterResult) {
    var payload: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy_meters": location.horizontalAccuracy,
      "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000)
    ]
    CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
      if let place = placemarks?.first {
        if let country = place.country { payload["country"] = country }
        if let region = place.administrativeArea { payload["region"] = region }
        if let city = place.locality ?? place.subAdministrativeArea { payload["city"] = city }
        if let district = place.subLocality { payload["district"] = district }
        let parts = [
          place.administrativeArea,
          place.locality,
          place.subLocality,
          place.thoroughfare,
          place.subThoroughfare
        ].compactMap { $0 }
        if !parts.isEmpty {
          payload["address"] = parts.joined()
        }
      }
      result(payload)
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
