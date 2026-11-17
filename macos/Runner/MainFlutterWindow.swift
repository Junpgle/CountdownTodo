import Cocoa
import CoreLocation
import FlutterMacOS
import WidgetKit
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
  private var powerSaveStreamHandler: MacPowerSaveModeStreamHandler?
  private var deviceContextLocationProvider: MacDeviceContextLocationProvider?

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

    let clipboardImageChannel = FlutterMethodChannel(
      name: "countdown_todo/clipboard_image",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardImageChannel.setMethodCallHandler { (call, result) in
      guard call.method == "readImage" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let pasteboard = NSPasteboard.general
      let imageData = pasteboard.data(forType: .png) ??
        pasteboard.data(forType: .tiff).flatMap { tiffData in
          NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:])
        }
      guard let imageData = imageData else {
        result(nil)
        return
      }

      result([
        "bytes": FlutterStandardTypedData(bytes: imageData),
        "mimeType": "image/png",
        "displayName": "clipboard-image.png"
      ])
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

    // Native macOS app status bar icon.
    let appStatusBarChannel = FlutterMethodChannel(
      name: "countdown_todo/macos_app_status_bar",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    MacPomodoroStatusBarController.shared.setAppFlutterChannel(appStatusBarChannel)
    appStatusBarChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "configureIsland":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? true
        let showOnNotchlessDisplay = args?["showOnNotchlessDisplay"] as? Bool ?? true
        let remindersEnabled = args?["remindersEnabled"] as? Bool ?? true
        let clipboardLinksEnabled = args?["clipboardLinksEnabled"] as? Bool ?? true
        MacPomodoroStatusBarController.shared.configureIsland(
          enabled: enabled,
          showOnNotchlessDisplay: showOnNotchlessDisplay,
          remindersEnabled: remindersEnabled,
          clipboardLinksEnabled: clipboardLinksEnabled
        )
        result(true)
      case "getClipboardBrowserSettings":
        result(MacPomodoroStatusBarController.shared.clipboardBrowserSettings())
      case "setClipboardBrowser":
        guard let args = call.arguments as? [String: Any],
              let browserID = args["browserId"] as? String else {
          result(FlutterError(
            code: "INVALID_ARGS",
            message: "Missing browserId",
            details: nil
          ))
          return
        }
        result(MacPomodoroStatusBarController.shared.setPreferredClipboardBrowser(browserID))
      case "setVisible":
        let args = call.arguments as? [String: Any]
        let visible = args?["visible"] as? Bool ?? true
        let iconSize = args?["iconSize"] as? Int ?? 18
        MacPomodoroStatusBarController.shared.setAppStatusVisible(visible, iconSize: iconSize)
        result(true)
      case "setIslandVisibilityShortcut":
        let args = call.arguments as? [String: Any]
        let success = MacPomodoroStatusBarController.shared.configureVisibilityShortcut(
          key: args?["key"] as? String ?? "",
          command: args?["command"] as? Bool ?? false,
          option: args?["option"] as? Bool ?? false,
          control: args?["control"] as? Bool ?? false,
          shift: args?["shift"] as? Bool ?? false
        )
        result(success)
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
    MacPomodoroStatusBarController.shared.setFlutterChannel(statusBarChannel)
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
      case "updateOngoingActivity":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing activity", details: nil))
          return
        }
        MacPomodoroStatusBarController.shared.updateOngoingActivity(args: args)
        result(true)
      case "clearOngoingActivity":
        MacPomodoroStatusBarController.shared.clearOngoingActivity()
        result(true)
      case "updateIslandOverview":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing overview", details: nil))
          return
        }
        MacPomodoroStatusBarController.shared.updateIslandOverview(args: args)
        result(true)
      case "showIslandReminder":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing reminder", details: nil))
          return
        }
        MacPomodoroStatusBarController.shared.showIslandReminder(args: args)
        result(true)
      case "clearIslandReminders":
        MacPomodoroStatusBarController.shared.clearIslandReminders()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let powerSaveMethodChannel = FlutterMethodChannel(
      name: "com.math_quiz_app/power_save_mode",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    powerSaveMethodChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getPowerSaveMode", "refreshPowerSaveMode":
        result(MacPowerSaveModeStreamHandler.isLowPowerModeEnabled())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let powerSaveEventChannel = FlutterEventChannel(
      name: "com.math_quiz_app/power_save_mode_events",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let powerSaveHandler = MacPowerSaveModeStreamHandler()
    self.powerSaveStreamHandler = powerSaveHandler
    powerSaveEventChannel.setStreamHandler(powerSaveHandler)

    let deviceContextChannel = FlutterMethodChannel(
      name: "com.math_quiz_app/device_context",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let locationProvider = MacDeviceContextLocationProvider()
    self.deviceContextLocationProvider = locationProvider
    deviceContextChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getLocationPermissionStatus":
        result(locationProvider.permissionStatusString())
      case "requestLocationPermission":
        locationProvider.requestPermission(result)
      case "getLocation":
        locationProvider.getLocation(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

private final class MacPowerSaveModeStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?
  private var lastPublishedState: Bool?

  static func isLowPowerModeEnabled() -> Bool {
    if #available(macOS 12.0, *) {
      return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    return false
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    lastPublishedState = nil
    registerObserverIfNeeded()
    publishState(force: true)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObserver()
    eventSink = nil
    lastPublishedState = nil
    return nil
  }

  private func registerObserverIfNeeded() {
    guard observer == nil else { return }
    if #available(macOS 12.0, *) {
      observer = NotificationCenter.default.addObserver(
        forName: .NSProcessInfoPowerStateDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.publishState(force: false)
      }
    }
  }

  private func removeObserver() {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
  }

  private func publishState(force: Bool) {
    let enabled = Self.isLowPowerModeEnabled()
    if !force && lastPublishedState == enabled {
      return
    }
    lastPublishedState = enabled
    eventSink?(enabled)
  }

  deinit {
    removeObserver()
  }
}

private final class MacDeviceContextLocationProvider: NSObject, CLLocationManagerDelegate {
  private lazy var locationManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    return manager
  }()
  private var pendingPermissionResult: FlutterResult?
  private var pendingLocationResult: FlutterResult?
  private var locationTimeoutTimer: Timer?

  func permissionStatusString() -> String {
    let status: CLAuthorizationStatus
    if #available(macOS 11.0, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    switch status {
    case .authorizedAlways:
      return "granted"
    case .authorized:
      return "granted"
    case .denied:
      return "permanentlyDenied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "denied"
    @unknown default:
      return "denied"
    }
  }

  func requestPermission(_ result: @escaping FlutterResult) {
    let current = permissionStatusString()
    if current == "granted" || current == "permanentlyDenied" || current == "restricted" {
      result(current)
      return
    }
    pendingPermissionResult?(permissionStatusString())
    pendingPermissionResult = result
    if #available(macOS 10.15, *) {
      locationManager.requestWhenInUseAuthorization()
    } else {
      result("denied")
      pendingPermissionResult = nil
    }
  }

  func getLocation(_ result: @escaping FlutterResult) {
    guard permissionStatusString() == "granted" else {
      result(FlutterError(code: "LOCATION_DENIED", message: "位置权限未授权", details: nil))
      return
    }
    if let cached = locationManager.location,
       Date().timeIntervalSince(cached.timestamp) <= 600 {
      deliverLocation(cached, result: result)
      return
    }
    pendingLocationResult?(nil)
    pendingLocationResult = result
    locationTimeoutTimer?.invalidate()
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
    locationManager.startUpdatingLocation()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if let pending = pendingPermissionResult {
      let status = permissionStatusString()
      if status != "denied" {
        pendingPermissionResult = nil
        pending(status)
      } else if #available(macOS 11.0, *), manager.authorizationStatus != .notDetermined {
        pendingPermissionResult = nil
        pending(status)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let pending = pendingLocationResult else { return }
    pendingLocationResult = nil
    locationTimeoutTimer?.invalidate()
    locationTimeoutTimer = nil
    manager.stopUpdatingLocation()
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
    manager.stopUpdatingLocation()
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
