import Cocoa
import FlutterMacOS
import QuartzCore

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
    var detailed = false { didSet { needsDisplay = true } }
    var hasNotch = false { didSet { needsDisplay = true } }
    var topInset: CGFloat = 0 { didSet { needsDisplay = true } }
    var focusCurrentCycle = 1 { didSet { needsDisplay = true } }
    var focusTotalCycles = 1 { didSet { needsDisplay = true } }
    var focusPlannedSeconds: Int64 = 0 { didSet { needsDisplay = true } }
    var focusTargetEndMs: Int64 = 0 { didSet { needsDisplay = true } }
    var focusSessionStartMs: Int64 = 0 { didSet { needsDisplay = true } }
    var focusAccumulatedMs: Int64 = 0 { didSet { needsDisplay = true } }
    var focusPauseStartMs: Int64 = 0 { didSet { needsDisplay = true } }
    var focusPausedAtMs: Int64 = 0 { didSet { needsDisplay = true } }
    var focusMode = "countdown" { didSet { needsDisplay = true } }
    var focusNote = "" { didSet { needsDisplay = true } }
    var focusTagNames: [String] = [] { didSet { needsDisplay = true } }
    var focusTodoId = "" { didSet { needsDisplay = true } }
    var focusPlanBlockId = "" { didSet { needsDisplay = true } }
    var sourceDeviceName = "" { didSet { needsDisplay = true } }
    var reminderActive = false { didSet { needsDisplay = true } }
    var reminderTitle = "" { didSet { needsDisplay = true } }
    var reminderBody = "" { didSet { needsDisplay = true } }
    var reminderType = "" { didSet { needsDisplay = true } }
    var reminderQueueCount = 0 { didSet { needsDisplay = true } }
    var activityActive = false { didSet { needsDisplay = true } }
    var activityKind = "" { didSet { needsDisplay = true } }
    var activityTitle = "" { didSet { needsDisplay = true } }
    var activityId = "" { didSet { needsDisplay = true } }
    var activitySubtitle = "" { didSet { needsDisplay = true } }
    var activityDetail = "" { didSet { needsDisplay = true } }
    var activityRelatedTodoId = "" { didSet { needsDisplay = true } }
    var activityGroupName = "" { didSet { needsDisplay = true } }
    var activityStartMs: Int64 = 0 { didSet { needsDisplay = true } }
    var activityEndMs: Int64 = 0 { didSet { needsDisplay = true } }
    var nextActivityId = "" { didSet { needsDisplay = true } }
    var nextActivityKind = "" { didSet { needsDisplay = true } }
    var nextActivityTitle = "" { didSet { needsDisplay = true } }
    var nextActivitySubtitle = "" { didSet { needsDisplay = true } }
    var nextActivityStartMs: Int64 = 0 { didSet { needsDisplay = true } }
    var nextActivityEndMs: Int64 = 0 { didSet { needsDisplay = true } }
    var reminderTimeText = "" { didSet { needsDisplay = true } }
    var reminderDetailText = "" { didSet { needsDisplay = true } }
    var reminderNextTitle = "" { didSet { needsDisplay = true } }
    var reminderNextTimeText = "" { didSet { needsDisplay = true } }
    var reminderEntityKind = "" { didSet { needsDisplay = true } }
    var reminderEntityId = "" { didSet { needsDisplay = true } }

    var onExpansionChanged: ((Bool, Bool) -> Void)?
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpenApp: (() -> Void)?
    var onOpenEntity: ((String, String) -> Void)?
    var onStartFocus: ((String, String) -> Void)?
    var onCompleteTodo: ((String) -> Void)?
    var onAcknowledgeReminder: (() -> Void)?
    var onSnoozeReminder: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var pauseRect = NSRect.zero
    private var stopRect = NSRect.zero
    private var openRect = NSRect.zero
    private var acknowledgeRect = NSRect.zero
    private var snoozeRect = NSRect.zero
    private var activityRect = NSRect.zero
    private var nextActivityRect = NSRect.zero
    private var startFocusRect = NSRect.zero
    private var completeTodoRect = NSRect.zero
    private var reminderOpenRect = NSRect.zero

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

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
        detailed = false
        onExpansionChanged?(true, false)
    }

    override func mouseExited(with event: NSEvent) {
        guard !reminderActive else { return }
        guard !detailed else { return }
        guard expanded else { return }
        expanded = false
        onExpansionChanged?(false, false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if reminderActive {
            if acknowledgeRect.contains(point) {
                onAcknowledgeReminder?()
                return
            } else if snoozeRect.contains(point) {
                onSnoozeReminder?()
                return
            } else if reminderOpenRect.contains(point) {
                onOpenEntity?(reminderEntityKind, reminderEntityId)
                return
            }
            if !isFocusActive { return }
        }
        if nextActivityRect.contains(point) {
            onOpenEntity?(nextActivityKind, nextActivityId)
            return
        }
        if activityRect.contains(point) {
            onOpenEntity?(activityKind, activityId)
            return
        }
        if startFocusRect.contains(point) {
            onStartFocus?(activityKind, activityId)
            return
        }
        if completeTodoRect.contains(point) {
            let todoId = activityRelatedTodoId.isEmpty ? activityId : activityRelatedTodoId
            onCompleteTodo?(todoId)
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
                if !isFocusActive && activityActive {
                    onOpenEntity?(activityKind, activityId)
                } else if !focusPlanBlockId.isEmpty {
                    onOpenEntity?("plan_block", focusPlanBlockId)
                } else if !focusTodoId.isEmpty {
                    onOpenEntity?("todo", focusTodoId)
                } else {
                    onOpenApp?()
                }
                return
            }
        }
        if expanded {
            if detailed {
                detailed = false
                expanded = false
                onExpansionChanged?(false, false)
            } else {
                detailed = true
                onExpansionChanged?(true, true)
            }
        } else {
            expanded = true
            detailed = false
            onExpansionChanged?(true, false)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        pauseRect = .zero
        stopRect = .zero
        openRect = .zero
        acknowledgeRect = .zero
        snoozeRect = .zero
        activityRect = .zero
        nextActivityRect = .zero
        startFocusRect = .zero
        completeTodoRect = .zero
        reminderOpenRect = .zero

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

        if expanded {
            if isFocusActive {
                drawExpanded(topOffset: topJoinHeight)
                if reminderActive {
                    drawReminderCard(topOffset: topJoinHeight)
                } else if activityActive {
                    drawActivityCard(topOffset: topJoinHeight)
                }
            } else if reminderActive {
                drawReminder(topOffset: topJoinHeight)
            } else {
                drawActivityExpanded(topOffset: topJoinHeight)
            }
        } else {
            if isFocusActive {
                drawCompact(topOffset: topJoinHeight)
            } else {
                drawActivityCompact(topOffset: topJoinHeight)
            }
        }
    }

    private var isFocusActive: Bool {
        phase == "focusing" || phase == "breaking"
    }

    private func drawCompact(topOffset: CGFloat) {
        activityRect = .zero
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
        activityRect = .zero
        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let accent = phase == "breaking" ? NSColor.systemTeal : NSColor.systemOrange
        let title = phase == "breaking" ? "休息时间" : (isRemote ? "其他设备正在专注" : "正在专注")

        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: contentTop + 4, width: 10, height: 10)).fill()
        drawText(
            title,
            rect: NSRect(x: 36, y: contentTop, width: bounds.width - 140, height: 20),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white,
            alignment: .left
        )
        drawText(
            focusCycleText,
            rect: NSRect(x: bounds.width - 112, y: contentTop, width: 94, height: 20),
            font: .systemFont(ofSize: 10.5, weight: .medium),
            color: accent,
            alignment: .right
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

        let device = sourceDeviceName.isEmpty ? (isRemote ? "其他设备" : "本机") : sourceDeviceName
        let focusMeta = "\(device)  ·  \(focusEndText)  ·  \(focusPausedText)"
        drawText(
            focusMeta,
            rect: NSRect(x: 20, y: contentTop + 82, width: bounds.width - 40, height: 16),
            font: .systemFont(ofSize: 9.5, weight: .regular),
            color: .white.withAlphaComponent(0.52),
            alignment: .center
        )
        drawFocusProgress(
            rect: NSRect(x: 28, y: contentTop + 103, width: bounds.width - 56, height: 4),
            accent: accent
        )

        if detailed {
            let tags = focusTagNames.isEmpty ? "未设置标签" : focusTagNames.prefix(3).joined(separator: " · ")
            drawText(
                tags,
                rect: NSRect(x: 24, y: contentTop + 114, width: bounds.width - 48, height: 16),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: accent.withAlphaComponent(0.9),
                alignment: .center
            )
            if !focusNote.isEmpty {
                drawText(
                    focusNote,
                    rect: NSRect(x: 28, y: contentTop + 133, width: bounds.width - 56, height: 30),
                    font: .systemFont(ofSize: 10, weight: .regular),
                    color: .white.withAlphaComponent(0.58),
                    alignment: .center,
                    lineBreakMode: .byTruncatingTail
                )
            }
            if !activityActive && !reminderActive && !nextActivityTitle.isEmpty {
                drawNextActivityCard(y: contentTop + 164)
            }
        }

        let buttonY = bounds.height - 38
        if isRemote {
            pauseRect = .zero
            stopRect = .zero
            openRect = NSRect(x: 18, y: buttonY, width: bounds.width - 36, height: 26)
            drawButton(title: "打开应用", rect: openRect, color: NSColor.white.withAlphaComponent(0.14))
        } else {
            let gap: CGFloat = 7
            let buttonCount: CGFloat = detailed ? 3 : 2
            let width = (bounds.width - 36 - gap * (buttonCount - 1)) / buttonCount
            pauseRect = NSRect(x: 18, y: buttonY, width: width, height: 26)
            stopRect = NSRect(x: pauseRect.maxX + gap, y: buttonY, width: width, height: 26)
            openRect = detailed
                ? NSRect(x: stopRect.maxX + gap, y: buttonY, width: width, height: 26)
                : .zero
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
            if detailed {
                drawButton(title: "打开", rect: openRect, color: accent.withAlphaComponent(0.72))
            }
        }
    }

    private func drawActivityCompact(topOffset: CGFloat) {
        activityRect = .zero
        let contentTop = hasNotch ? max(topOffset - 1, 26) : 6
        let centerY = contentTop + max((bounds.height - contentTop) / 2, 12)
        let accent = activityAccent

        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: centerY - 4, width: 8, height: 8)).fill()
        drawText(
            activityTitle,
            rect: NSRect(x: 29, y: centerY - 10, width: bounds.width - 112, height: 20),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .white,
            alignment: .left
        )
        drawText(
            activityRemainingText,
            rect: NSRect(x: bounds.width - 80, y: centerY - 9, width: 65, height: 18),
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            color: .white.withAlphaComponent(0.72),
            alignment: .right
        )
    }

    private func drawActivityExpanded(topOffset: CGFloat) {
        pauseRect = .zero
        stopRect = .zero
        activityRect = .zero
        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let accent = activityAccent

        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: contentTop + 4, width: 10, height: 10)).fill()
        drawText(
            activityCategory,
            rect: NSRect(x: 36, y: contentTop, width: bounds.width - 54, height: 20),
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: accent,
            alignment: .left
        )
        drawText(
            activityTitle,
            rect: NSRect(x: 20, y: contentTop + 27, width: bounds.width - 40, height: 24),
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .white,
            alignment: .center
        )
        let details = activitySubtitle.isEmpty
            ? activityTimeRange
            : "\(activityTimeRange)  ·  \(activitySubtitle)"
        drawText(
            details,
            rect: NSRect(x: 24, y: contentTop + 54, width: bounds.width - 48, height: 18),
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .white.withAlphaComponent(0.62),
            alignment: .center
        )
        drawText(
            activityRemainingText,
            rect: NSRect(x: 18, y: contentTop + 78, width: bounds.width - 36, height: 28),
            font: .monospacedDigitSystemFont(ofSize: 21, weight: .semibold),
            color: .white,
            alignment: .center
        )
        drawActivityProgress(
            rect: NSRect(x: 28, y: contentTop + 112, width: bounds.width - 56, height: 4),
            accent: accent
        )

        if detailed {
            let context = [activityGroupName, activityDetail]
                .filter { !$0.isEmpty }
                .joined(separator: "  ·  ")
            if !context.isEmpty {
                drawText(
                    context,
                    rect: NSRect(x: 24, y: contentTop + 124, width: bounds.width - 48, height: 17),
                    font: .systemFont(ofSize: 10, weight: .regular),
                    color: .white.withAlphaComponent(0.56),
                    alignment: .center
                )
            }
            if !nextActivityTitle.isEmpty {
                drawNextActivityCard(y: contentTop + 146)
            }
        }

        let buttonY = bounds.height - 38
        if !detailed || activityKind == "course" {
            openRect = NSRect(x: 18, y: buttonY, width: bounds.width - 36, height: 26)
            drawButton(
                title: activityKind == "course" ? "打开课程" : "打开事项",
                rect: openRect,
                color: accent.withAlphaComponent(0.76)
            )
            return
        }

        let gap: CGFloat = 7
        if activityKind == "todo" {
            let width = (bounds.width - 36 - gap * 2) / 3
            startFocusRect = NSRect(x: 18, y: buttonY, width: width, height: 26)
            completeTodoRect = NSRect(x: startFocusRect.maxX + gap, y: buttonY, width: width, height: 26)
            openRect = NSRect(x: completeTodoRect.maxX + gap, y: buttonY, width: width, height: 26)
            drawButton(title: "专注", rect: startFocusRect, color: accent.withAlphaComponent(0.76))
            drawButton(title: "完成", rect: completeTodoRect, color: NSColor.systemGreen.withAlphaComponent(0.72))
            drawButton(title: "打开", rect: openRect, color: NSColor.white.withAlphaComponent(0.14))
        } else {
            let width = (bounds.width - 36 - gap) / 2
            startFocusRect = NSRect(x: 18, y: buttonY, width: width, height: 26)
            openRect = NSRect(x: startFocusRect.maxX + gap, y: buttonY, width: width, height: 26)
            drawButton(title: "开始专注", rect: startFocusRect, color: accent.withAlphaComponent(0.76))
            drawButton(title: "打开规划", rect: openRect, color: NSColor.white.withAlphaComponent(0.14))
        }
    }

    private func drawActivityCard(topOffset: CGFloat) {
        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let cardY = contentTop + (detailed ? 166 : 116)
        activityRect = NSRect(
            x: 18,
            y: cardY,
            width: bounds.width - 36,
            height: detailed ? 54 : 42
        )
        NSColor.white.withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: activityRect, xRadius: 11, yRadius: 11).fill()
        activityAccent.setFill()
        NSBezierPath(ovalIn: NSRect(x: activityRect.minX + 10, y: activityRect.minY + 9, width: 7, height: 7)).fill()
        drawText(
            activityTitle,
            rect: NSRect(x: activityRect.minX + 24, y: activityRect.minY + 4, width: activityRect.width - 100, height: 17),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .white,
            alignment: .left
        )
        drawText(
            activityRemainingText,
            rect: NSRect(x: activityRect.maxX - 72, y: activityRect.minY + 4, width: 62, height: 17),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            color: .white.withAlphaComponent(0.72),
            alignment: .right
        )
        drawText(
            activityCategory + " · " + activityTimeRange,
            rect: NSRect(x: activityRect.minX + 24, y: activityRect.minY + 21, width: activityRect.width - 34, height: 15),
            font: .systemFont(ofSize: 9.5, weight: .regular),
            color: .white.withAlphaComponent(0.5),
            alignment: .left
        )
        if detailed {
            let context = [activityGroupName, activitySubtitle, activityDetail]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            drawText(
                context,
                rect: NSRect(x: activityRect.minX + 24, y: activityRect.minY + 36, width: activityRect.width - 34, height: 14),
                font: .systemFont(ofSize: 9, weight: .regular),
                color: .white.withAlphaComponent(0.46),
                alignment: .left
            )
            if !nextActivityTitle.isEmpty {
                drawNextActivityCard(y: activityRect.maxY + 8)
            }
        }
    }

    private func drawReminderCard(topOffset: CGFloat) {
        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let card = NSRect(
            x: 18,
            y: contentTop + (detailed ? 166 : 116),
            width: bounds.width - 36,
            height: detailed ? 92 : 50
        )
        let accent = reminderAccent
        NSColor.white.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: card, xRadius: 11, yRadius: 11).fill()
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: card.minX + 10, y: card.minY + 10, width: 7, height: 7)).fill()

        drawText(
            reminderTitle,
            rect: NSRect(x: card.minX + 24, y: card.minY + 4, width: card.width - (detailed ? 34 : 128), height: 18),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .white,
            alignment: .left
        )
        let queueSuffix = reminderQueueCount > 0 ? " · 另 \(reminderQueueCount) 条" : ""
        drawText(
            detailed && !reminderTimeText.isEmpty ? reminderTimeText + queueSuffix : reminderCategory + queueSuffix,
            rect: NSRect(x: card.minX + 24, y: card.minY + 25, width: card.width - 128, height: 15),
            font: .systemFont(ofSize: 9.5, weight: .regular),
            color: .white.withAlphaComponent(0.52),
            alignment: .left
        )

        if detailed {
            let preview = !reminderNextTitle.isEmpty
                ? "下一条：\(reminderNextTitle) \(reminderNextTimeText)"
                : reminderDetailText
            drawText(
                preview,
                rect: NSRect(x: card.minX + 24, y: card.minY + 43, width: card.width - 34, height: 15),
                font: .systemFont(ofSize: 9.5, weight: .regular),
                color: .white.withAlphaComponent(0.48),
                alignment: .left
            )
            let gap: CGFloat = 6
            let hasEntity = !reminderEntityId.isEmpty
            let count: CGFloat = hasEntity ? 3 : 2
            let width = (card.width - 20 - gap * (count - 1)) / count
            snoozeRect = NSRect(x: card.minX + 10, y: card.minY + 63, width: width, height: 23)
            acknowledgeRect = NSRect(x: snoozeRect.maxX + gap, y: card.minY + 63, width: width, height: 23)
            reminderOpenRect = hasEntity
                ? NSRect(x: acknowledgeRect.maxX + gap, y: card.minY + 63, width: width, height: 23)
                : .zero
            drawButton(title: "稍后", rect: snoozeRect, color: NSColor.white.withAlphaComponent(0.14))
            drawButton(title: "好的", rect: acknowledgeRect, color: accent.withAlphaComponent(0.78))
            if hasEntity {
                drawButton(title: "打开", rect: reminderOpenRect, color: NSColor.white.withAlphaComponent(0.14))
            }
        } else {
            snoozeRect = NSRect(x: card.maxX - 98, y: card.minY + 14, width: 42, height: 23)
            acknowledgeRect = NSRect(x: card.maxX - 50, y: card.minY + 14, width: 40, height: 23)
            drawButton(title: "稍后", rect: snoozeRect, color: NSColor.white.withAlphaComponent(0.14))
            drawButton(title: "好的", rect: acknowledgeRect, color: accent.withAlphaComponent(0.78))
        }
    }

    private func drawActivityProgress(rect: NSRect, accent: NSColor) {
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        let duration = max(1, activityEndMs - activityStartMs)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let progress = CGFloat(max(0, min(duration, now - activityStartMs))) / CGFloat(duration)
        accent.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    private func drawFocusProgress(rect: NSRect, accent: NSColor) {
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        guard focusPlannedSeconds > 0 else {
            accent.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.32, height: rect.height), xRadius: 2, yRadius: 2).fill()
            return
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard focusSessionStartMs > 0 else {
            let remaining = max(0, focusTargetEndMs - now)
            let duration = max(1, focusPlannedSeconds * 1000)
            let progress = CGFloat(max(0, duration - remaining)) / CGFloat(duration)
            accent.setFill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width * min(1, progress),
                    height: rect.height
                ),
                xRadius: 2,
                yRadius: 2
            ).fill()
            return
        }
        let frozenNow = isPaused ? max(focusPausedAtMs, focusPauseStartMs) : now
        let currentPause = isPaused && focusPauseStartMs > 0 ? max(0, frozenNow - focusPauseStartMs) : 0
        let elapsed = max(0, frozenNow - focusSessionStartMs - focusAccumulatedMs - currentPause)
        let duration = max(1, focusPlannedSeconds * 1000)
        let progress = CGFloat(min(duration, elapsed)) / CGFloat(duration)
        accent.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    private func drawNextActivityCard(y: CGFloat) {
        guard !nextActivityTitle.isEmpty else {
            nextActivityRect = .zero
            return
        }
        nextActivityRect = NSRect(x: 18, y: y, width: bounds.width - 36, height: 42)
        NSColor.white.withAlphaComponent(0.075).setFill()
        NSBezierPath(roundedRect: nextActivityRect, xRadius: 11, yRadius: 11).fill()
        let accent = nextActivityAccent
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: nextActivityRect.minX + 10, y: nextActivityRect.minY + 9, width: 7, height: 7)).fill()
        drawText(
            nextActivityTitle,
            rect: NSRect(x: nextActivityRect.minX + 24, y: nextActivityRect.minY + 4, width: nextActivityRect.width - 112, height: 17),
            font: .systemFont(ofSize: 10.5, weight: .semibold),
            color: .white,
            alignment: .left
        )
        drawText(
            nextActivityStartText,
            rect: NSRect(x: nextActivityRect.maxX - 86, y: nextActivityRect.minY + 4, width: 76, height: 17),
            font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            color: accent,
            alignment: .right
        )
        let detail = nextActivitySubtitle.isEmpty
            ? nextActivityCategory
            : "\(nextActivityCategory) · \(nextActivitySubtitle)"
        drawText(
            detail,
            rect: NSRect(x: nextActivityRect.minX + 24, y: nextActivityRect.minY + 21, width: nextActivityRect.width - 34, height: 15),
            font: .systemFont(ofSize: 9, weight: .regular),
            color: .white.withAlphaComponent(0.46),
            alignment: .left
        )
    }

    private var focusCycleText: String {
        let cycle = max(1, focusCurrentCycle)
        let total = max(cycle, focusTotalCycles)
        return "第 \(cycle)/\(total) 轮"
    }

    private var focusEndText: String {
        if focusMode == "countUp" || focusTargetEndMs <= 0 { return "正计时" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let date = Date(timeIntervalSince1970: Double(focusTargetEndMs) / 1000)
        return "\(formatter.string(from: date)) 结束"
    }

    private var focusPausedText: String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let current = isPaused && focusPauseStartMs > 0 ? max(0, now - focusPauseStartMs) : 0
        let minutes = (focusAccumulatedMs + current) / 60_000
        if minutes <= 0 { return isPaused ? "已暂停" : "未暂停" }
        return "已暂停 \(minutes) 分钟"
    }

    private var nextActivityAccent: NSColor {
        switch nextActivityKind {
        case "course": return .systemBlue
        case "plan_block": return .systemIndigo
        default: return .systemOrange
        }
    }

    private var nextActivityCategory: String {
        switch nextActivityKind {
        case "course": return "下一节课程"
        case "plan_block": return "下一项规划"
        default: return "下一项待办"
        }
    }

    private var nextActivityStartText: String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let minutes = max(0, (nextActivityStartMs - now + 59_999) / 60_000)
        if minutes <= 60 { return minutes <= 1 ? "马上开始" : "\(minutes) 分钟后" }
        let date = Date(timeIntervalSince1970: Double(nextActivityStartMs) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        if Calendar.current.isDateInToday(date) { return time }
        if Calendar.current.isDateInTomorrow(date) { return "明天 \(time)" }
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private var activityAccent: NSColor {
        switch activityKind {
        case "course": return .systemBlue
        case "plan_block": return .systemIndigo
        default: return .systemOrange
        }
    }

    private var reminderAccent: NSColor {
        switch reminderType {
        case "course": return .systemBlue
        case "special_todo": return .systemPurple
        case "plan_block": return .systemIndigo
        default: return .systemOrange
        }
    }

    private var reminderCategory: String {
        switch reminderType {
        case "course": return "课程提醒"
        case "special_todo": return "重要提醒"
        case "plan_block": return "计划提醒"
        default: return "待办提醒"
        }
    }

    fileprivate var activityCategory: String {
        switch activityKind {
        case "course": return "正在上课"
        case "plan_block": return "计划进行中"
        default: return "待办进行中"
        }
    }

    fileprivate var activityRemainingText: String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let remainingMs = max(0, activityEndMs - now)
        let totalMinutes = (remainingMs + 59_999) / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return String(format: "剩 %lld:%02lld", hours, minutes) }
        return "剩 \(minutes) 分钟"
    }

    private var activityTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = Date(timeIntervalSince1970: Double(activityStartMs) / 1000)
        let end = Date(timeIntervalSince1970: Double(activityEndMs) / 1000)
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    private func drawReminder(topOffset: CGFloat) {
        pauseRect = .zero
        stopRect = .zero
        openRect = .zero
        activityRect = .zero

        let contentTop = max(topOffset + 8, hasNotch ? 38 : 18)
        let accent = reminderAccent
        let category = reminderCategory

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
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        if !reminderTimeText.isEmpty {
            drawText(
                reminderTimeText,
                rect: NSRect(x: 24, y: contentTop + 94, width: bounds.width - 48, height: 18),
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                color: accent,
                alignment: .center
            )
        }
        if detailed {
            if !reminderDetailText.isEmpty {
                drawText(
                    reminderDetailText,
                    rect: NSRect(x: 24, y: contentTop + 116, width: bounds.width - 48, height: 17),
                    font: .systemFont(ofSize: 10, weight: .regular),
                    color: .white.withAlphaComponent(0.52),
                    alignment: .center
                )
            }
            if !reminderNextTitle.isEmpty {
                drawText(
                    "下一条：\(reminderNextTitle) \(reminderNextTimeText)",
                    rect: NSRect(x: 24, y: contentTop + 137, width: bounds.width - 48, height: 17),
                    font: .systemFont(ofSize: 9.5, weight: .regular),
                    color: .white.withAlphaComponent(0.46),
                    alignment: .center
                )
            }
        }

        let gap: CGFloat = 7
        let buttonY = bounds.height - 38
        let hasEntity = !reminderEntityId.isEmpty
        let count: CGFloat = hasEntity ? 3 : 2
        let width = (bounds.width - 36 - gap * (count - 1)) / count
        snoozeRect = NSRect(x: 18, y: buttonY, width: width, height: 26)
        acknowledgeRect = NSRect(x: snoozeRect.maxX + gap, y: buttonY, width: width, height: 26)
        reminderOpenRect = hasEntity
            ? NSRect(x: acknowledgeRect.maxX + gap, y: buttonY, width: width, height: 26)
            : .zero
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
        if hasEntity {
            drawButton(
                title: "打开",
                rect: reminderOpenRect,
                color: NSColor.white.withAlphaComponent(0.14)
            )
        }
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
        alignment: NSTextAlignment,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = lineBreakMode
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

        let view = ensureIslandView()
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
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("CountDownTodo 灵动岛")
        if isPomodoroActive {
            let activityValue = hasActivity ? "，同时进行：\(activityTitle)" : ""
            let reminderValue = hasReminder ? "，提醒：\(view.reminderTitle)" : ""
            view.setAccessibilityValue("\(phase == "breaking" ? "休息" : "专注")，\(view.timeText)\(reminderValue)\(activityValue)")
        } else if hasReminder {
            view.setAccessibilityValue("提醒：\(view.reminderTitle)，\(view.reminderBody)")
        } else {
            view.setAccessibilityValue("\(view.activityCategory)，\(activityTitle)，\(view.activityRemainingText)")
        }

        let activityCompactWidth: CGFloat = hasActivity && !isPomodoroActive ? 238 : 196
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
        if !expanded {
            height = compactHeight
        } else if detailed {
            let detailedHeight: CGFloat
            if focusWithReminder {
                detailedHeight = 360
            } else if focusWithActivity {
                detailedHeight = nextActivityTitle.isEmpty ? 305 : 350
            } else if isPomodoroActive {
                detailedHeight = nextActivityTitle.isEmpty ? 275 : 315
            } else if hasReminder {
                detailedHeight = 270
            } else {
                detailedHeight = nextActivityTitle.isEmpty ? 245 : 285
            }
            height = max(detailedHeight, geometry.topInset + detailedHeight - 34)
        } else {
            let quickHeight: CGFloat = isPomodoroActive
                ? (focusWithActivity ? 235 : 205)
                : 218
            height = max(quickHeight, geometry.topInset + quickHeight - 34)
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
        view.needsDisplay = true
        window.orderFrontRegardless()
    }

    private func ensureIslandView() -> MacIslandView {
        if let islandView = islandView { return islandView }
        let view = MacIslandView(frame: .zero)
        view.onExpansionChanged = { [weak self] expanded, detailed in
            guard let self = self else { return }
            self.isExpanded = expanded
            self.isPinnedExpanded = detailed
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

    private func ensureIslandWindow(frame: NSRect, view: MacIslandView) -> MacIslandPanel {
        if let islandWindow = islandWindow { return islandWindow }

        let window = MacIslandPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
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
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
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
