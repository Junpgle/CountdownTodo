import Cocoa
import FlutterMacOS

class MacAppStatusBarController {
    static let shared = MacAppStatusBarController()

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var appChannel: FlutterMethodChannel?
    private var pomodoroChannel: FlutterMethodChannel?

    private var appStatusVisible = true
    private var appIconSize = 18

    private var phase: String = "idle"
    private var targetEndMs: Int64 = 0
    private var sessionStartMs: Int64 = 0
    private var mode: String = "countdown"
    private var isPaused: Bool = false
    private var pausedAtMs: Int64 = 0
    private var accumulatedMs: Int64 = 0
    private var pauseStartMs: Int64 = 0
    private var todoTitle: String = ""
    private var isRemote: Bool = false

    private var pauseItem: NSMenuItem?
    private var stopItem: NSMenuItem?

    private init() {}

    func setup(channel: FlutterMethodChannel) {
        appChannel = channel
    }

    func setPomodoroChannel(_ channel: FlutterMethodChannel) {
        pomodoroChannel = channel
    }

    func setVisible(_ visible: Bool, iconSize: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appStatusVisible = visible
            self.appIconSize = iconSize

            if visible {
                if self.isPomodoroActive {
                    self.refreshPomodoroDisplay()
                } else {
                    self.showAppIcon()
                }
            } else if !self.isPomodoroActive {
                self.removeStatusItem()
            }
        }
    }

    func updatePomodoroStatus(args: [String: Any]) {
        phase = args["phase"] as? String ?? "idle"
        targetEndMs = args["targetEndMs"] as? Int64 ?? 0
        sessionStartMs = args["sessionStartMs"] as? Int64 ?? 0
        mode = args["mode"] as? String ?? "countdown"
        isPaused = args["isPaused"] as? Bool ?? false
        pausedAtMs = args["pausedAtMs"] as? Int64 ?? 0
        accumulatedMs = args["accumulatedMs"] as? Int64 ?? 0
        pauseStartMs = args["pauseStartMs"] as? Int64 ?? 0
        todoTitle = args["todoTitle"] as? String ?? ""
        isRemote = args["isRemote"] as? Bool ?? false

        NSLog("[MacStatusBar] updatePomodoroStatus: phase=%@, targetEndMs=%lld, mode=%@", phase, targetEndMs, mode)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshPomodoroDisplay()
            self.scheduleNextUpdate()
        }
    }

    func clearPomodoroStatus() {
        NSLog("[MacStatusBar] clearPomodoroStatus called")
        phase = "idle"
        isRemote = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cancelTimer()
            if self.appStatusVisible {
                self.showAppIcon()
            } else {
                self.removeStatusItem()
            }
        }
    }

    private var isPomodoroActive: Bool {
        phase == "focusing" || phase == "breaking"
    }

    private func ensureStatusItem(length: CGFloat) -> NSStatusBarButton? {
        if statusItem == nil {
            NSLog("[MacStatusBar] Creating combined NSStatusItem")
            statusItem = NSStatusBar.system.statusItem(withLength: length)
        }

        statusItem?.isVisible = true
        statusItem?.length = length

        guard let button = statusItem?.button else {
            NSLog("[MacStatusBar] status item button is nil")
            return nil
        }

        button.isHidden = false
        button.isEnabled = true
        button.alphaValue = 1
        return button
    }

    private func showAppIcon() {
        let size = max(12, min(appIconSize, 28))
        let length = max(NSStatusItem.squareLength, CGFloat(size + 10))
        guard let button = ensureStatusItem(length: length) else { return }

        let image = NSImage(named: "AppIcon") ?? (NSApp.applicationIconImage.copy() as? NSImage)
        if let image = image {
            image.size = NSSize(width: size, height: size)
            image.isTemplate = false
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem?.length = length
        } else {
            button.image = nil
            button.title = "CDT"
            button.imagePosition = .noImage
            statusItem?.length = 42
        }

        button.toolTip = "CountDownTodo"
        setupMenu(includePomodoroControls: false)
        NSLog(
            "[MacStatusBar] app display updated: image=%@ title=%@ length=%.1f visible=%@",
            button.image == nil ? "no" : "yes",
            button.title,
            statusItem?.length ?? -1,
            statusItem?.isVisible == true ? "yes" : "no"
        )
        logStatusItemGeometry(button: button, context: "app")
    }

    private func refreshPomodoroDisplay() {
        guard isPomodoroActive else {
            clearPomodoroStatus()
            return
        }

        guard let button = ensureStatusItem(length: 64) else { return }
        button.image = nil
        button.imagePosition = .noImage

        pauseItem?.isHidden = isRemote
        stopItem?.isHidden = isRemote

        switch phase {
        case "focusing":
            if isPaused {
                let minutes = calculatePausedMinutes()
                button.title = "CDT\(minutes)"
                button.toolTip = buildTooltip(status: "已暂停")
            } else if mode == "countdown" {
                let minutes = calculateCountdownMinutes()
                button.title = "CDT\(minutes)"
                button.toolTip = buildTooltip(status: "剩余 \(minutes) 分钟")
            } else {
                let minutes = calculateCountUpMinutes()
                button.title = "CDT\(minutes)"
                button.toolTip = buildTooltip(status: "已专注 \(minutes) 分钟")
            }
        case "breaking":
            let minutes = calculateCountdownMinutes()
            button.title = "CDT\(minutes)"
            button.toolTip = "休息中，剩余 \(minutes) 分钟"
        default:
            return
        }

        setupMenu(includePomodoroControls: true)
        updatePauseMenuTitle()

        let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
        let width = ceil(button.title.size(withAttributes: [.font: font]).width)
        statusItem?.length = max(56, width + 18)
        statusItem?.isVisible = true
        NSLog(
            "[MacStatusBar] display updated: title=%@ length=%.1f visible=%@",
            button.title,
            statusItem?.length ?? -1,
            statusItem?.isVisible == true ? "yes" : "no"
        )
        logStatusItemGeometry(button: button, context: "pomodoro")
    }

    private func logStatusItemGeometry(button: NSStatusBarButton, context: String) {
        let buttonFrame = NSStringFromRect(button.frame)
        let windowFrame = button.window.map { NSStringFromRect($0.frame) } ?? "nil"
        let screenFrame = button.window?.screen.map { NSStringFromRect($0.frame) } ?? "nil"
        let isOnScreen = button.window?.isVisible == true ? "yes" : "no"
        NSLog(
            "[MacStatusBar] geometry %@: buttonFrame=%@ windowFrame=%@ screenFrame=%@ windowOnScreen=%@ hidden=%@ alpha=%.2f",
            context,
            buttonFrame,
            windowFrame,
            screenFrame,
            isOnScreen,
            button.isHidden ? "yes" : "no",
            button.alphaValue
        )
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            pauseItem = nil
            stopItem = nil
        }
    }

    private func setupMenu(includePomodoroControls: Bool) {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(title: "打开设置", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if includePomodoroControls {
            menu.addItem(NSMenuItem.separator())

            let p = NSMenuItem(title: "暂停", action: #selector(togglePause), keyEquivalent: "")
            p.target = self
            p.isHidden = isRemote
            menu.addItem(p)
            pauseItem = p

            let s = NSMenuItem(title: "结束专注", action: #selector(stopFocus), keyEquivalent: "")
            s.target = self
            s.isHidden = isRemote
            menu.addItem(s)
            stopItem = s
        } else {
            pauseItem = nil
            stopItem = nil
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 CountDownTodo", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func buildTooltip(status: String) -> String {
        let prefix = isRemote ? "远端专注" : "正在专注"
        if todoTitle.isEmpty {
            return "\(prefix)，\(status)"
        }
        return "\(prefix)：\(todoTitle)，\(status)"
    }

    private func updatePauseMenuTitle() {
        pauseItem?.title = isPaused ? "继续" : "暂停"
    }

    private func calculateCountdownMinutes() -> Int {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let remainingMs = targetEndMs - now
        guard remainingMs > 0 else { return 0 }
        return max(Int(ceil(Double(remainingMs) / 60000.0)), 1)
    }

    private func calculateCountUpMinutes() -> Int {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsedMs = now - sessionStartMs - accumulatedMs
        guard elapsedMs > 0 else { return 0 }
        return Int(floor(Double(elapsedMs) / 60000.0))
    }

    private func calculatePausedMinutes() -> Int {
        let frozenMs = pausedAtMs > 0 ? pausedAtMs : (pauseStartMs > 0 ? pauseStartMs : Int64(Date().timeIntervalSince1970 * 1000))

        if mode == "countdown" {
            let remainingMs = targetEndMs - frozenMs + accumulatedMs
            guard remainingMs > 0 else { return 0 }
            return max(Int(ceil(Double(remainingMs) / 60000.0)), 1)
        } else {
            let elapsedMs = frozenMs - sessionStartMs - accumulatedMs
            guard elapsedMs > 0 else { return 0 }
            return Int(floor(Double(elapsedMs) / 60000.0))
        }
    }

    private func scheduleNextUpdate() {
        cancelTimer()

        guard isPomodoroActive else { return }
        guard !isPaused else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var nextUpdateMs: Int64

        if mode == "countdown" || phase == "breaking" {
            let remainingMs = targetEndMs - now
            guard remainingMs > 0 else { refreshPomodoroDisplay(); return }
            let currentMinutes = Int(ceil(Double(remainingMs) / 60000.0))
            let msUntilNextMinute = remainingMs - Int64((currentMinutes - 1) * 60000)
            nextUpdateMs = max(msUntilNextMinute + 500, 1000)
        } else {
            let elapsedMs = now - sessionStartMs - accumulatedMs
            let currentMinutes = Int(floor(Double(elapsedMs) / 60000.0))
            let msUntilNextMinute = Int64((currentMinutes + 1) * 60000) - elapsedMs
            nextUpdateMs = max(msUntilNextMinute + 500, 1000)
        }

        let timer = Timer(timeInterval: Double(nextUpdateMs) / 1000.0, target: self, selector: #selector(timerFired), userInfo: nil, repeats: false)
        timer.tolerance = 5.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        guard !isPaused else {
            cancelTimer()
            return
        }
        refreshPomodoroDisplay()
        scheduleNextUpdate()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        showMainWindow()
        appChannel?.invokeMethod("openSettings", arguments: nil)
    }

    @objc private func togglePause() {
        guard !isRemote else { return }
        pomodoroChannel?.invokeMethod("togglePomodoroPause", arguments: nil)
    }

    @objc private func stopFocus() {
        guard !isRemote else { return }
        pomodoroChannel?.invokeMethod("stopPomodoroFocus", arguments: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
