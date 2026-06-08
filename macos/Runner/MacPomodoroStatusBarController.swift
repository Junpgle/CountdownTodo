import Cocoa
import FlutterMacOS

class MacPomodoroStatusBarController {
    static let shared = MacPomodoroStatusBarController()

    private var statusItem: NSStatusItem?
    private var timer: Timer?

    private var phase: String = "idle"
    private var targetEndMs: Int64 = 0
    private var sessionStartMs: Int64 = 0
    private var mode: String = "countdown"
    private var isPaused: Bool = false
    private var pausedAtMs: Int64 = 0
    private var accumulatedMs: Int64 = 0
    private var pauseStartMs: Int64 = 0
    private var todoTitle: String = ""

    private init() {}

    // MARK: - Public

    func setup() {
        // 不预创建，专注时才创建
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

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshDisplay()
            self.scheduleNextUpdate()
        }
    }

    func clearPomodoroStatus() {
        phase = "idle"
        targetEndMs = 0
        sessionStartMs = 0
        mode = "countdown"
        isPaused = false
        pausedAtMs = 0
        accumulatedMs = 0
        pauseStartMs = 0
        todoTitle = ""

        DispatchQueue.main.async { [weak self] in
            self?.cancelTimer()
            self?.removeStatusItem()
        }
    }

    // MARK: - Private

    private func showStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            setupMenu()
        }
        statusItem?.isVisible = true
    }

    private func removeStatusItem() {
        if let item = statusItem {
            item.isVisible = false
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupMenu() {
        guard let button = statusItem?.button else { return }
        button.title = ""

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let openFocusItem = NSMenuItem(title: "打开专注页", action: #selector(openFocusPage), keyEquivalent: "")
        openFocusItem.target = self
        menu.addItem(openFocusItem)

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "暂停", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let stopItem = NSMenuItem(title: "结束专注", action: #selector(stopFocus), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 CountDownTodo", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func refreshDisplay() {
        switch phase {
        case "focusing":
            showStatusItem()
            guard let button = statusItem?.button else { return }
            if isPaused {
                let minutes = calculatePausedMinutes()
                button.title = "⏸ \(minutes)分"
                button.toolTip = buildTooltip(status: "已暂停")
            } else if mode == "countdown" {
                let minutes = calculateCountdownMinutes()
                button.title = "🍅 \(minutes)分"
                button.toolTip = buildTooltip(status: "剩余 \(minutes) 分钟")
            } else {
                let minutes = calculateCountUpMinutes()
                button.title = "🍅 \(minutes)分"
                button.toolTip = buildTooltip(status: "已专注 \(minutes) 分钟")
            }
            updatePauseMenuTitle()

        case "breaking":
            showStatusItem()
            guard let button = statusItem?.button else { return }
            let minutes = calculateCountdownMinutes()
            button.title = "☕ \(minutes)分"
            button.toolTip = "休息中，剩余 \(minutes) 分钟"
            updatePauseMenuTitle()

        default:
            removeStatusItem()
            cancelTimer()
        }
    }

    private func buildTooltip(status: String) -> String {
        if todoTitle.isEmpty {
            return "正在专注，\(status)"
        }
        return "正在专注：\(todoTitle)，\(status)"
    }

    private func updatePauseMenuTitle() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items {
            if item.action == #selector(togglePause) {
                item.title = isPaused ? "继续" : "暂停"
                break
            }
        }
    }

    private func calculateCountdownMinutes() -> Int {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let remainingMs = targetEndMs - now
        guard remainingMs > 0 else { return 0 }
        let minutes = Int(ceil(Double(remainingMs) / 60000.0))
        return max(minutes, 1)
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
            return Int(ceil(Double(remainingMs) / 60000.0))
        } else {
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
            guard remainingMs > 0 else {
                refreshDisplay()
                return
            }
            let currentMinutes = Int(ceil(Double(remainingMs) / 60000.0))
            let nextMinuteBoundary = Double(currentMinutes - 1) * 60000.0
            let msUntilNextMinute = remainingMs - Int64(nextMinuteBoundary)
            nextUpdateMs = max(msUntilNextMinute + 500, 1000)
        } else {
            let elapsedMs = now - sessionStartMs - accumulatedMs
            let currentMinutes = Int(floor(Double(elapsedMs) / 60000.0))
            let nextMinuteBoundary = Double(currentMinutes + 1) * 60000.0
            let msUntilNextMinute = Int64(nextMinuteBoundary) - elapsedMs
            nextUpdateMs = max(msUntilNextMinute + 500, 1000)
        }

        let interval = Double(nextUpdateMs) / 1000.0
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: false)
        timer.tolerance = 5.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        refreshDisplay()
        scheduleNextUpdate()
    }

    // MARK: - Menu Actions

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func openFocusPage() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePause() {
        // TODO: Implement pause/resume via Flutter channel
    }

    @objc private func stopFocus() {
        // TODO: Implement stop focus via Flutter channel
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
