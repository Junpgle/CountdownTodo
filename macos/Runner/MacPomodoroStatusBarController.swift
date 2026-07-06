import Cocoa
import FlutterMacOS

private final class MacStatusBarFallbackView: NSView {
    var title: String = "" {
        didSet { needsDisplay = true }
    }
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var leftClick: (() -> Void)?
    var rightClick: ((NSView) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        if let image = image {
            let size = min(bounds.height - 4, 18)
            let rect = NSRect(
                x: (bounds.width - size) / 2,
                y: (bounds.height - size) / 2,
                width: size,
                height: size
            )
            image.draw(in: rect)
            return
        }

        guard !title.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(
            x: max(0, (bounds.width - size.width) / 2),
            y: max(0, (bounds.height - size.height) / 2)
        ))
    }

    override func mouseDown(with event: NSEvent) {
        leftClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        rightClick?(self)
    }
}

class MacPomodoroStatusBarController {
    static let shared = MacPomodoroStatusBarController()

    private enum DisplayMode {
        case none
        case appIcon
        case pomodoro
    }

    private var statusItem: NSStatusItem?
    private var fallbackWindow: NSPanel?
    private var fallbackView: MacStatusBarFallbackView?
    private var displayMode: DisplayMode = .none
    private var timer: Timer?
    private var appChannel: FlutterMethodChannel?
    private var flutterChannel: FlutterMethodChannel?

    private var appStatusVisible = true
    private var appIconSize = 18
    private var appStatusReady = false

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

    // MARK: - Public

    func setup() {}

    func setAppFlutterChannel(_ channel: FlutterMethodChannel) {
        self.appChannel = channel
    }

    func setFlutterChannel(_ channel: FlutterMethodChannel) {
        self.flutterChannel = channel
    }

    func setAppStatusVisible(_ visible: Bool, iconSize: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appStatusVisible = visible
            self.appIconSize = iconSize
            self.appStatusReady = true

            if visible {
                if self.isPomodoroActive {
                    self.refreshDisplay()
                    self.scheduleNextUpdate()
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

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.appStatusReady else {
                NSLog("[MacStatusBar] update deferred until app status item is ready")
                return
            }
            self.refreshDisplay()
            self.scheduleNextUpdate()
        }
    }

    func clearPomodoroStatus() {
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

    // MARK: - Private

    private var isPomodoroActive: Bool {
        phase == "focusing" || phase == "breaking"
    }

    private func ensureStatusItem(length: CGFloat, mode: DisplayMode) -> NSStatusBarButton? {
        if statusItem == nil {
            NSLog("[MacStatusBar] Creating persistent NSStatusItem length=%.1f", length)
            let item = NSStatusBar.system.statusItem(withLength: length)
            item.isVisible = true
            statusItem = item
        }

        displayMode = mode
        statusItem?.isVisible = true
        statusItem?.length = length

        guard let button = statusItem?.button else {
            NSLog("[MacStatusBar] status item button is nil")
            return nil
        }

        button.isHidden = false
        button.isEnabled = true
        button.alphaValue = 1
        button.appearsDisabled = false
        return button
    }

    private func showStatusItem() {
        _ = ensureStatusItem(length: 64, mode: .pomodoro)
    }

    private func showAppIcon() {
        let size = max(12, min(appIconSize, 28))
        let length = max(NSStatusItem.squareLength, CGFloat(size + 10))
        guard let button = ensureStatusItem(length: length, mode: .appIcon) else { return }

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
        updateFallbackVisibility(button: button)
        scheduleGeometryProbe(context: "app")
    }

    private func removeStatusItem() {
        hideFallbackWindow()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            displayMode = .none
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

    private func refreshDisplay() {
        let title: String
        let tooltip: String
        let shouldHidePause: Bool
        let shouldHideStop: Bool

        switch phase {
        case "focusing":
            if isPaused {
                let minutes = calculatePausedMinutes()
                title = "⏸ \(minutes)分"
                tooltip = buildTooltip(status: "已暂停")
            } else if mode == "countdown" {
                let minutes = calculateCountdownMinutes()
                title = "🍅 \(minutes)分"
                tooltip = buildTooltip(status: "剩余 \(minutes) 分钟")
            } else {
                let minutes = calculateCountUpMinutes()
                title = "🍅 \(minutes)分"
                tooltip = buildTooltip(status: "已专注 \(minutes) 分钟")
            }
            shouldHidePause = isRemote
            shouldHideStop = isRemote

        case "breaking":
            let minutes = calculateCountdownMinutes()
            title = "☕ \(minutes)分"
            tooltip = "休息中，剩余 \(minutes) 分钟"
            shouldHidePause = true
            shouldHideStop = isRemote

        default:
            removeStatusItem()
            cancelTimer()
            return
        }

        let font = NSFont.menuBarFont(ofSize: 0)
        let width = ceil(title.size(withAttributes: [.font: font]).width)
        let desiredLength = max(56, width + 18)
        guard let button = ensureStatusItem(length: desiredLength, mode: .pomodoro) else {
            NSLog("[MacStatusBar] refreshDisplay: button is nil!")
            return
        }

        button.isHidden = false
        button.isEnabled = true
        button.alphaValue = 1
        button.appearsDisabled = false
        button.image = nil
        button.imagePosition = .noImage
        button.title = title
        button.toolTip = tooltip
        setupMenu(includePomodoroControls: true)
        pauseItem?.isHidden = shouldHidePause
        stopItem?.isHidden = shouldHideStop
        updatePauseMenuTitle()

        statusItem?.length = desiredLength
        statusItem?.isVisible = true
        NSLog(
            "[MacStatusBar] display updated: title=%@ length=%.1f visible=%@",
            button.title,
            statusItem?.length ?? -1,
            statusItem?.isVisible == true ? "yes" : "no"
        )
        logStatusItemGeometry(button: button, context: "pomodoro")
        updateFallbackVisibility(button: button)
        scheduleGeometryProbe(context: "pomodoro")
    }

    private func scheduleGeometryProbe(context: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            self.logStatusItemGeometry(button: button, context: "\(context)-probe")
            self.updateFallbackVisibility(button: button)
        }
    }

    private func logStatusItemGeometry(button: NSStatusBarButton, context: String) {
        let buttonFrame = NSStringFromRect(button.frame)
        let windowFrame = button.window.map { NSStringFromRect($0.frame) } ?? "nil"
        let screenFrame = button.window?.screen.map { NSStringFromRect($0.frame) } ?? "nil"
        let screenCount = NSScreen.screens.count
        let isOnScreen = button.window?.isVisible == true ? "yes" : "no"
        NSLog(
            "[MacStatusBar] geometry %@: buttonFrame=%@ windowFrame=%@ screenFrame=%@ screens=%d windowOnScreen=%@ hidden=%@ alpha=%.2f",
            context,
            buttonFrame,
            windowFrame,
            screenFrame,
            screenCount,
            isOnScreen,
            button.isHidden ? "yes" : "no",
            button.alphaValue
        )
    }

    private func updateFallbackVisibility(button: NSStatusBarButton) {
        guard shouldUseFallback(for: button) else {
            hideFallbackWindow()
            return
        }

        showFallbackWindow(
            title: button.image == nil ? button.title : "",
            image: button.image,
            width: statusItem?.length ?? max(56, button.frame.width + 16)
        )
    }

    private func shouldUseFallback(for button: NSStatusBarButton) -> Bool {
        guard let frame = button.window?.frame else { return true }
        let screenMaxX = button.window?.screen?.frame.maxX ?? NSScreen.main?.frame.maxX ?? 0
        return frame.origin.x <= 1 || frame.maxX >= screenMaxX - 1
    }

    private func showFallbackWindow(title: String, image: NSImage?, width: CGFloat) {
        let height: CGFloat = 22
        let safeWidth = max(28, ceil(width))
        let screen = buttonScreen() ?? NSScreen.main
        guard let screen = screen else { return }

        let rightInset: CGFloat = 260
        let x = max(screen.frame.minX + 8, screen.frame.maxX - safeWidth - rightInset)
        let y = screen.frame.maxY - height - 1
        let frame = NSRect(x: x, y: y, width: safeWidth, height: height)

        let view: MacStatusBarFallbackView
        if let existing = fallbackView {
            view = existing
        } else {
            view = MacStatusBarFallbackView(frame: NSRect(x: 0, y: 0, width: safeWidth, height: height))
            view.leftClick = { [weak self] in self?.showMainWindow() }
            view.rightClick = { [weak self] sourceView in
                guard let self = self, let menu = self.statusItem?.menu else { return }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sourceView.bounds.height), in: sourceView)
            }
            fallbackView = view
        }

        view.frame = NSRect(x: 0, y: 0, width: safeWidth, height: height)
        view.title = title
        view.image = image

        let window: NSPanel
        if let existing = fallbackWindow {
            window = existing
        } else {
            window = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.contentView = view
            fallbackWindow = window
        }

        window.setFrame(frame, display: true)
        if window.contentView !== view {
            window.contentView = view
        }
        window.orderFrontRegardless()
        NSLog("[MacStatusBar] fallback shown: frame=%@ title=%@ image=%@", NSStringFromRect(frame), title, image == nil ? "no" : "yes")
    }

