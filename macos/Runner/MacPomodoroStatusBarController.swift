
import Cocoa
import SwiftUI
import FlutterMacOS
import QuartzCore


private final class MacIslandHostingView: NSHostingView<AnyView> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }
    
    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

private final class MacIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class IslandStateModel: ObservableObject {
    @Published var phase: String = "idle"
    @Published var timeText: String = ""
    @Published var todoTitle: String = ""
    @Published var isPaused = false
    @Published var isRemote = false
    @Published var expanded = false
    @Published var detailed = false
    @Published var hasNotch = false
    @Published var topInset: CGFloat = 0
    @Published var focusCurrentCycle = 1
    @Published var focusTotalCycles = 1
    @Published var focusPlannedSeconds: Int64 = 0
    @Published var focusTargetEndMs: Int64 = 0
    @Published var focusSessionStartMs: Int64 = 0
    @Published var focusAccumulatedMs: Int64 = 0
    @Published var focusPauseStartMs: Int64 = 0
    @Published var focusPausedAtMs: Int64 = 0
    @Published var focusMode = "countdown"
    @Published var focusNote = ""
    @Published var focusTagNames: [String] = []
    @Published var focusTodoId = ""
    @Published var focusPlanBlockId = ""
    @Published var sourceDeviceName = ""
    @Published var reminderActive = false
    @Published var reminderTitle = ""
    @Published var reminderBody = ""
    @Published var reminderType = ""
    @Published var reminderQueueCount = 0
    @Published var activityActive = false
    @Published var activityKind = ""
    @Published var activityTitle = ""
    @Published var activityId = ""
    @Published var activitySubtitle = ""
    @Published var activityDetail = ""
    @Published var activityRelatedTodoId = ""
    @Published var activityGroupName = ""
    @Published var activityStartMs: Int64 = 0
    @Published var activityEndMs: Int64 = 0
    @Published var nextActivityId = ""
    @Published var nextActivityKind = ""
    @Published var nextActivityTitle = ""
    @Published var nextActivitySubtitle = ""
    @Published var nextActivityStartMs: Int64 = 0
    @Published var nextActivityEndMs: Int64 = 0
    @Published var reminderTimeText = ""
    @Published var reminderDetailText = ""
    @Published var reminderNextTitle = ""
    @Published var reminderNextTimeText = ""
    @Published var reminderEntityKind = ""
    @Published var reminderEntityId = ""
    @Published var overviewLoaded = false
    @Published var todayFocusBaseSeconds: Int64 = 0
    @Published var todayFocusBaseCount = 0
    @Published var includeCurrentFocus = false
    @Published var countdownTitle = ""
    @Published var countdownTargetMs: Int64 = 0
    @Published var countdownDays = -1

    var onExpansionChanged: ((Bool, Bool) -> Void)?
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenApp: (() -> Void)?
    var onOpenEntity: ((String, String) -> Void)?
    var onStartFocus: ((String, String) -> Void)?
    var onCompleteTodo: ((String) -> Void)?
    var onAcknowledgeReminder: (() -> Void)?
    var onSnoozeReminder: (() -> Void)?

    var isFocusActive: Bool {
        phase == "focusing" || phase == "breaking"
    }

    var focusCycleText: String {
        let cycle = max(1, focusCurrentCycle)
        let total = max(cycle, focusTotalCycles)
        return "第 \(cycle)/\(total) 轮"
    }

    var focusEndText: String {
        if focusMode == "countUp" || focusTargetEndMs <= 0 { return "正计时" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let date = Date(timeIntervalSince1970: Double(focusTargetEndMs) / 1000)
        return "\(formatter.string(from: date)) 结束"
    }

    var focusPausedText: String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let current = isPaused && focusPauseStartMs > 0 ? max(0, now - focusPauseStartMs) : 0
        let minutes = (focusAccumulatedMs + current) / 60_000
        if minutes <= 0 { return isPaused ? "已暂停" : "未暂停" }
        return "已暂停 \(minutes) 分钟"
    }

