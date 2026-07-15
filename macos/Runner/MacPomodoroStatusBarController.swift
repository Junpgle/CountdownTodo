import Cocoa
import FlutterMacOS

private final class MacIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MacIslandView: NSView {
    var phase: String = "idle" { didSet { needsDisplay = true } }
    var timeText: String = "" { didSet { needsDisplay = true } }
    var todoTitle: String = "" { didSet { needsDisplay = true } }
    var isPaused = false { didSet { needsDisplay = true } }
    var isRemote = false { didSet { needsDisplay = true } }
    var expanded = false { didSet { needsDisplay = true } }
    var hasNotch = false { didSet { needsDisplay = true } }
    var topInset: CGFloat = 0 { didSet { needsDisplay = true } }
    var reminderActive = false { didSet { needsDisplay = true } }
    var reminderTitle = "" { didSet { needsDisplay = true } }
    var reminderBody = "" { didSet { needsDisplay = true } }
    var reminderType = "" { didSet { needsDisplay = true } }
    var reminderQueueCount = 0 { didSet { needsDisplay = true } }

    var onExpansionChanged: ((Bool) -> Void)?
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenApp: (() -> Void)?
    var onAcknowledgeReminder: (() -> Void)?
    var onSnoozeReminder: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var pauseRect = NSRect.zero
    private var stopRect = NSRect.zero
    private var openRect = NSRect.zero
    private var acknowledgeRect = NSRect.zero
    private var snoozeRect = NSRect.zero

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let trackingAreaRef = trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard !expanded else { return }
        expanded = true
        onExpansionChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !reminderActive else { return }
        guard expanded else { return }
        expanded = false
        onExpansionChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if reminderActive {
            if acknowledgeRect.contains(point) {
                onAcknowledgeReminder?()
            } else if snoozeRect.contains(point) {
                onSnoozeReminder?()
            }
            return
        }
        if expanded {
            if pauseRect.contains(point), !isRemote {
                onTogglePause?()
                return
            }
            if stopRect.contains(point), !isRemote {
                onStop?()
                return
            }
            if openRect.contains(point) {
                onOpenApp?()
                return
            }
        }
        expanded.toggle()
        onExpansionChanged?(expanded)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let topJoinHeight = hasNotch ? max(topInset, 28) : 6
        let islandRect = NSRect(
            x: 0,
            y: hasNotch ? 0 : 6,
            width: bounds.width,
            height: bounds.height - (hasNotch ? 0 : 6)
        )
        let path = NSBezierPath(
            roundedRect: islandRect,
            xRadius: expanded ? 22 : 18,
            yRadius: expanded ? 22 : 18
        )
        NSColor.black.withAlphaComponent(0.96).setFill()
        path.fill()