    private func hideFallbackWindow() {
        if fallbackWindow?.isVisible == true {
            NSLog("[MacStatusBar] fallback hidden")
        }
        fallbackWindow?.orderOut(nil)
    }

    private func buttonScreen() -> NSScreen? {
        statusItem?.button?.window?.screen ?? NSScreen.main
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
        // 使用 pausedAtMs 或 pauseStartMs 作为暂停时间点
        let frozenMs = pausedAtMs > 0 ? pausedAtMs : (pauseStartMs > 0 ? pauseStartMs : Int64(Date().timeIntervalSince1970 * 1000))
        
        if mode == "countdown" {
            // 倒计时模式：显示剩余时间（暂停时冻结）
            // remaining = targetEndMs - frozenMs + accumulatedMs
            let remainingMs = targetEndMs - frozenMs + accumulatedMs
            guard remainingMs > 0 else { return 0 }
            return max(Int(ceil(Double(remainingMs) / 60000.0)), 1)
        } else {
            // 正计时模式：显示已专注时间（暂停时冻结）
            // elapsed = frozenMs - sessionStartMs - accumulatedMs
            let elapsedMs = frozenMs - sessionStartMs - accumulatedMs
            guard elapsedMs > 0 else { return 0 }
            return Int(floor(Double(elapsedMs) / 60000.0))
        }
    }

    private func scheduleNextUpdate() {
        cancelTimer()

        guard phase == "focusing" || phase == "breaking" else { return }
        guard !isPaused else { return }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var nextUpdateMs: Int64

        if mode == "countdown" || phase == "breaking" {
            let remainingMs = targetEndMs - now
            guard remainingMs > 0 else { refreshDisplay(); return }
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
        // 暂停状态下不更新显示，直接返回
        guard !isPaused else {
            cancelTimer()
            return
        }
        refreshDisplay()
        scheduleNextUpdate()
    }

    // MARK: - Menu Actions

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
        flutterChannel?.invokeMethod("togglePomodoroPause", arguments: nil)
    }

    @objc private func stopFocus() {
        guard !isRemote else { return }
        flutterChannel?.invokeMethod("stopPomodoroFocus", arguments: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