    var currentFocusElapsedSeconds: Int64 {
        guard includeCurrentFocus, phase == "focusing", focusSessionStartMs > 0 else { return 0 }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let frozenNow = isPaused
            ? max(focusSessionStartMs, max(focusPausedAtMs, focusPauseStartMs))
            : now
        return max(0, frozenNow - focusSessionStartMs - focusAccumulatedMs) / 1000
    }

    var todayFocusDisplayCount: Int {
        todayFocusBaseCount + (currentFocusElapsedSeconds > 0 ? 1 : 0)
    }

    var todayFocusDurationText: String {
        let totalMinutes = max(0, todayFocusBaseSeconds + currentFocusElapsedSeconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours <= 0 { return "\(minutes) 分钟" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分"
    }

    var countdownRemainingText: String {
        if countdownDays < 0 { return "暂无" }
        if countdownDays == 0 { return "就在今天" }
        return "还有 \(countdownDays) 天"
    }

    var countdownDateText: String {
        guard countdownTargetMs > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: Date(timeIntervalSince1970: Double(countdownTargetMs) / 1000))
    }
}


struct BottomRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                    radius: cornerRadius,
                    startAngle: Angle(degrees: 90),
                    endAngle: Angle(degrees: 180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        
        return path
    }
}

struct MacIslandSwiftUIView: View {
    @ObservedObject var model: IslandStateModel
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .clipShape(BottomRoundedRectangle(cornerRadius: model.expanded ? 22 : 18))
                .edgesIgnoringSafeArea(.all)
            
            if model.hasNotch {
                Color.black
                    .frame(height: max(model.topInset, 28))
                    .edgesIgnoringSafeArea(.top)
            }
            
            VStack(spacing: 0) {
                if model.hasNotch {
                    Spacer().frame(height: max(model.topInset, 28))
                } else {
                    Spacer().frame(height: 6)
                }
                
                Group {
                    if model.expanded {
                        if model.isFocusActive {
                            expandedFocusView
                            if model.reminderActive {
                                Spacer().frame(height: 12)
                                reminderCard
                            } else if model.activityActive {
                                Spacer().frame(height: 12)
                                activityCard
                            }
                        } else if model.reminderActive {
                            expandedReminderView
                        } else {
                            expandedActivityView
                        }
                        
                        if model.detailed {
                            Spacer().frame(height: 20)
                            overviewCards
                        }
                    } else {
                        if model.isFocusActive {
                            compactFocusView
                        } else {
                            compactActivityView
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 8)
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if model.expanded {
                    if model.detailed {
                        model.detailed = false
                        model.onExpansionChanged?(true, false)
                    } else {
                        model.detailed = true
                        model.onExpansionChanged?(true, true)
                    }
                } else {
                    model.expanded = true
                    model.detailed = false
                    model.onExpansionChanged?(true, false)
                }
            }
        }
        .colorScheme(.dark)
    }
    
    
    var overviewCards: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("今日专注")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("\(model.todayFocusDisplayCount) 次")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(height: 14)
                
                Text(model.todayFocusDurationText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                    .frame(height: 18)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.countdownTitle.isEmpty ? "倒数日" : model.countdownTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                    Spacer()
                    Text(model.countdownDateText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(height: 14)
                
                Text(model.countdownRemainingText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.purple)
                    .frame(height: 18)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
        }
        .frame(height: 68)
    }

    var compactFocusView: some View {
        HStack {
            let color = model.phase == "breaking" ? Color.blue : Color.purple
            Image(systemName: model.phase == "breaking" ? "cup.and.saucer.fill" : "hourglass.tophalf.filled")
                .foregroundColor(color)
                .font(.system(size: 12))
                .frame(width: 16, alignment: .center)
            
            Text(model.timeText)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
            
            Spacer()
        }
        .frame(height: 24)
    }
    