        if hasNotch {
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: topJoinHeight).fill()
        }

        if reminderActive {
            drawReminder(topOffset: topJoinHeight)
        } else if expanded {
            drawExpanded(topOffset: topJoinHeight)
        } else {
            drawCompact(topOffset: topJoinHeight)
        }
    }

    private func drawCompact(topOffset: CGFloat) {
        let contentTop = hasNotch ? max(topOffset - 1, 26) : 6
        let centerY = contentTop + max((bounds.height - contentTop) / 2, 12)
        let accent = phase == "breaking" ? NSColor.systemTeal : NSColor.systemOrange

        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: centerY - 4, width: 8, height: 8)).fill()

        drawText(
            timeText,
            rect: NSRect(x: 29, y: centerY - 10, width: 66, height: 20),
            font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            color: .white,
            alignment: .left
        )

        let status = isPaused ? "已暂停" : (phase == "breaking" ? "休息中" : "专注中")
        drawText(
            status,
            rect: NSRect(x: bounds.width - 73, y: centerY - 9, width: 58, height: 18),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .white.withAlphaComponent(0.72),
            alignment: .right
        )
    }

    private func drawExpanded(topOffset: CGFloat) {
        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let accent = phase == "breaking" ? NSColor.systemTeal : NSColor.systemOrange
        let title = phase == "breaking" ? "休息时间" : (isRemote ? "其他设备正在专注" : "正在专注")

        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: contentTop + 4, width: 10, height: 10)).fill()
        drawText(
            title,
            rect: NSRect(x: 36, y: contentTop, width: bounds.width - 54, height: 20),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white,
            alignment: .left
        )

        drawText(
            timeText,
            rect: NSRect(x: 18, y: contentTop + 24, width: bounds.width - 36, height: 34),
            font: .monospacedDigitSystemFont(ofSize: 27, weight: .semibold),
            color: .white,
            alignment: .center
        )

        let task = todoTitle.isEmpty ? "CountDownTodo" : todoTitle
        drawText(
            task,
            rect: NSRect(x: 24, y: contentTop + 61, width: bounds.width - 48, height: 18),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .white.withAlphaComponent(0.62),
            alignment: .center
        )

        let buttonY = bounds.height - 38
        if isRemote {
            pauseRect = .zero
            stopRect = .zero
            openRect = NSRect(x: 18, y: buttonY, width: bounds.width - 36, height: 26)
            drawButton(title: "打开应用", rect: openRect, color: NSColor.white.withAlphaComponent(0.14))
        } else {
            let gap: CGFloat = 8
            let width = (bounds.width - 36 - gap) / 2
            pauseRect = NSRect(x: 18, y: buttonY, width: width, height: 26)
            stopRect = NSRect(x: pauseRect.maxX + gap, y: buttonY, width: width, height: 26)
            openRect = .zero
            drawButton(
                title: isPaused ? "继续" : "暂停",
                rect: pauseRect,
                color: NSColor.white.withAlphaComponent(0.14)
            )
            drawButton(
                title: "结束",
                rect: stopRect,
                color: NSColor.systemRed.withAlphaComponent(0.78)
            )
        }
    }

    private func drawReminder(topOffset: CGFloat) {
        pauseRect = .zero
        stopRect = .zero
        openRect = .zero

        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let accent: NSColor
        let category: String
        switch reminderType {
        case "course":
            accent = .systemBlue
            category = "课程提醒"
        case "special_todo":
            accent = .systemPurple
            category = "重要提醒"
        case "plan_block":
            accent = .systemIndigo
            category = "计划提醒"
        default:
            accent = .systemOrange
            category = "待办提醒"
        }

        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: contentTop + 4, width: 10, height: 10)).fill()
        drawText(
            category,
            rect: NSRect(x: 36, y: contentTop, width: bounds.width - 54, height: 20),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: accent,
            alignment: .left
        )
        if reminderQueueCount > 0 {
            drawText(
                "还有 \(reminderQueueCount) 条",
                rect: NSRect(x: bounds.width - 94, y: contentTop, width: 76, height: 20),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: .white.withAlphaComponent(0.5),
                alignment: .right
            )
        }
        drawText(
            reminderTitle,
            rect: NSRect(x: 20, y: contentTop + 27, width: bounds.width - 40, height: 24),
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .white,
            alignment: .center
        )
        drawText(
            reminderBody,
            rect: NSRect(x: 24, y: contentTop + 55, width: bounds.width - 48, height: 34),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .white.withAlphaComponent(0.66),
            alignment: .center
        )

        let gap: CGFloat = 8
        let buttonY = bounds.height - 38
        let width = (bounds.width - 36 - gap) / 2
        snoozeRect = NSRect(x: 18, y: buttonY, width: width, height: 26)
        acknowledgeRect = NSRect(x: snoozeRect.maxX + gap, y: buttonY, width: width, height: 26)
        drawButton(
            title: "10 分钟后",
            rect: snoozeRect,
            color: NSColor.white.withAlphaComponent(0.14)
        )
        drawButton(
            title: "好的",
            rect: acknowledgeRect,
            color: accent.withAlphaComponent(0.82)
        )
    }

    private func drawButton(title: String, rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        drawText(
            title,
            rect: NSRect(x: rect.minX, y: rect.minY + 5, width: rect.width, height: 17),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .white,
            alignment: .center
        )
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style,
            ]
        )
    }
}

/// macOS 刘海灵动岛控制器。
///
/// 保留原类名以兼容现有 Flutter MethodChannel，展示层不再创建 NSStatusItem。
class MacPomodoroStatusBarController {
    static let shared = MacPomodoroStatusBarController()

    private var islandWindow: MacIslandPanel?
    private var islandView: MacIslandView?
    private var timer: Timer?
    private var appChannel: FlutterMethodChannel?
    private var flutterChannel: FlutterMethodChannel?
    private var observers: [NSObjectProtocol] = []

    private var islandEnabled = true
    private var showOnNotchlessDisplay = true
    private var remindersEnabled = true
    private var isExpanded = false
    private var currentReminder: [String: Any]?
    private var reminderQueue: [[String: Any]] = []
    private var reminderIds: Set<String> = []
    private var lastScreenNumber: NSNumber?

