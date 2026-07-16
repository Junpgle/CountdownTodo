
import Cocoa
import SwiftUI
import FlutterMacOS
import QuartzCore
import Carbon


private let islandVisibilityHotKeySignature: OSType = 0x43445449 // "CDTI"
private let islandVisibilityHotKeyID: UInt32 = 1
private let islandExpansionAnimation = Animation.spring(
    response: 0.50,
    dampingFraction: 0.90,
    blendDuration: 0.12
)
private let islandCollapseAnimation = Animation.spring(
    response: 0.36,
    dampingFraction: 0.94,
    blendDuration: 0.08
)
private let islandExpansionDuration: TimeInterval = 0.50
private let islandCollapseDuration: TimeInterval = 0.36

private func islandVisibilityHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event, let userData = userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == islandVisibilityHotKeySignature,
          hotKeyID.id == islandVisibilityHotKeyID else {
        return OSStatus(eventNotHandledErr)
    }

    let controller = Unmanaged<MacPomodoroStatusBarController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    controller.toggleIslandVisibilityFromHotKey()
    return noErr
}


private final class MacIslandHostingView: NSHostingView<AnyView> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        // 窗口高度动画时不要缩放一张旧的居中快照，否则顶部会短暂
        // 离开菜单栏。逐帧重绘可以让新增高度只向下显露。
        self.layerContentsRedrawPolicy = .duringViewResize
    }

    // 灵动岛本身已经按真实刘海高度预留了 topInset。NSHostingView 再
    // 注入系统安全区会造成展开途中出现第二段顶部空隙。
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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
    @Published var notchWidth: CGFloat = 0
    @Published var isIdle = true
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
    @Published var clipboardLinkActive = false
    @Published var clipboardLinkDisplay = ""
    @Published var revealHeight: CGFloat = 0

    var onExpansionChanged: ((Bool, Bool) -> Void)?
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenApp: (() -> Void)?
    var onOpenEntity: ((String, String) -> Void)?
    var onStartFocus: ((String, String) -> Void)?
    var onCompleteTodo: ((String) -> Void)?
    var onAcknowledgeReminder: (() -> Void)?
    var onSnoozeReminder: (() -> Void)?
    var onOpenClipboardLink: (() -> Void)?
    var onDismissClipboardLink: (() -> Void)?

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
    @Namespace private var focusTimerNamespace
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .frame(maxWidth: .infinity)
                .frame(height: max(0, model.revealHeight))
                .clipShape(BottomRoundedRectangle(cornerRadius: model.expanded ? 22 : 18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .edgesIgnoringSafeArea(.all)
                // 黑色底板必须跟随宿主窗口逐帧立即铺满。若继承 expanded
                // 的弹簧事务，它会以自身中心插值尺寸，出现从中间向上下
                // 生长、刘海连接处短暂缺块的问题。
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            
            if model.hasNotch {
                Color.black
                    .frame(maxWidth: .infinity)
                    .frame(height: max(model.topInset, 28))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .edgesIgnoringSafeArea(.all)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
            }

            Group {
                if model.hasNotch && !model.expanded {
                    if !model.isIdle {
                        compactNotchView
                            .frame(height: max(model.topInset, 28))
                            .padding(.horizontal, 8)
                    }
                } else {
                    VStack(spacing: 0) {
                        if model.hasNotch {
                            Color.clear.frame(height: max(model.topInset, 28))
                        } else {
                            Color.clear.frame(height: 6)
                        }

                        VStack(spacing: 0) {
                            if model.expanded {
                                if model.isFocusActive {
                                    expandedFocusView
                                    if model.reminderActive {
                                        reminderCard.padding(.top, 12)
                                    } else if model.clipboardLinkActive {
                                        clipboardLinkCard.padding(.top, 12)
                                    } else if model.activityActive {
                                        activityCard.padding(.top, 12)
                                    }
                                } else if model.reminderActive {
                                    expandedReminderView
                                } else if model.clipboardLinkActive {
                                    expandedClipboardLinkView
                                } else {
                                    expandedActivityView
                                }

                                if model.detailed {
                                    overviewCards.padding(.top, 20)
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
            }
            // 只裁切移动中的文字/按钮，黑色底板和刘海顶部连接层不参与
            // 遮罩，避免展开过程中屏幕顶部再次出现透明缺口。
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                        .frame(height: max(0, model.revealHeight))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .onTapGesture {
            let animation = model.expanded && model.detailed
                ? islandCollapseAnimation
                : islandExpansionAnimation
            withAnimation(animation) {
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
    
    var compactNotchView: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: model.isFocusActive
                      ? (model.phase == "breaking" ? "cup.and.saucer.fill" : "hourglass.tophalf.filled")
                      : "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(model.phase == "breaking" ? .blue : .orange)

                VStack(alignment: .leading, spacing: 1) {
                    if model.isFocusActive {
                        Text(compactContextTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .matchedGeometryEffect(
                                id: "focusEventTitle",
                                in: focusTimerNamespace,
                                properties: .position,
                                anchor: .center
                            )
                            .zIndex(9)
                    } else {
                        Text(compactContextTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    if model.isFocusActive && !focusTagSummary.isEmpty {
                        Text(focusTagSummary)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                            .matchedGeometryEffect(
                                id: "focusTags",
                                in: focusTimerNamespace,
                                properties: .position,
                                anchor: .center
                            )
                            .zIndex(8)
                    } else {
                        Text(compactContextDetail)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(model.isFocusActive ? .purple : .white.opacity(0.48))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: max(model.notchWidth, 160))

            VStack(alignment: .trailing, spacing: 1) {
                if model.isFocusActive {
                    Text(model.timeText)
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .fixedSize(horizontal: true, vertical: true)
                        .matchedGeometryEffect(
                            id: "focusTimer",
                            in: focusTimerNamespace,
                            properties: .position,
                            anchor: .center
                        )
                        .zIndex(10)
                } else {
                    Text("进行中")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(compactStatusText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var compactContextTitle: String {
        if model.isFocusActive {
            return model.todoTitle.isEmpty ? "自由专注" : model.todoTitle
        }
        return model.activityTitle.isEmpty ? "CountDownTodo" : model.activityTitle
    }

    private var compactContextDetail: String {
        if model.isFocusActive {
            return focusTagSummary.isEmpty
                ? (model.phase == "breaking" ? "休息阶段" : "未设置标签")
                : focusTagSummary
        }
        if !model.activityGroupName.isEmpty { return model.activityGroupName }
        if !model.activitySubtitle.isEmpty { return model.activitySubtitle }
        return "当前事项"
    }

    private var focusTagSummary: String {
        model.focusTagNames.prefix(2).joined(separator: " · ")
    }

    private var compactStatusText: String {
        if model.isPaused { return "已暂停" }
        if model.phase == "breaking" { return "休息中" }
        if model.isRemote { return "其他设备" }
        return model.isFocusActive ? "专注中" : "正在发生"
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
        HStack(spacing: 8) {
            let color = model.phase == "breaking" ? Color.blue : Color.purple
            Image(systemName: model.phase == "breaking" ? "cup.and.saucer.fill" : "hourglass.tophalf.filled")
                .foregroundColor(color)
                .font(.system(size: 12))
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(compactContextTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .matchedGeometryEffect(
                        id: "focusEventTitle",
                        in: focusTimerNamespace,
                        properties: .position,
                        anchor: .center
                    )
                    .zIndex(9)
                if !focusTagSummary.isEmpty {
                    Text(focusTagSummary)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(color.opacity(0.85))
                        .lineLimit(1)
                        .matchedGeometryEffect(
                            id: "focusTags",
                            in: focusTimerNamespace,
                            properties: .position,
                            anchor: .center
                        )
                        .zIndex(8)
                } else {
                    Text(compactContextDetail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(color.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(model.timeText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .fixedSize(horizontal: true, vertical: true)
                    .matchedGeometryEffect(
                        id: "focusTimer",
                        in: focusTimerNamespace,
                        properties: .position,
                        anchor: .center
                    )
                    .zIndex(10)
                Text(compactStatusText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                }
        }
        .frame(height: 34)
    }
    
    var compactActivityView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundColor(.orange)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text(compactContextTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(compactContextDetail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            Text("进行中")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(height: 34)
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
                .fixedSize(horizontal: true, vertical: true)
                .matchedGeometryEffect(
                    id: "focusTimer",
                    in: focusTimerNamespace,
                    properties: .position,
                    anchor: .center
                )
                .zIndex(10)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .padding(.top, 10)
            
            // 与收起态保持完全相同的内容，matched geometry 才不会在滑动中交叉换字。
            let titleStr = compactContextTitle
            Text(titleStr)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .matchedGeometryEffect(
                    id: "focusEventTitle",
                    in: focusTimerNamespace,
                    properties: .position,
                    anchor: .center
                )
                .zIndex(9)
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
            
            if !focusTagSummary.isEmpty {
                HStack(spacing: 8) {
                    Text(focusTagSummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.purple)
                        .lineLimit(1)
                        .matchedGeometryEffect(
                            id: "focusTags",
                            in: focusTimerNamespace,
                            properties: .position,
                            anchor: .center
                        )
                        .zIndex(8)

                    if model.focusTagNames.count > 2 {
                        Text(model.focusTagNames.dropFirst(2).joined(separator: " · "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    }
                }
                    .frame(height: 16)
                    .padding(.bottom, 16)
            }

            if model.detailed {
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
                Image(systemName: model.isIdle ? "checkmark.circle.fill" : "checklist")
                    .foregroundColor(model.isIdle ? .green : .orange)
                Text(model.isIdle ? "当前暂无进行中的事项" : model.activityTitle)
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

    var expandedClipboardLinkView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundColor(.blue)
                Text("检测到剪贴板链接")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }

            Text(model.clipboardLinkDisplay)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: { model.onDismissClipboardLink?() }) {
                    Text("忽略")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button(action: { model.onOpenClipboardLink?() }) {
                    Text("打开网址")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.85))
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

    var clipboardLinkCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("剪贴板链接")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(model.clipboardLinkDisplay)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: { model.onOpenClipboardLink?() }) {
                Text("打开网址")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(9)
            }
            .buttonStyle(.plain)
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
    private var islandFrameAnimationTimer: Timer?
    private var clipboardMonitorTimer: Timer?
    private var appChannel: FlutterMethodChannel?
    private var flutterChannel: FlutterMethodChannel?
    private var observers: [NSObjectProtocol] = []

    private var islandEnabled = true
    private var isShortcutHidden = false
    private var showOnNotchlessDisplay = true
    private var remindersEnabled = true
    private var clipboardLinksEnabled = false
    private var isExpanded = false
    private var isPinnedExpanded = false
    private var isPointerInsideIsland = false
    private var currentReminder: [String: Any]?
    private var reminderQueue: [[String: Any]] = []
    private var reminderIds: Set<String> = []
    private var lastScreenNumber: NSNumber?
    private var lastMinuteRefreshKey: Int64 = -1
    private var visibilityHotKeyRef: EventHotKeyRef?
    private var visibilityHotKeyHandlerRef: EventHandlerRef?
    private var registeredVisibilityShortcut: (keyCode: UInt32, modifiers: UInt32)?
    private var lastClipboardChangeCount = -1
    private var clipboardURL: URL?
    private var clipboardLinkExpiresAt: TimeInterval = 0
    private var clipboardDidForceExpansion = false

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

    func configureIsland(
        enabled: Bool,
        showOnNotchlessDisplay: Bool,
        remindersEnabled: Bool,
        clipboardLinksEnabled: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if enabled && !self.islandEnabled {
                self.isShortcutHidden = false
            }
            self.islandEnabled = enabled
            self.showOnNotchlessDisplay = showOnNotchlessDisplay
            self.remindersEnabled = remindersEnabled
            self.clipboardLinksEnabled = clipboardLinksEnabled
            if !remindersEnabled {
                self.clearIslandReminders()
            }
            if enabled && clipboardLinksEnabled {
                self.startClipboardMonitoring()
            } else {
                self.stopClipboardMonitoring(clearLink: true)
            }
            self.refreshDisplay()
            self.scheduleNextUpdate()
        }
    }

    func configureVisibilityShortcut(
        key: String,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool
    ) -> Bool {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalizedKey.isEmpty {
            unregisterVisibilityHotKey()
            registeredVisibilityShortcut = nil
            return true
        }

        guard let keyCode = carbonKeyCode(for: normalizedKey) else { return false }
        // 只允许 Shift 会劫持正常的大写字母输入，必须至少包含一个
        // Command / Option / Control 修饰键。
        guard command || option || control else { return false }
        var modifiers: UInt32 = 0
        if command { modifiers |= UInt32(cmdKey) }
        if option { modifiers |= UInt32(optionKey) }
        if control { modifiers |= UInt32(controlKey) }
        if shift { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { return false }

        if let current = registeredVisibilityShortcut,
           current.keyCode == keyCode,
           current.modifiers == modifiers,
           visibilityHotKeyRef != nil {
            return true
        }

        guard installVisibilityHotKeyHandlerIfNeeded() else { return false }
        let previousShortcut = registeredVisibilityShortcut
        unregisterVisibilityHotKey()

        if registerVisibilityHotKey(keyCode: keyCode, modifiers: modifiers) {
            registeredVisibilityShortcut = (keyCode, modifiers)
            return true
        }

        if let previous = previousShortcut,
           registerVisibilityHotKey(
               keyCode: previous.keyCode,
               modifiers: previous.modifiers
           ) {
            registeredVisibilityShortcut = previous
        } else {
            registeredVisibilityShortcut = nil
        }
        return false
    }

    fileprivate func toggleIslandVisibilityFromHotKey() {
        guard islandEnabled else { return }
        isShortcutHidden.toggle()
        if isShortcutHidden {
            hideIsland()
        } else {
            refreshDisplay()
            scheduleNextUpdate()
        }
    }

    private func installVisibilityHotKeyHandlerIfNeeded() -> Bool {
        if visibilityHotKeyHandlerRef != nil { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            islandVisibilityHotKeyHandler,
            1,
            &eventType,
            userData,
            &visibilityHotKeyHandlerRef
        )
        if status != noErr {
            NSLog("[MacIsland] Failed to install hot key handler: %d", status)
        }
        return status == noErr
    }

    private func registerVisibilityHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let hotKeyID = EventHotKeyID(
            signature: islandVisibilityHotKeySignature,
            id: islandVisibilityHotKeyID
        )
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &visibilityHotKeyRef
        )
        if status != noErr {
            visibilityHotKeyRef = nil
            NSLog("[MacIsland] Failed to register visibility hot key: %d", status)
        }
        return status == noErr
    }

    private func unregisterVisibilityHotKey() {
        if let hotKeyRef = visibilityHotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            visibilityHotKeyRef = nil
        }
    }

    private func carbonKeyCode(for key: String) -> UInt32? {
        let keyCodes: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C,
            "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
            "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I,
            "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
            "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
            "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U,
            "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
            "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9,
            "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3,
            "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
            "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9,
            "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
        ]
        guard let code = keyCodes[key] else { return nil }
        return UInt32(code)
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
        lastMinuteRefreshKey = Int64(Date().timeIntervalSince1970) / 60
        let hasReminder = remindersEnabled && currentReminder != nil
        let hasActivity = isOngoingActivityActive
        let hasClipboardLink = clipboardLinksEnabled && clipboardURL != nil
        let hasLiveContent = isPomodoroActive || hasReminder || hasActivity || hasClipboardLink
        guard islandEnabled, !isShortcutHidden else {
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
        // 普通屏幕没有可供空闲态收纳的物理刘海；没有实时内容时仍然隐藏。
        guard hasLiveContent || geometry.hasNotch else {
            hideIsland()
            return
        }

        // 实时内容刚结束时不能沿用之前的点击/提醒展开状态。空闲态只在
        // 指针位于刘海交互区域内时展开，移出后一定完全缩回刘海。
        if !hasLiveContent {
            isPinnedExpanded = false
            isExpanded = isPointerInsideIsland
        }
        let expanded = hasReminder || hasClipboardLink || isExpanded
        let detailed = hasReminder || isPinnedExpanded

        let view = ensureIslandModel()
        view.phase = phase
        view.timeText = calculateTimeText()
        view.todoTitle = todoTitle
        view.isPaused = isPaused
        view.isRemote = isRemote
        view.hasNotch = geometry.hasNotch
        view.topInset = geometry.topInset
        view.notchWidth = geometry.notchWidth
        view.isIdle = !hasLiveContent
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
        view.clipboardLinkActive = hasClipboardLink
        view.clipboardLinkDisplay = clipboardURL.map(clipboardDisplayText) ?? ""
        updateExpansionState(view, expanded: expanded, detailed: detailed)
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

        let collapsedNotchWidth = geometry.notchWidth > 0 ? geometry.notchWidth : 180
        // 收起态只在物理刘海两侧各保留约 80pt。旧的 430pt 下限会覆盖
        // Android Studio 等菜单项较多的应用，且远宽于实际刘海区域。
        let liveCompactWidth = max(320, collapsedNotchWidth + 160)
        let compactWidth: CGFloat = geometry.hasNotch
            ? (hasLiveContent ? liveCompactWidth : collapsedNotchWidth)
            : (hasActivity || isPomodoroActive ? 320 : 280)
        let compactHeight: CGFloat = geometry.hasNotch
            ? (hasLiveContent ? max(geometry.topInset, 28) + 4 : max(geometry.topInset, 28))
            : 68
        let focusWithActivity = isPomodoroActive && hasActivity
        let focusWithReminder = isPomodoroActive && hasReminder
        let expandedWidthFloor: CGFloat = geometry.hasNotch
            ? max(360, geometry.notchWidth + 80)
            : 320
        let width = expanded
            ? max(
                detailed ? 360 : ((focusWithReminder || hasClipboardLink) ? 360 : (hasActivity ? 330 : 320)),
                expandedWidthFloor
            )
            : compactWidth
        let height: CGFloat
        let widthStr: CGFloat = width
        
        let hasNotch = geometry.hasNotch
        let topInset = hasNotch ? max(geometry.topInset, 28) : 6
        
        if !expanded {
            height = compactHeight
        } else {
            let topPadding: CGFloat = 8
            let bottomPadding: CGFloat = 20
            var contentHeight: CGFloat

            if isPomodoroActive {
                // expandedFocusView 的固定内容总高为 204pt。
                contentHeight = 204
                if !view.focusTagNames.isEmpty {
                    contentHeight += 32
                }
                // 备注可能换行，最终高度由 SwiftUI 实际布局回传；这里不再
                // 预留猜测值，避免不可见/空白备注把首次展开窗口撑高。

                // reminderCard/activityCard 是单行内容加 12pt 内边距，实际约 39pt。
                if hasReminder && !view.reminderTitle.isEmpty {
                    contentHeight += 12 + 39
                } else if hasClipboardLink {
                    contentHeight += 12 + 54
                } else if hasActivity && !view.activityTitle.isEmpty {
                    contentHeight += 12 + 39
                }
            } else if hasReminder {
                contentHeight = 104
            } else if hasClipboardLink {
                contentHeight = 104
            } else {
                contentHeight = 70
            }

            if detailed {
                contentHeight += 20 + 68
            }
            height = topInset + topPadding + contentHeight + bottomPadding
        }
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )

        let windowWasVisible = islandWindow?.isVisible == true
        if view.revealHeight <= 0 {
            setIslandRevealHeight(
                view,
                expanded && !windowWasVisible ? compactHeight : height
            )
        }
        let window = ensureIslandWindow(frame: frame, view: view)
        window.hasShadow = hasLiveContent || expanded
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = window.isVisible && !reduceMotion && lastScreenNumber == screenNumber
        let shouldAnimateFirstExpansion = !window.isVisible && expanded && !reduceMotion
        if shouldAnimateFirstExpansion {
            window.orderFrontRegardless()
            animateIslandFrame(
                window,
                view: view,
                to: frame,
                topEdge: screen.frame.maxY,
                duration: islandExpansionDuration
            )
        } else if shouldAnimate
                    && (!NSEqualRects(window.frame, frame)
                        || abs(view.revealHeight - height) > 0.5) {
            animateIslandFrame(
                window,
                view: view,
                to: frame,
                topEdge: screen.frame.maxY,
                duration: expanded
                    ? islandExpansionDuration
                    : islandCollapseDuration
            )
        } else {
            islandFrameAnimationTimer?.invalidate()
            islandFrameAnimationTimer = nil
            window.setFrame(frame, display: true)
            setIslandRevealHeight(view, height)
        }
        lastScreenNumber = screenNumber
        // ObservableObject triggers UI update
        window.orderFrontRegardless()
    }

    /// 展开时先把窗口画布扩到足够高度，再从顶部逐帧增加可见高度。
    /// matched-geometry 文字因此始终有完整画布，不会像旧实现那样在
    /// 展开途中被矮窗口裁掉；收回结束后才真正缩小窗口。
    private func animateIslandFrame(
        _ window: MacIslandPanel,
        view: IslandStateModel,
        to targetFrame: NSRect,
        topEdge: CGFloat,
        duration: TimeInterval
    ) {
        islandFrameAnimationTimer?.invalidate()

        let currentFrame = window.frame
        let startFrame = NSRect(
            x: currentFrame.origin.x,
            y: topEdge - currentFrame.height,
            width: currentFrame.width,
            height: currentFrame.height
        )
        let startRevealHeight = view.revealHeight > 0
            ? view.revealHeight
            : min(startFrame.height, targetFrame.height)
        let canvasHeight = max(max(startFrame.height, targetFrame.height), startRevealHeight)
        let canvasStartFrame = NSRect(
            x: startFrame.origin.x,
            y: topEdge - canvasHeight,
            width: startFrame.width,
            height: canvasHeight
        )
        // 先建立完整的纵向画布；此时遮罩仍保持旧高度，视觉上不会跳变。
        window.setFrame(canvasStartFrame, display: true)
        setIslandRevealHeight(view, startRevealHeight)

        let startTime = CACurrentMediaTime()
        let startMidX = canvasStartFrame.midX
        let targetMidX = targetFrame.midX
        var animationTimer: Timer?
        animationTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak window] timer in
            guard let self = self, let window = window else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(1, max(0, elapsed / max(duration, 0.001)))
            // smootherstep：比普通 ease-in-out 的起落更柔和，面板不会像
            // 突然弹出，也不会在动画末尾生硬刹停。
            let easedValue = progress * progress * progress
                * (progress * (progress * 6 - 15) + 10)
            let eased = CGFloat(easedValue)
            let width = canvasStartFrame.width
                + (targetFrame.width - canvasStartFrame.width) * eased
            let revealHeight = startRevealHeight
                + (targetFrame.height - startRevealHeight) * eased
            let midX = startMidX + (targetMidX - startMidX) * eased
            let nextFrame = NSRect(
                x: midX - width / 2,
                y: topEdge - canvasHeight,
                width: width,
                height: canvasHeight
            )
            window.setFrame(nextFrame, display: true)
            self.setIslandRevealHeight(view, revealHeight)

            if progress >= 1 {
                timer.invalidate()
                window.setFrame(targetFrame, display: true)
                self.setIslandRevealHeight(view, targetFrame.height)
                if self.islandFrameAnimationTimer === timer {
                    self.islandFrameAnimationTimer = nil
                }
            }
        }

        if let animationTimer = animationTimer {
            islandFrameAnimationTimer = animationTimer
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    private func setIslandRevealHeight(_ view: IslandStateModel, _ height: CGFloat) {
        guard abs(view.revealHeight - height) > 0.01 else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            view.revealHeight = height
        }
    }

    private func updateExpansionState(
        _ view: IslandStateModel,
        expanded: Bool,
        detailed: Bool
    ) {
        guard view.expanded != expanded || view.detailed != detailed else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            view.expanded = expanded
            view.detailed = detailed
        } else {
            let isGrowing = (!view.expanded && expanded)
                || (!view.detailed && detailed)
            withAnimation(isGrowing ? islandExpansionAnimation : islandCollapseAnimation) {
                view.expanded = expanded
                view.detailed = detailed
            }
        }
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
        view.onOpenClipboardLink = { [weak self] in
            self?.openClipboardLink()
        }
        view.onDismissClipboardLink = { [weak self] in
            self?.dismissClipboardLink()
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

    private func startClipboardMonitoring() {
        guard clipboardMonitorTimer == nil else { return }
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        let monitor = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(clipboardMonitorFired),
            userInfo: nil,
            repeats: true
        )
        monitor.tolerance = 0.2
        RunLoop.main.add(monitor, forMode: .common)
        clipboardMonitorTimer = monitor
    }

    private func stopClipboardMonitoring(clearLink: Bool) {
        clipboardMonitorTimer?.invalidate()
        clipboardMonitorTimer = nil
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        if clearLink {
            clearClipboardLink(restoreExpansion: true, refresh: false)
        }
    }

    @objc private func clipboardMonitorFired() {
        guard islandEnabled, clipboardLinksEnabled else { return }

        if clipboardURL != nil,
           Date().timeIntervalSince1970 >= clipboardLinkExpiresAt {
            dismissClipboardLink()
        }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = changeCount
        guard !isShortcutHidden else { return }

        let rawValue = pasteboard.string(forType: .URL)
            ?? pasteboard.string(forType: .string)
        guard let rawValue = rawValue,
              let url = normalizedClipboardURL(rawValue) else {
            if clipboardURL != nil {
                dismissClipboardLink()
            }
            return
        }

        if clipboardURL == nil {
            clipboardDidForceExpansion = !isExpanded
        }
        clipboardURL = url
        clipboardLinkExpiresAt = Date().timeIntervalSince1970 + 15
        isExpanded = true
        refreshDisplay()
    }

    private func normalizedClipboardURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048 else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        let candidate: String
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            candidate = trimmed
        } else {
            // 其他显式 scheme 一律拒绝；无 scheme 时只为看起来像域名的
            // 内容补 https，避免把普通单词误判成网址。
            guard !trimmed.contains("://"), trimmed.contains(".") else {
                return nil
            }
            candidate = "https://\(trimmed)"
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host,
              !host.isEmpty,
              host == "localhost" || host.contains(".") || host.contains(":") else {
            return nil
        }
        return components.url
    }

    private func clipboardDisplayText(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return url.absoluteString
        }
        var display = host
        if let port = components.port {
            display += ":\(port)"
        }
        if !components.path.isEmpty && components.path != "/" {
            display += components.path.removingPercentEncoding ?? components.path
        }
        if components.query != nil {
            display += "?…"
        }
        if display.count > 160 {
            return String(display.prefix(78)) + "…" + String(display.suffix(78))
        }
        return display
    }

    private func openClipboardLink() {
        guard let url = clipboardURL else { return }
        NSWorkspace.shared.open(url)
        dismissClipboardLink()
    }

    private func dismissClipboardLink() {
        clearClipboardLink(restoreExpansion: true, refresh: true)
    }

    private func clearClipboardLink(restoreExpansion: Bool, refresh: Bool) {
        guard clipboardURL != nil else { return }
        clipboardURL = nil
        clipboardLinkExpiresAt = 0
        if restoreExpansion,
           clipboardDidForceExpansion,
           currentReminder == nil,
           !isPinnedExpanded {
            isExpanded = isPointerInsideIsland
        }
        clipboardDidForceExpansion = false
        if refresh {
            refreshDisplay()
            scheduleNextUpdate()
        }
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
        hostingView.onMouseEntered = { [weak self, weak view] in
            guard let self = self, let view = view else { return }
            self.isPointerInsideIsland = true
            guard !view.expanded else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                view.expanded = true
            } else {
                withAnimation(islandExpansionAnimation) {
                    view.expanded = true
                }
            }
            view.onExpansionChanged?(true, view.detailed)
        }
        hostingView.onMouseExited = { [weak self, weak view] in
            guard let self = self, let view = view else { return }
            self.isPointerInsideIsland = false
            if view.isIdle || (!view.detailed && view.expanded && !view.reminderActive) {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    view.expanded = false
                } else {
                    withAnimation(islandCollapseAnimation) {
                        view.expanded = false
                    }
                }
                view.onExpansionChanged?(false, false)
            }
        }
        window.contentView = hostingView
        islandWindow = window
        return window
    }

    private func hideIsland() {
        islandFrameAnimationTimer?.invalidate()
        islandFrameAnimationTimer = nil
        if let islandModel = islandModel {
            setIslandRevealHeight(islandModel, 0)
        }
        isExpanded = false
        isPinnedExpanded = false
        isPointerInsideIsland = false
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
        let previousReminderId = currentReminder.map(reminderIdentifier)
        let activityWasActive = isOngoingActivityActive
        expireStartedReminders()
        let reminderId = currentReminder.map(reminderIdentifier)
        let activityIsActive = isOngoingActivityActive

        // 提醒切换、提醒结束或活动跨过结束边界时，仍需完整刷新布局。
        if previousReminderId != reminderId || activityWasActive != activityIsActive {
            refreshDisplay()
            return
        }

        let minuteKey = Int64(Date().timeIntervalSince1970) / 60
        if minuteKey != lastMinuteRefreshKey {
            // 课程倒计时、活动剩余时间和今日统计只需按分钟刷新。
            refreshDisplay()
            return
        }

        // 番茄钟每秒只更新一个固定尺寸的文本，避免重写整个 SwiftUI 模型
        // 以及重复计算窗口尺寸造成视觉抖动。
        guard isPomodoroActive, let islandModel = islandModel else { return }
        let nextTimeText = calculateTimeText()
        if islandModel.timeText != nextTimeText {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                islandModel.timeText = nextTimeText
            }
        }
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