    var compactActivityView: some View {
        HStack {
            Image(systemName: "checklist")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            
            Text(model.activityTitle.isEmpty ? "CountDownTodo" : model.activityTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
        }
        .frame(height: 24)
    }
    
    var expandedFocusView: some View {
        VStack(spacing: 0) {
            HStack {
                let color = model.phase == "breaking" ? Color.blue : Color.purple
                let title = model.phase == "breaking" ? "休息时间" : (model.isRemote ? "其他设备正在专注" : "正在专注")
                Image(systemName: model.phase == "breaking" ? "cup.and.saucer.fill" : "hourglass.tophalf.filled")
                    .foregroundColor(color)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(model.focusCycleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(height: 20)
            
            Text(model.timeText)
                .font(.system(size: 42, weight: .bold).monospacedDigit())
                .foregroundColor(.white)
                .frame(height: 50)
                .padding(.top, 10)
            
            let titleStr = model.todoTitle.isEmpty ? (model.focusTagNames.first ?? "专注中") : model.todoTitle
            Text(titleStr)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(height: 20)
                .padding(.top, 8)
            
            let device = model.sourceDeviceName.isEmpty ? (model.isRemote ? "其他设备" : "本机") : model.sourceDeviceName
            let focusMeta = "\(device)  ·  \(model.focusEndText)  ·  \(model.focusPausedText)"
            Text(focusMeta)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .frame(height: 16)
                .padding(.top, 4)
                
            progressView
                .padding(.top, 16)
                .padding(.bottom, 16)
            
            if model.detailed {
                if !model.focusTagNames.isEmpty {
                    HStack {
                        ForEach(model.focusTagNames, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.purple)
                        }
                    }
                    .frame(height: 16)
                    .padding(.bottom, 16)
                }
                
                if !model.focusNote.isEmpty {
                    Text(model.focusNote)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                        .padding(.bottom, 16)
                }
            }
            
            HStack(spacing: 12) {
                if !model.isRemote {
                    Button(action: { model.onTogglePause?() }) {
                        Text(model.isPaused ? "继续" : "暂停")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    
                    Button(action: { model.onStop?() }) {
                        Text("结束")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 38)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
                } else {
                    Button(action: { model.onOpenApp?() }) {
                        Text("打开应用")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                }
            }
            .frame(height: 38)
        }
    }
    

    var progressView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.12))
                
                let accent = model.phase == "breaking" ? Color.blue : Color.purple
                if model.focusPlannedSeconds <= 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent.opacity(0.7))
                        .frame(width: geometry.size.width * 0.32)
                } else {
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    let duration = max(1, Double(model.focusPlannedSeconds) * 1000)
                    let progress: Double = {
                        if model.focusSessionStartMs <= 0 {
                            let remaining = max(0, Double(model.focusTargetEndMs - now))
                            return max(0, duration - remaining) / duration
                        } else {
                            let frozenNow = model.isPaused ? max(model.focusPausedAtMs, model.focusPauseStartMs) : now
                            let currentPause = model.isPaused && model.focusPauseStartMs > 0 ? max(0, frozenNow - model.focusPauseStartMs) : 0
                            let elapsed = max(0, Double(frozenNow - model.focusSessionStartMs - model.focusAccumulatedMs - currentPause))
                            return min(duration, elapsed) / duration
                        }
                    }()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: geometry.size.width * CGFloat(progress))
                }
            }
        }
        .frame(height: 6)
    }

    var expandedActivityView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.orange)
                Text(model.activityTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            
            HStack(spacing: 12) {
                Button(action: { model.onOpenApp?() }) {
                    Text("打开应用")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }
    
    var expandedReminderView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.orange)
                Text(model.reminderTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            
            Text(model.reminderBody)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button(action: { model.onSnoozeReminder?() }) {
                    Text("稍后")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button(action: { model.onAcknowledgeReminder?() }) {
                    Text("好的")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
    }
    
    var reminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.fill").foregroundColor(.orange)
                Text(model.reminderTitle).font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    var activityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist").foregroundColor(.blue)
                Text(model.activityTitle).font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

/// macOS 刘海灵动岛控制器。
///
/// 保留原类名以兼容现有 Flutter MethodChannel，展示层不再创建 NSStatusItem。
class MacPomodoroStatusBarController {
    static let shared = MacPomodoroStatusBarController()

    private var islandWindow: MacIslandPanel?
    private var islandModel: IslandStateModel?
    private var timer: Timer?
    private var appChannel: FlutterMethodChannel?
    private var flutterChannel: FlutterMethodChannel?
    private var observers: [NSObjectProtocol] = []

    private var islandEnabled = true
    private var showOnNotchlessDisplay = true
    private var remindersEnabled = true
    private var isExpanded = false
    private var isPinnedExpanded = false
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
    private var focusCurrentCycle = 1
    private var focusTotalCycles = 1
    private var focusPlannedSeconds: Int64 = 0
    private var focusTagNames: [String] = []
    private var focusNote = ""
    private var focusTodoId = ""
    private var focusPlanBlockId = ""
    private var sourceDeviceName = ""
    private var isRemote = false
    private var activityId = ""
    private var activityKind = ""
    private var activityTitle = ""
    private var activitySubtitle = ""
    private var activityDetail = ""
    private var activityRelatedTodoId = ""
    private var activityGroupName = ""
    private var activityStartMs: Int64 = 0
    private var activityEndMs: Int64 = 0
    private var nextActivityId = ""
    private var nextActivityKind = ""
    private var nextActivityTitle = ""
    private var nextActivitySubtitle = ""
    private var nextActivityStartMs: Int64 = 0
    private var nextActivityEndMs: Int64 = 0
    private var overviewLoaded = false
    private var todayFocusBaseSeconds: Int64 = 0
    private var todayFocusBaseCount = 0
    private var includeCurrentFocus = false
    private var countdownTitle = ""
    private var countdownTargetMs: Int64 = 0
    private var countdownDays = -1

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
            self.scheduleNextUpdate()
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
        focusCurrentCycle = Int(int64Value(args["currentCycle"]))
        focusTotalCycles = Int(int64Value(args["totalCycles"]))
        focusPlannedSeconds = int64Value(args["plannedFocusSeconds"])
        focusTagNames = (args["tagNames"] as? [Any])?.map { String(describing: $0) } ?? []
        focusNote = args["note"] as? String ?? ""
        focusTodoId = args["todoId"] as? String ?? ""
        focusPlanBlockId = args["planBlockId"] as? String ?? ""
        sourceDeviceName = args["sourceDeviceName"] as? String ?? ""
        isRemote = args["isRemote"] as? Bool ?? false

        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplay()
            self?.scheduleNextUpdate()
        }
    }

    func clearPomodoroStatus() {
        phase = "idle"
        isRemote = false
        focusCurrentCycle = 1
        focusTotalCycles = 1
        focusPlannedSeconds = 0
        focusTagNames = []
        focusNote = ""
        focusTodoId = ""
        focusPlanBlockId = ""
        sourceDeviceName = ""
        DispatchQueue.main.async { [weak self] in
            self?.cancelTimer()
            self?.refreshDisplay()
            self?.scheduleNextUpdate()
        }
    }

    func updateOngoingActivity(args: [String: Any]) {
        activityId = args["id"] as? String ?? ""
        activityKind = args["kind"] as? String ?? "todo"
        activityTitle = args["title"] as? String ?? ""
        activitySubtitle = args["subtitle"] as? String ?? ""
        activityDetail = args["detail"] as? String ?? ""
        activityRelatedTodoId = args["relatedTodoId"] as? String ?? ""
        activityGroupName = args["groupName"] as? String ?? ""
        activityStartMs = int64Value(args["startMs"])
        activityEndMs = int64Value(args["endMs"])
        let next = args["nextActivity"] as? [String: Any]
        nextActivityId = next?["id"] as? String ?? ""
        nextActivityKind = next?["kind"] as? String ?? ""
        nextActivityTitle = next?["title"] as? String ?? ""
        nextActivitySubtitle = next?["subtitle"] as? String ?? ""
        nextActivityStartMs = int64Value(next?["startMs"])
        nextActivityEndMs = int64Value(next?["endMs"])
        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplay()
            self?.scheduleNextUpdate()
        }
    }

    func clearOngoingActivity() {
        activityId = ""
        activityKind = ""
        activityTitle = ""
        activitySubtitle = ""
        activityDetail = ""
        activityRelatedTodoId = ""
        activityGroupName = ""
        activityStartMs = 0
        activityEndMs = 0
        nextActivityId = ""
        nextActivityKind = ""
        nextActivityTitle = ""
        nextActivitySubtitle = ""
        nextActivityStartMs = 0
        nextActivityEndMs = 0
        DispatchQueue.main.async { [weak self] in
            self?.refreshDisplay()
            self?.scheduleNextUpdate()
        }
    }

    func updateIslandOverview(args: [String: Any]) {
        overviewLoaded = true
        todayFocusBaseSeconds = int64Value(args["todayFocusBaseSeconds"])
        todayFocusBaseCount = Int(int64Value(args["todayFocusBaseCount"]))
        includeCurrentFocus = args["includeCurrentFocus"] as? Bool ?? false
        countdownTitle = args["countdownTitle"] as? String ?? ""
        countdownTargetMs = int64Value(args["countdownTargetMs"])
        countdownDays = Int(int64Value(args["countdownDays"]))
        DispatchQueue.main.async { [weak self] in
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
            self.isPinnedExpanded = false
            self.flutterChannel?.invokeMethod("requestIslandOverview", arguments: nil)
            self.refreshDisplay()
            self.scheduleNextUpdate()
        }
    }

    func clearIslandReminders() {
        currentReminder = nil
        reminderQueue.removeAll()
        reminderIds.removeAll()
        isExpanded = false
        isPinnedExpanded = false
        refreshDisplay()
    }

    private var isPomodoroActive: Bool {
        phase == "focusing" || phase == "breaking"
    }



    private var isOngoingActivityActive: Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return !activityTitle.isEmpty && activityStartMs <= now && now < activityEndMs
    }

    private func refreshDisplay() {
        expireStartedReminders()
        let hasReminder = remindersEnabled && currentReminder != nil
        let hasActivity = isOngoingActivityActive
        guard islandEnabled, isPomodoroActive || hasReminder || hasActivity else {
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

        let view = ensureIslandModel()
        view.phase = phase
        view.timeText = calculateTimeText()
        view.todoTitle = todoTitle
        view.isPaused = isPaused
        view.isRemote = isRemote
        view.expanded = hasReminder || isExpanded
        view.detailed = hasReminder || isPinnedExpanded
        view.hasNotch = geometry.hasNotch
        view.topInset = geometry.topInset
        view.focusCurrentCycle = max(1, focusCurrentCycle)
        view.focusTotalCycles = max(1, focusTotalCycles)
        view.focusPlannedSeconds = focusPlannedSeconds
        view.focusTargetEndMs = targetEndMs
        view.focusSessionStartMs = sessionStartMs
        view.focusAccumulatedMs = accumulatedMs
        view.focusPauseStartMs = pauseStartMs
        view.focusPausedAtMs = pausedAtMs
        view.focusMode = mode
        view.focusNote = focusNote
        view.focusTagNames = focusTagNames
        view.focusTodoId = focusTodoId
        view.focusPlanBlockId = focusPlanBlockId
        view.sourceDeviceName = sourceDeviceName
        view.reminderActive = hasReminder
        view.reminderTitle = currentReminder?["title"] as? String ?? ""
        view.reminderBody = currentReminder?["text"] as? String ?? ""
        view.reminderType = currentReminder?["type"] as? String ?? ""
        view.reminderQueueCount = reminderQueue.count
        view.reminderTimeText = reminderTimeText(currentReminder)
        view.reminderDetailText = reminderDetailText(currentReminder)
        view.reminderNextTitle = reminderQueue.first?["title"] as? String ?? ""
        view.reminderNextTimeText = reminderQueue.first?["timeStr"] as? String ?? ""
        let reminderEntity = reminderEntity(currentReminder)
        view.reminderEntityKind = reminderEntity.kind
        view.reminderEntityId = reminderEntity.id
        view.activityActive = hasActivity
        view.activityId = activityId
        view.activityKind = activityKind
        view.activityTitle = activityTitle
        view.activitySubtitle = activitySubtitle
        view.activityDetail = activityDetail
        view.activityRelatedTodoId = activityRelatedTodoId
        view.activityGroupName = activityGroupName
        view.activityStartMs = activityStartMs
        view.activityEndMs = activityEndMs
        view.nextActivityId = nextActivityId
        view.nextActivityKind = nextActivityKind
        view.nextActivityTitle = nextActivityTitle
        view.nextActivitySubtitle = nextActivitySubtitle
        view.nextActivityStartMs = nextActivityStartMs
        view.nextActivityEndMs = nextActivityEndMs
        view.overviewLoaded = overviewLoaded
        view.todayFocusBaseSeconds = todayFocusBaseSeconds
        view.todayFocusBaseCount = todayFocusBaseCount
        view.includeCurrentFocus = includeCurrentFocus
        view.countdownTitle = countdownTitle
        view.countdownTargetMs = countdownTargetMs
        view.countdownDays = countdownDays
        // SwiftUI handles accessibility
        // SwiftUI handles accessibility
        // view.setAccessibilityLabel("CountDownTodo 灵动岛")
        if isPomodoroActive {
            let activityValue = hasActivity ? "，同时进行：\(activityTitle)" : ""
            let reminderValue = hasReminder ? "，提醒：\(view.reminderTitle)" : ""
            // view.setAccessibilityValue("\(phase == "breaking" ? "休息" : "专注")，\(view.timeText)\(reminderValue)\(activityValue)")
        } else if hasReminder {
            // view.setAccessibilityValue("提醒：\(view.reminderTitle)，\(view.reminderBody)")
        } else {
            // view.setAccessibilityValue("\(view.activityCategory)，\(activityTitle)，\(view.activityRemainingText)")
        }

        let activityCompactWidth: CGFloat = hasActivity || isPomodoroActive ? 238 : 196
        let compactWidth = geometry.hasNotch ? max(activityCompactWidth, geometry.notchWidth + 24) : activityCompactWidth
        let compactHeight: CGFloat = geometry.hasNotch ? max(54, geometry.topInset + 25) : 43
        let expanded = hasReminder || isExpanded
        let detailed = hasReminder || isPinnedExpanded
        let focusWithActivity = isPomodoroActive && hasActivity
        let focusWithReminder = isPomodoroActive && hasReminder
        let width = expanded
            ? max(detailed ? 360 : (focusWithReminder ? 340 : (hasActivity ? 330 : 320)), compactWidth)
            : compactWidth
        let height: CGFloat
        let widthStr: CGFloat = width
        
        let hasNotch = geometry.hasNotch
        let topInset = hasNotch ? max(geometry.topInset, 28) : 6
        
        if !expanded {
            height = topInset + 4 + 18 + 8
        } else if detailed {
            let topPadding: CGFloat = 8
            let bottomPadding: CGFloat = 16
            
            var contentHeight: CGFloat = 0
            if isPomodoroActive {
                // TopBar(20) + Time(50+10) + Title(20+8) + Meta(16+4) + Progress(6+32) + Buttons(38) = 204
                let baseFocus: CGFloat = 204
                let tagsHeight: CGFloat = view.focusTagNames.isEmpty ? 0 : 32
                // Note has 13+24+16=53 height
                let noteHeight: CGFloat = view.focusNote.isEmpty ? 0 : 53
                
                contentHeight += baseFocus + tagsHeight + noteHeight
                
                if hasReminder && !view.reminderTitle.isEmpty {
                    contentHeight += 12 + 62
                } else if hasActivity && !view.nextActivityTitle.isEmpty {
                    contentHeight += 12 + 62
                }
            } else if hasReminder {
                contentHeight += 80
            } else {
                contentHeight += 80
            }
            
            // Overview Cards (16 + 68)
            contentHeight += 16 + 68
            
            height = topInset + topPadding + contentHeight + bottomPadding
        } else {
            let topPadding: CGFloat = 8
            let bottomPadding: CGFloat = 16
            
            var contentHeight: CGFloat = 0
            if isPomodoroActive {
                let baseFocus: CGFloat = 204
                contentHeight += baseFocus
                
                if hasReminder && !view.reminderTitle.isEmpty {
                    contentHeight += 12 + 62
                } else if hasActivity && !view.nextActivityTitle.isEmpty {
                    contentHeight += 12 + 62
                }
            } else {
                contentHeight += 80
            }
            
            height = topInset + topPadding + contentHeight + bottomPadding
        }
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
        let shouldAnimateFirstExpansion = !window.isVisible && expanded && !reduceMotion
        if shouldAnimateFirstExpansion {
            let compactFrame = NSRect(
                x: screen.frame.midX - compactWidth / 2,
                y: screen.frame.maxY - compactHeight,
                width: compactWidth,
                height: compactHeight
            )
            window.setFrame(compactFrame, display: true)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else if shouldAnimate && !NSEqualRects(window.frame, frame) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.26 : 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        lastScreenNumber = screenNumber
        // ObservableObject triggers UI update
        window.orderFrontRegardless()
    }

    private func ensureIslandModel() -> IslandStateModel {
        if let islandModel = islandModel { return islandModel }
        let view = IslandStateModel()
        view.onExpansionChanged = { [weak self] expanded, detailed in
            guard let self = self else { return }
            self.isExpanded = expanded
            self.isPinnedExpanded = detailed
            if detailed {
                self.flutterChannel?.invokeMethod("requestIslandOverview", arguments: nil)
            }
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
        view.onOpenEntity = { [weak self] kind, id in
            self?.sendIslandCommand("openIslandEntity", kind: kind, id: id)
        }
        view.onStartFocus = { [weak self] kind, id in
            self?.sendIslandCommand("startIslandActivityFocus", kind: kind, id: id)
        }
        view.onCompleteTodo = { [weak self] id in
            self?.sendIslandCommand("completeIslandTodo", kind: "todo", id: id)
        }
        view.onAcknowledgeReminder = { [weak self] in
            self?.handleCurrentReminder(snoozeMinutes: nil)
        }
        view.onSnoozeReminder = { [weak self] in
            self?.handleCurrentReminder(snoozeMinutes: 10)
        }
        islandModel = view
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

        currentReminder = reminderQueue.isEmpty ? nil : reminderQueue.removeFirst()
        isExpanded = currentReminder != nil
        if currentReminder == nil {
            isPinnedExpanded = false
        }
        refreshDisplay()
        if currentReminder == nil, (isPomodoroActive && !isPaused) || isOngoingActivityActive {
            scheduleNextUpdate()
        }
    }

    private func reminderIdentifier(_ reminder: [String: Any]) -> String {
        let trigger = String(describing: reminder["triggerAtMs"] ?? "")
        if let number = reminder["notifId"] as? NSNumber {
            return "\(number.stringValue)@\(trigger)"
        }
        if let value = reminder["notifId"] {
            return "\(String(describing: value))@\(trigger)"
        }
        return "\(reminder["title"] ?? "")@\(trigger)"
    }

    private func sendIslandCommand(_ method: String, kind: String, id: String) {
        guard !kind.isEmpty, !id.isEmpty else {
            showMainWindow()
            return
        }
        showMainWindow()
        flutterChannel?.invokeMethod(method, arguments: [
            "kind": kind,
            "id": id,
        ])
    }

    private func reminderEntity(_ reminder: [String: Any]?) -> (kind: String, id: String) {
        guard let reminder = reminder else { return ("", "") }
        let type = reminder["type"] as? String ?? ""
        if type == "course" {
            return ("course", reminder["courseId"] as? String ?? "")
        }
        if type == "plan_block" {
            return ("plan_block", reminder["planBlockId"] as? String ?? "")
        }
        return ("todo", reminder["todoId"] as? String ?? "")
    }

    private func reminderTimeText(_ reminder: [String: Any]?) -> String {
        guard let reminder = reminder else { return "" }
        let startMs = int64Value(reminder["startAtMs"] ?? reminder["courseStartMs"])
        let timeRange = reminder["timeStr"] as? String ?? ""
        guard startMs > 0 else { return timeRange }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let minutes = max(0, (startMs - now + 59_999) / 60_000)
        let countdown = minutes <= 1 ? "马上开始" : "\(minutes) 分钟后开始"
        return timeRange.isEmpty ? countdown : "\(countdown) · \(timeRange)"
    }

    private func reminderDetailText(_ reminder: [String: Any]?) -> String {
        guard let reminder = reminder else { return "" }
        let details = [
            reminder["room"] as? String ?? "",
            reminder["teacher"] as? String ?? "",
            reminder["courseName"] as? String ?? "",
        ].filter { !$0.isEmpty }
        return details.joined(separator: " · ")
    }

    private func expireStartedReminders() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        func hasStarted(_ reminder: [String: Any]) -> Bool {
            let startAt = int64Value(reminder["startAtMs"] ?? reminder["courseStartMs"])
            return startAt > 0 && now >= startAt
        }

        var expiredCurrentReminder = false
        if let current = currentReminder, hasStarted(current) {
            currentReminder = nil
            expiredCurrentReminder = true
        }
        reminderQueue.removeAll(where: hasStarted)
        if currentReminder == nil, !reminderQueue.isEmpty {
            currentReminder = reminderQueue.removeFirst()
        }
        // 没有提醒本身不是收起条件，否则鼠标移入设置的展开状态会在
        // refreshDisplay() 开头被立即清空，看起来就像悬停事件没有触发。
        if expiredCurrentReminder && currentReminder == nil {
            isExpanded = false
            isPinnedExpanded = false
        }
    }

    private func ensureIslandWindow(frame: NSRect, view: IslandStateModel) -> MacIslandPanel {
        if let islandWindow = islandWindow { return islandWindow }

        let window = MacIslandPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.hasShadow = true
        window.backgroundColor = .clear
        window.title = "CountDownTodo 灵动岛"
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
        
        
                let rootView = AnyView(MacIslandSwiftUIView(model: view))
        let hostingView = MacIslandHostingView(rootView: rootView)
        hostingView.onMouseEntered = { [weak view] in
            guard let view = view, !view.expanded else { return }
            view.expanded = true
            view.onExpansionChanged?(true, view.detailed)
        }
        hostingView.onMouseExited = { [weak view] in
            guard let view = view else { return }
            if !view.detailed && view.expanded && !view.reminderActive {
                view.expanded = false
                view.onExpansionChanged?(false, false)
            }
        }
        window.contentView = hostingView
        islandWindow = window
        return window
    }

    private func hideIsland() {
        isExpanded = false
        isPinnedExpanded = false
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
            if topInset > 0 {
                // safeAreaInsets.top 才是刘海是否存在的可靠信号。部分系统状态下
                // auxiliaryTopLeft/RightArea 会暂时返回 nil，不能因此把刘海屏误判
                // 成普通屏幕，否则提醒正文只会预留 6pt 并被刘海遮挡。
                if let left = screen.auxiliaryTopLeftArea,
                   let right = screen.auxiliaryTopRightArea {
                    return (true, topInset, max(0, right.minX - left.maxX))
                }
                return (true, topInset, 180)
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
        guard islandEnabled,
              (isPomodoroActive && !isPaused) ||
              isOngoingActivityActive ||
              (remindersEnabled && currentReminder != nil) else { return }
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