    private var phase = "idle"
    private var targetEndMs: Int64 = 0
    private var sessionStartMs: Int64 = 0
    private var mode = "countdown"
    private var isPaused = false
    private var pausedAtMs: Int64 = 0
    private var accumulatedMs: Int64 = 0
    private var pauseStartMs: Int64 = 0
    private var todoTitle = ""
    private var isRemote = false

    private init() {}

    func setup() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplay()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplay()
        })
        for name in [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.refreshDisplay()
                }
            })
        }
    }

    func setAppFlutterChannel(_ channel: FlutterMethodChannel) {
        appChannel = channel
    }

    func setFlutterChannel(_ channel: FlutterMethodChannel) {
        flutterChannel = channel
    }

    func configureIsland(enabled: Bool, showOnNotchlessDisplay: Bool, remindersEnabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.islandEnabled = enabled
            self.showOnNotchlessDisplay = showOnNotchlessDisplay
            self.remindersEnabled = remindersEnabled
            if !remindersEnabled {
                self.clearIslandReminders()
            }
            self.refreshDisplay()
        }
    }

    // 兼容旧通道调用；应用图标不再显示到菜单栏。
    func setAppStatusVisible(_ visible: Bool, iconSize: Int) {
        NSLog("[MacIsland] Ignoring legacy status item visibility request")
    }

    func updatePomodoroStatus(args: [String: Any]) {
        phase = args["phase"] as? String ?? "idle"
        targetEndMs = int64Value(args["targetEndMs"])
        sessionStartMs = int64Value(args["sessionStartMs"])
        mode = args["mode"] as? String ?? "countdown"
        isPaused = args["isPaused"] as? Bool ?? false
        pausedAtMs = int64Value(args["pausedAtMs"])
        accumulatedMs = int64Value(args["accumulatedMs"])
        pauseStartMs = int64Value(args["pauseStartMs"])
        todoTitle = args["todoTitle"] as? String ?? ""
        isRemote = args["isRemote"] as? Bool ?? false

        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplay()
            self?.scheduleNextUpdate()
        }
    }

    func clearPomodoroStatus() {
        phase = "idle"
        isRemote = false
        DispatchQueue.main.async { [weak self] in
            self?.cancelTimer()
            self?.refreshDisplay()
        }
    }

    func showIslandReminder(args: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.islandEnabled, self.remindersEnabled else { return }
            let identifier = self.reminderIdentifier(args)
            guard !self.reminderIds.contains(identifier) else { return }
            self.reminderIds.insert(identifier)

            if self.currentReminder == nil {
                self.currentReminder = args
            } else {
                self.reminderQueue.append(args)
            }
            self.isExpanded = true
            self.refreshDisplay()
        }
    }

    func clearIslandReminders() {
        currentReminder = nil
        reminderQueue.removeAll()
        reminderIds.removeAll()
        isExpanded = false
        refreshDisplay()
    }

    private var isPomodoroActive: Bool {
        phase == "focusing" || phase == "breaking"
    }

    private func refreshDisplay() {
        let hasReminder = remindersEnabled && currentReminder != nil
        guard islandEnabled, isPomodoroActive || hasReminder else {
            hideIsland()
            return
        }

        guard let screen = preferredScreen() else {
            hideIsland()
            return
        }

        let geometry = screenGeometry(screen)
        guard geometry.hasNotch || showOnNotchlessDisplay else {
            hideIsland()
            return
        }

        let view = ensureIslandView()
        view.phase = phase
        view.timeText = calculateTimeText()
        view.todoTitle = todoTitle
        view.isPaused = isPaused
        view.isRemote = isRemote
        view.expanded = hasReminder || isExpanded
        view.hasNotch = geometry.hasNotch
        view.topInset = geometry.topInset
        view.reminderActive = hasReminder
        view.reminderTitle = currentReminder?["title"] as? String ?? ""
        view.reminderBody = currentReminder?["text"] as? String ?? ""
        view.reminderType = currentReminder?["type"] as? String ?? ""
        view.reminderQueueCount = reminderQueue.count

        let compactWidth = geometry.hasNotch ? max(190, geometry.notchWidth + 24) : 196
        let expanded = hasReminder || isExpanded
        let width = expanded ? max(hasReminder ? 310 : 286, compactWidth) : compactWidth
        let height: CGFloat = expanded
            ? max(hasReminder ? 178 : 166, geometry.topInset + (hasReminder ? 144 : 132))
            : (geometry.hasNotch ? max(54, geometry.topInset + 25) : 43)
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        let window = ensureIslandWindow(frame: frame, view: view)
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = window.isVisible && !reduceMotion && lastScreenNumber == screenNumber
        window.setFrame(frame, display: true, animate: shouldAnimate)
        lastScreenNumber = screenNumber
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.needsDisplay = true
        window.orderFrontRegardless()
    }

    private func ensureIslandView() -> MacIslandView {
        if let islandView = islandView { return islandView }
        let view = MacIslandView(frame: .zero)
        view.onExpansionChanged = { [weak self] expanded in
            guard let self = self else { return }
            self.isExpanded = expanded
            self.refreshDisplay()
        }
        view.onTogglePause = { [weak self] in
            guard let self = self, !self.isRemote else { return }
            self.flutterChannel?.invokeMethod("togglePomodoroPause", arguments: nil)
        }
        view.onStop = { [weak self] in
            guard let self = self, !self.isRemote else { return }
            self.flutterChannel?.invokeMethod("stopPomodoroFocus", arguments: nil)
        }
        view.onOpenApp = { [weak self] in self?.showMainWindow() }
        view.onAcknowledgeReminder = { [weak self] in
            self?.handleCurrentReminder(snoozeMinutes: nil)
        }
        view.onSnoozeReminder = { [weak self] in
            self?.handleCurrentReminder(snoozeMinutes: 10)
        }
        islandView = view
        return view
    }

    private func handleCurrentReminder(snoozeMinutes: Int?) {
        guard let reminder = currentReminder else { return }
        if let minutes = snoozeMinutes {
            flutterChannel?.invokeMethod("snoozeIslandReminder", arguments: [
                "reminder": reminder,
                "minutes": minutes,
            ])
        } else {
            flutterChannel?.invokeMethod("acknowledgeIslandReminder", arguments: reminder)
        }

        reminderIds.remove(reminderIdentifier(reminder))
        currentReminder = reminderQueue.isEmpty ? nil : reminderQueue.removeFirst()
        isExpanded = currentReminder != nil
        refreshDisplay()
        if currentReminder == nil, isPomodoroActive, !isPaused {
            scheduleNextUpdate()
        }
    }

    private func reminderIdentifier(_ reminder: [String: Any]) -> String {
        if let number = reminder["notifId"] as? NSNumber {
            return number.stringValue
        }
        if let value = reminder["notifId"] {
            return String(describing: value)
        }
        return "\(reminder["title"] ?? "")@\(reminder["triggerAtMs"] ?? "")"
    }

    private func ensureIslandWindow(frame: NSRect, view: MacIslandView) -> MacIslandPanel {
        if let islandWindow = islandWindow { return islandWindow }

        let window = MacIslandPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.animationBehavior = .utilityWindow
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.becomesKeyOnlyIfNeeded = true
        window.acceptsMouseMovedEvents = true
        window.contentView = view
        islandWindow = window
        return window
    }

    private func hideIsland() {
        isExpanded = false
        cancelTimer()
        islandWindow?.orderOut(nil)
    }

    private func preferredScreen() -> NSScreen? {
        if #available(macOS 12.0, *) {
            if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notched
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func screenGeometry(_ screen: NSScreen) -> (hasNotch: Bool, topInset: CGFloat, notchWidth: CGFloat) {
        if #available(macOS 12.0, *) {
            let topInset = screen.safeAreaInsets.top
            if topInset > 0,
               let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea {
                return (true, topInset, max(0, right.minX - left.maxX))
            }
        }
        return (false, 0, 0)
    }

    private func calculateTimeText() -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let milliseconds: Int64

        if isPaused {
            let frozen = pausedAtMs > 0 ? pausedAtMs : (pauseStartMs > 0 ? pauseStartMs : now)
            if mode == "countdown" || phase == "breaking" {
                milliseconds = max(0, targetEndMs - frozen + accumulatedMs)
            } else {
                milliseconds = max(0, frozen - sessionStartMs - accumulatedMs)
            }
        } else if mode == "countdown" || phase == "breaking" {
            milliseconds = max(0, targetEndMs - now)
        } else {
            milliseconds = max(0, now - sessionStartMs - accumulatedMs)
        }

        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02lld:%02lld:%02lld", hours, minutes, seconds)
        }
        return String(format: "%02lld:%02lld", minutes, seconds)
    }

    private func scheduleNextUpdate() {
        cancelTimer()
        guard islandEnabled, isPomodoroActive, !isPaused else { return }
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        refreshDisplay()
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !($0 is MacIslandPanel) })?.makeKeyAndOrderFront(nil)
    }

    private func int64Value(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        return 0
    }
}
