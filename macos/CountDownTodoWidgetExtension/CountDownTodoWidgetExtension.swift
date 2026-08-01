import WidgetKit
import SwiftUI
import AppIntents
import AppKit

// MARK: - Container Background Extension

extension View {
    @ViewBuilder
    func widgetContainerBackground<Background: View>(
        @ViewBuilder _ background: () -> Background
    ) -> some View {
        if #available(macOSApplicationExtension 14.0, iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                background()
            }
        } else {
            self.background(background())
        }
    }
}

// MARK: - Data Models

struct WidgetSnapshot: Codable {
    let updatedAt: String
    let countdowns: [WidgetCountdownItem]
    let todos: [WidgetTodoItem]
    let courses: [WidgetCourseItem]
    let focus: WidgetFocusState
    let recurrenceSeries: [WidgetRecurrenceSeriesItem]?
    let habits: [WidgetHabitItem]?

    static let empty = WidgetSnapshot(
        updatedAt: "",
        countdowns: [],
        todos: [],
        courses: [],
        focus: WidgetFocusState.empty,
        recurrenceSeries: [],
        habits: []
    )
}

struct WidgetHabitItem: Codable, Identifiable {
    let habitId: String
    let title: String
    let icon: String
    let sourceType: String
    let currentValue: Double
    let targetValue: Double
    let unit: String
    let goalMet: Bool
    let quickValues: [Double]

    var id: String { habitId }

    static let empty = WidgetHabitItem(
        habitId: "",
        title: "",
        icon: "",
        sourceType: "quantityCheckIn",
        currentValue: 0,
        targetValue: 0,
        unit: "",
        goalMet: false,
        quickValues: []
    )

    /// 数量型 / 时长型显示 "当前 / 目标"，其余显示达标状态。
    var progressText: String {
        switch sourceType {
        case "quantityCheckIn", "pomodoroTag":
            if goalMet {
                return targetValue > 0 ? "达标 \(formattedCurrent)\(unit)" : formattedCurrent
            }
            return targetValue > 0 ? "\(formattedCurrent) / \(formattedTarget)\(unit)" : formattedCurrent
        case "recurringTodo", "timeCheckIn":
            return goalMet ? "已达标" : "待完成"
        default:
            return goalMet ? "已达标" : "待完成"
        }
    }

    private var formattedCurrent: String {
        formatValue(currentValue)
    }

    private var formattedTarget: String {
        formatValue(targetValue)
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

struct WidgetRecurrenceSeriesItem: Codable, Identifiable {
    let seriesId: String
    let title: String
    let recurrenceType: String
    let recurrenceText: String
    let customIntervalDays: Int?
    let anchorStartMs: Int64
    let anchorDueMs: Int64?
    let recurrenceEndMs: Int64?
    let isActive: Bool
    let contextText: String
    let completedCount: Int
    let overdueCount: Int
    let elapsedCount: Int
    let totalCount: Int?
    let occurrences: [WidgetRecurrenceOccurrenceItem]

    var id: String { seriesId }
}

struct WidgetRecurrenceOccurrenceItem: Codable, Identifiable {
    let occurrenceId: String
    let startAtMs: Int64
    let dueAtMs: Int64?
    let isDone: Bool
    let isDateOnly: Bool
    let isProjected: Bool

    var id: String {
        occurrenceId.isEmpty ? "projected-\(startAtMs)" : occurrenceId
    }

    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startAtMs) / 1000)
    }

    var dueDate: Date? {
        guard let dueAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(dueAtMs) / 1000)
    }
}

struct WidgetCountdownItem: Codable {
    let title: String
    let daysLeft: Int
    let dateText: String
    let subtitle: String

    static let empty = WidgetCountdownItem(title: "", daysLeft: 0, dateText: "", subtitle: "")
}

struct WidgetTodoItem: Codable {
    let title: String
    let timeText: String
    let priority: Int
    let isDone: Bool
    let visibleUntilMs: Int64?

    init(title: String, timeText: String, priority: Int, isDone: Bool, visibleUntilMs: Int64? = nil) {
        self.title = title
        self.timeText = timeText
        self.priority = priority
        self.isDone = isDone
        self.visibleUntilMs = visibleUntilMs
    }

    static let empty = WidgetTodoItem(title: "", timeText: "", priority: 0, isDone: false)

    func isVisible(at date: Date) -> Bool {
        guard let visibleUntilMs, visibleUntilMs > 0 else { return true }
        return Int64(date.timeIntervalSince1970 * 1000) < visibleUntilMs
    }
}

struct WidgetCourseItem: Codable {
    let title: String
    let timeText: String
    let location: String
    let statusText: String

    static let empty = WidgetCourseItem(title: "", timeText: "", location: "", statusText: "")
}

struct WidgetFocusState: Codable {
    let isRunning: Bool
    let currentTitle: String
    let todayMinutes: Int
    let sessionMinutes: Int
    let remainingSeconds: Int

    static let empty = WidgetFocusState(isRunning: false, currentTitle: "", todayMinutes: 0, sessionMinutes: 0, remainingSeconds: 0)
}

// MARK: - Data Loader

class WidgetDataLoader {
    static let shared = WidgetDataLoader()
    private let appGroupId = "group.com.junpgle.countdowntodo"
    private let key = "widget_snapshot_json"
    private let snapshotFileName = "widget_snapshot.json"

    func loadSnapshot() -> WidgetSnapshot {
        guard let jsonString = loadSnapshotJSON() else {
            return .empty
        }

        guard let data = jsonString.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }

        let visibleTodos = snapshot.todos.filter { $0.isVisible(at: Date()) }
        return WidgetSnapshot(
            updatedAt: snapshot.updatedAt,
            countdowns: snapshot.countdowns,
            todos: visibleTodos,
            courses: snapshot.courses,
            focus: snapshot.focus,
            recurrenceSeries: snapshot.recurrenceSeries,
            habits: snapshot.habits
        )
    }

    private func loadSnapshotJSON() -> String? {
        // App Group UserDefaults is the normal signed-app path. Local debug
        // builds can be ad-hoc signed without a usable App Group entitlement,
        // so keep the file written by the macOS host as a read-only fallback.
        if let userDefaults = UserDefaults(suiteName: appGroupId),
           let jsonString = userDefaults.string(forKey: key),
           !jsonString.isEmpty {
            return jsonString
        }

        var candidates: [URL] = []
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            candidates.append(containerURL.appendingPathComponent(snapshotFileName))
        }

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(
            homeDirectory
                .appendingPathComponent("Library/Group Containers")
                .appendingPathComponent(appGroupId)
                .appendingPathComponent(snapshotFileName)
        )

        for url in candidates {
            if let jsonString = try? String(contentsOf: url, encoding: .utf8),
               !jsonString.isEmpty {
                return jsonString
            }
        }
        return nil
    }

    func loadRecurrenceSeries(id: String) -> WidgetRecurrenceSeriesItem? {
        loadSnapshot().recurrenceSeries?.first { $0.seriesId == id }
    }

    func loadRecurrenceCatalog(activeOnly: Bool = false) -> [WidgetRecurrenceSeriesItem] {
        let catalog = loadSnapshot().recurrenceSeries ?? []
        return activeOnly ? catalog.filter(\.isActive) : catalog
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), snapshot: .empty, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), snapshot: .empty, isPlaceholder: true)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let snapshot = WidgetDataLoader.shared.loadSnapshot()
        let entry = SimpleEntry(date: Date(), snapshot: snapshot, isPlaceholder: false)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

// MARK: - Configurable Recurrence Widget Data

@available(macOS 14.2, *)
struct RecurrenceTodoEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "循环待办")
    static var defaultQuery = RecurrenceTodoEntityQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)"
        )
    }

    init(series: WidgetRecurrenceSeriesItem, now: Date = Date()) {
        id = series.seriesId
        title = series.title
        let nextText = series.nextOccurrenceText(at: now)
        let suffix = series.contextText.isEmpty ? "" : " · \(series.contextText)"
        subtitle = "\(series.recurrenceText) · \(nextText)\(suffix)"
    }
}

@available(macOS 14.2, *)
struct RecurrenceTodoEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RecurrenceTodoEntity] {
        let catalog = WidgetDataLoader.shared.loadRecurrenceCatalog()
        let byId = Dictionary(uniqueKeysWithValues: catalog.map { ($0.seriesId, $0) })
        return identifiers.compactMap { identifier in
            byId[identifier].map { RecurrenceTodoEntity(series: $0) }
        }
    }

    func suggestedEntities() async throws -> [RecurrenceTodoEntity] {
        WidgetDataLoader.shared
            .loadRecurrenceCatalog(activeOnly: true)
            .map { RecurrenceTodoEntity(series: $0) }
    }

    func entities(matching string: String) async throws -> [RecurrenceTodoEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return WidgetDataLoader.shared
            .loadRecurrenceCatalog(activeOnly: true)
            .filter { series in
                needle.isEmpty ||
                    series.title.localizedCaseInsensitiveContains(needle) ||
                    series.recurrenceText.localizedCaseInsensitiveContains(needle) ||
                    series.contextText.localizedCaseInsensitiveContains(needle)
            }
            .map { RecurrenceTodoEntity(series: $0) }
    }
}

@available(macOS 14.2, *)
struct SelectRecurrenceTodoIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择循环待办"
    static var description = IntentDescription("选择一个循环系列固定显示在桌面。")
    static var parameterSummary: some ParameterSummary {
        Summary("显示 \(\.$recurrenceTodo)")
    }

    @Parameter(title: "循环待办")
    var recurrenceTodo: RecurrenceTodoEntity?
}

@available(macOS 14.2, *)
struct RecurrenceWidgetEntry: TimelineEntry {
    let date: Date
    let series: WidgetRecurrenceSeriesItem?
    let configuredSeriesId: String?
    let configuredTitle: String?
    let snapshotUpdatedAt: String
    let isPlaceholder: Bool
}

@available(macOS 14.2, *)
struct RecurrenceWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RecurrenceWidgetEntry {
        RecurrenceWidgetEntry(
            date: Date(),
            series: .preview,
            configuredSeriesId: WidgetRecurrenceSeriesItem.preview.seriesId,
            configuredTitle: WidgetRecurrenceSeriesItem.preview.title,
            snapshotUpdatedAt: "",
            isPlaceholder: true
        )
    }

    func snapshot(
        for configuration: SelectRecurrenceTodoIntent,
        in context: Context
    ) async -> RecurrenceWidgetEntry {
        makeEntry(configuration: configuration, isPreview: context.isPreview)
    }

    func timeline(
        for configuration: SelectRecurrenceTodoIntent,
        in context: Context
    ) async -> Timeline<RecurrenceWidgetEntry> {
        let entry = makeEntry(configuration: configuration, isPreview: false)
        let nextUpdate = Calendar.current.date(
            byAdding: .minute,
            value: 15,
            to: Date()
        ) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func makeEntry(
        configuration: SelectRecurrenceTodoIntent,
        isPreview: Bool
    ) -> RecurrenceWidgetEntry {
        let configured = configuration.recurrenceTodo
        if isPreview && configured == nil {
            return RecurrenceWidgetEntry(
                date: Date(),
                series: .preview,
                configuredSeriesId: WidgetRecurrenceSeriesItem.preview.seriesId,
                configuredTitle: WidgetRecurrenceSeriesItem.preview.title,
                snapshotUpdatedAt: "",
                isPlaceholder: true
            )
        }

        let snapshot = WidgetDataLoader.shared.loadSnapshot()
        let series = configured.flatMap { selected in
            snapshot.recurrenceSeries?.first { $0.seriesId == selected.id }
        }
        return RecurrenceWidgetEntry(
            date: Date(),
            series: series,
            configuredSeriesId: configured?.id,
            configuredTitle: configured?.title,
            snapshotUpdatedAt: snapshot.updatedAt,
            isPlaceholder: false
        )
    }
}

// MARK: - Helper Extensions

extension WidgetSnapshot {
    var isEmpty: Bool {
        countdowns.isEmpty && todos.isEmpty && courses.isEmpty && !focus.isRunning && (habits ?? []).isEmpty
    }

    var deepLinkURL: URL {
        var components = URLComponents()
        components.scheme = "countdowntodo"
        components.host = "habit"
        return components.url ?? URL(string: "countdowntodo://habit")!
    }

    var nearestCountdown: WidgetCountdownItem? {
        countdowns.first
    }

    var incompleteTodoCount: Int {
        todos.filter { !$0.isDone }.count
    }

    var formatUpdatedAt: String {
        guard !updatedAt.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: updatedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm"
            return displayFormatter.string(from: date)
        }
        let formatter2 = ISO8601DateFormatter()
        if let date2 = formatter2.date(from: updatedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm"
            return displayFormatter.string(from: date2)
        }
        return ""
    }
}

extension WidgetCountdownItem {
    var daysLeftText: String {
        if daysLeft == 0 { return "今天" }
        if daysLeft < 0 { return "已过 \(-daysLeft) 天" }
        return "还有 \(daysLeft) 天"
    }
}

extension WidgetFocusState {
    var formattedTodayMinutes: String {
        if todayMinutes < 60 { return "\(todayMinutes)min" }
        let h = todayMinutes / 60
        let m = todayMinutes % 60
        return m > 0 ? "\(h)h \(m)min" : "\(h)h"
    }

    var formattedRemaining: String {
        guard remainingSeconds > 0 else { return "" }
        let m = remainingSeconds / 60
        return "\(m) 分钟"
    }
}

enum RecurrenceOccurrenceState {
    case completed
    case overdue
    case pending
    case future

    var label: String {
        switch self {
        case .completed: return "本期已完成"
        case .overdue: return "本期已逾期"
        case .pending: return "本期待完成"
        case .future: return "等待下一期"
        }
    }

    var symbolName: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .overdue: return "exclamationmark.circle.fill"
        case .pending: return "circle.inset.filled"
        case .future: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .completed: return .green
        case .overdue: return .red
        case .pending: return .accentColor
        case .future: return .secondary
        }
    }
}

struct RecurrenceWidgetPresentation {
    let occurrence: WidgetRecurrenceOccurrenceItem
    let state: RecurrenceOccurrenceState
    let scheduleText: String
    let nodes: [WidgetRecurrenceOccurrenceItem]
}

extension WidgetRecurrenceSeriesItem {
    static let preview = WidgetRecurrenceSeriesItem(
        seriesId: "preview-daily-water",
        title: "每日喝水 2000ml",
        recurrenceType: "daily",
        recurrenceText: "每天",
        customIntervalDays: nil,
        anchorStartMs: Int64(Date().timeIntervalSince1970 * 1000),
        anchorDueMs: Int64(
            Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!
                .timeIntervalSince1970 * 1000
        ),
        recurrenceEndMs: nil,
        isActive: true,
        contextText: "生活",
        completedCount: 12,
        overdueCount: 1,
        elapsedCount: 14,
        totalCount: nil,
        occurrences: previewOccurrences
    )

    private static var previewOccurrences: [WidgetRecurrenceOccurrenceItem] {
        let calendar = Calendar.current
        return (-3...3).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: Date()),
                  let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                  let due = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) else {
                return nil
            }
            return WidgetRecurrenceOccurrenceItem(
                occurrenceId: "preview-\(offset)",
                startAtMs: Int64(start.timeIntervalSince1970 * 1000),
                dueAtMs: Int64(due.timeIntervalSince1970 * 1000),
                isDone: offset < -1,
                isDateOnly: false,
                isProjected: offset > 0
            )
        }
    }

    var deepLinkURL: URL? {
        var components = URLComponents()
        components.scheme = "countdowntodo"
        components.host = "todo"
        components.path = "/recurrence"
        components.queryItems = [URLQueryItem(name: "seriesId", value: seriesId)]
        return components.url
    }

    func nextOccurrenceText(at date: Date) -> String {
        guard let occurrence = orderedOccurrences.first(where: {
            !Calendar.current.startOfDay(for: $0.startDate)
                .isBefore(Calendar.current.startOfDay(for: date))
        }) else {
            return isActive ? "等待下一期" : "循环已结束"
        }
        return shortScheduleText(for: occurrence, at: date, includePrefix: true)
    }

    func presentation(at date: Date) -> RecurrenceWidgetPresentation? {
        let ordered = orderedOccurrences
        guard !ordered.isEmpty else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        let exactToday = ordered.first {
            calendar.isDate($0.startDate, inSameDayAs: date)
        }
        let recentIncomplete = ordered.last { occurrence in
            guard !occurrence.isDone else { return false }
            let startDay = calendar.startOfDay(for: occurrence.startDate)
            guard startDay < today,
                  let visibleUntil = calendar.date(byAdding: .day, value: 2, to: startDay) else {
                return false
            }
            return date < visibleUntil
        }
        let upcoming = ordered.first {
            calendar.startOfDay(for: $0.startDate) > today
        }
        let selected = exactToday ?? recentIncomplete ?? upcoming ?? ordered.last!
        let selectedState = state(of: selected, at: date)
        let selectedIndex = ordered.firstIndex { $0.id == selected.id } ?? 0
        let scheduleOccurrence: WidgetRecurrenceOccurrenceItem
        let scheduleHasNextPrefix: Bool
        if selectedState == .completed,
           let next = ordered.dropFirst(selectedIndex + 1).first {
            scheduleOccurrence = next
            scheduleHasNextPrefix = true
        } else {
            scheduleOccurrence = selected
            scheduleHasNextPrefix = selectedState == .future
        }
        let lowerBound = max(0, min(selectedIndex - 3, ordered.count - 7))
        let upperBound = min(ordered.count, lowerBound + 7)

        return RecurrenceWidgetPresentation(
            occurrence: selected,
            state: isActive ? selectedState : .future,
            scheduleText: shortScheduleText(
                for: scheduleOccurrence,
                at: date,
                includePrefix: scheduleHasNextPrefix
            ),
            nodes: Array(ordered[lowerBound..<upperBound])
        )
    }

    func state(
        of occurrence: WidgetRecurrenceOccurrenceItem,
        at date: Date
    ) -> RecurrenceOccurrenceState {
        if occurrence.isDone { return .completed }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let occurrenceDay = calendar.startOfDay(for: occurrence.startDate)
        if occurrenceDay > today { return .future }

        let effectiveDue: Date
        if occurrence.isDateOnly {
            effectiveDue = calendar.date(byAdding: .day, value: 1, to: occurrenceDay) ?? occurrence.startDate
        } else if let dueDate = occurrence.dueDate {
            effectiveDue = dueDate
        } else {
            effectiveDue = calendar.date(byAdding: .day, value: 1, to: occurrenceDay) ?? occurrence.startDate
        }
        return date >= effectiveDue ? .overdue : .pending
    }

    func nodeLabel(for occurrence: WidgetRecurrenceOccurrenceItem, at date: Date) -> String {
        if Calendar.current.isDate(occurrence.startDate, inSameDayAs: date) {
            return "今天"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: occurrence.startDate)
    }

    private var orderedOccurrences: [WidgetRecurrenceOccurrenceItem] {
        let calendar = Calendar.current
        var byDay: [Date: WidgetRecurrenceOccurrenceItem] = [:]
        for occurrence in occurrences.sorted(by: { $0.startAtMs < $1.startAtMs }) {
            let day = calendar.startOfDay(for: occurrence.startDate)
            if let existing = byDay[day], !existing.isProjected {
                continue
            }
            byDay[day] = occurrence
        }
        return byDay.values.sorted { $0.startAtMs < $1.startAtMs }
    }

    private func shortScheduleText(
        for occurrence: WidgetRecurrenceOccurrenceItem,
        at date: Date,
        includePrefix: Bool
    ) -> String {
        let calendar = Calendar.current
        let displayDate = occurrence.dueDate ?? occurrence.startDate
        let prefix = includePrefix ? "下一期 " : ""
        if occurrence.isDateOnly {
            if calendar.isDate(displayDate, inSameDayAs: date) {
                return "\(prefix)今天内完成"
            }
            return "\(prefix)\(relativeDayText(for: displayDate, at: date))内完成"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: displayDate)
        if calendar.isDate(displayDate, inSameDayAs: date) {
            return "\(prefix)今天 \(time)"
        }
        return "\(prefix)\(relativeDayText(for: displayDate, at: date)) \(time)"
    }

    private func relativeDayText(for target: Date, at date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(target) { return "明天" }
        let formatter = DateFormatter()
        if abs(target.timeIntervalSince(date)) < 7 * 24 * 60 * 60 {
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: target)
    }
}

private extension Date {
    func isBefore(_ other: Date) -> Bool { self < other }
}

// MARK: - Overview Widget

struct CountDownTodoOverviewWidget: Widget {
    let kind: String = "CountDownTodoOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OverviewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日总览")
        .description("查看倒计时、待办和专注状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct OverviewWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        content
            .widgetContainerBackground {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallOverview
        case .systemMedium:
            mediumOverview
        case .systemLarge:
            largeOverview
        default:
            smallOverview
        }
    }

    // MARK: - Small Overview
    private var smallOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("CountDownTodo")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if entry.isPlaceholder || entry.snapshot.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无数据")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                if let cd = entry.snapshot.nearestCountdown {
                    Text(cd.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(cd.daysLeftText)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                HStack {
                    Label("\(entry.snapshot.incompleteTodoCount) 项待办", systemImage: "checklist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Medium Overview
    private var mediumOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("CountDownTodo")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.snapshot.formatUpdatedAt)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if entry.isPlaceholder || entry.snapshot.isEmpty {
                emptyStateView
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Left: Countdown
                    countdownSection

                    Divider()

                    // Right: Focus / Course / Todo
                    rightSection
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    // MARK: - Large Overview
    private var largeOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("CountDownTodo")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.snapshot.formatUpdatedAt)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if entry.isPlaceholder || entry.snapshot.isEmpty {
                emptyStateView
            } else {
                // Countdowns
                if !entry.snapshot.countdowns.isEmpty {
                    GroupBox(label: Label("倒计时", systemImage: "calendar").font(.caption)) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(entry.snapshot.countdowns.prefix(3), id: \.title) { cd in
                                HStack {
                                    Text(cd.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(cd.daysLeftText)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Courses
                if !entry.snapshot.courses.isEmpty {
                    GroupBox(label: Label("今日课程", systemImage: "book").font(.caption)) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(entry.snapshot.courses.prefix(3), id: \.title) { course in
                                HStack {
                                    Text(course.timeText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(course.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(course.location)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Todos
                if !entry.snapshot.todos.isEmpty {
                    GroupBox(label: Label("今日待办", systemImage: "checklist").font(.caption)) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(entry.snapshot.todos.prefix(3), id: \.title) { todo in
                                HStack {
                                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(todo.isDone ? .green : .secondary)
                                        .font(.caption)
                                    Text(todo.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .opacity(todo.isDone ? 0.5 : 1.0)
                                    Spacer()
                                    if !todo.timeText.isEmpty {
                                        Text(todo.timeText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    // MARK: - Shared Components
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("暂无数据")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("添加待办、倒计时或开始专注")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("倒计时", systemImage: "calendar")
                .font(.caption)
                .foregroundColor(.secondary)
            if let cd = entry.snapshot.nearestCountdown {
                Text(cd.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(cd.daysLeftText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            } else {
                Text("暂无倒计时")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rightSection: some View {
        if entry.snapshot.focus.isRunning {
            focusActiveSection
        } else if !entry.snapshot.courses.isEmpty {
            courseSection
        } else {
            todoSection
        }
    }

    private var focusActiveSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("专注中", systemImage: "timer")
                .font(.caption)
                .foregroundColor(.blue)
            Text(entry.snapshot.focus.currentTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            if entry.snapshot.focus.remainingSeconds > 0 {
                Text("剩余 \(entry.snapshot.focus.formattedRemaining)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("课程", systemImage: "book")
                .font(.caption)
                .foregroundColor(.secondary)
            if let course = entry.snapshot.courses.first {
                Text(course.statusText)
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(course.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(course.timeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("今日待办", systemImage: "checklist")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(entry.snapshot.incompleteTodoCount) 项")
                .font(.title3)
                .fontWeight(.bold)
            if let todo = entry.snapshot.todos.first {
                Text(todo.title)
                    .font(.subheadline)
                    .lineLimit(2)
                if !todo.timeText.isEmpty {
                    Text(todo.timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Countdown Widget

struct CountDownTodoCountdownWidget: Widget {
    let kind: String = "CountDownTodoCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CountdownWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("倒数日")
        .description("查看重要倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CountdownWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        content
            .widgetContainerBackground {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallCountdown
        case .systemMedium:
            mediumCountdown
        default:
            smallCountdown
        }
    }

    private var smallCountdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.accentColor)
                Text("倒数日")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if entry.isPlaceholder || entry.snapshot.countdowns.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无倒计时")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let cd = entry.snapshot.nearestCountdown {
                Text(cd.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(cd.daysLeftText)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            Spacer()
        }
        .padding()
    }

    private var mediumCountdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.accentColor)
                Text("重要倒数")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            if entry.isPlaceholder || entry.snapshot.countdowns.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无倒计时")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.snapshot.countdowns.prefix(4), id: \.title) { cd in
                        HStack {
                            Text(cd.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Text(cd.daysLeftText)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(cd.daysLeft == 0 ? .red : .accentColor)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - Todo Widget

struct CountDownTodoTodoWidget: Widget {
    let kind: String = "CountDownTodoTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日待办")
        .description("查看今日待办事项")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodoWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        content
            .widgetContainerBackground {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallTodo
        case .systemMedium:
            mediumTodo
        default:
            smallTodo
        }
    }

    private var smallTodo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.accentColor)
                Text("今日待办")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if entry.isPlaceholder || entry.snapshot.todos.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无待办")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("\(entry.snapshot.incompleteTodoCount) 项")
                    .font(.title)
                    .fontWeight(.bold)
                if let todo = entry.snapshot.todos.first {
                    Text(todo.title)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding()
    }

    private var mediumTodo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.accentColor)
                Text("今日待办 \(entry.snapshot.incompleteTodoCount) 项")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            if entry.isPlaceholder || entry.snapshot.todos.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无待办")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.snapshot.todos.prefix(5), id: \.title) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(todo.isDone ? .green : .secondary)
                                .font(.caption)
                            Text(todo.title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .opacity(todo.isDone ? 0.5 : 1.0)
                            Spacer()
                            if !todo.timeText.isEmpty {
                                Text(todo.timeText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - Course Widget

struct CountDownTodoCourseWidget: Widget {
    let kind: String = "CountDownTodoCourseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CourseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日课程")
        .description("查看今日课程安排")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CourseWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        content
            .widgetContainerBackground {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallCourse
        case .systemMedium:
            mediumCourse
        default:
            smallCourse
        }
    }

    private var smallCourse: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "book")
                    .foregroundColor(.accentColor)
                Text("今日课程")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if entry.isPlaceholder || entry.snapshot.courses.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("今天没课")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let course = entry.snapshot.courses.first {
                Text(course.statusText)
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(course.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(course.timeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var mediumCourse: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book")
                    .foregroundColor(.accentColor)
                Text("今日课程")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            if entry.isPlaceholder || entry.snapshot.courses.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("今天没课")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("可以专注处理待办")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.snapshot.courses.prefix(4), id: \.title) { course in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.timeText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(course.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(course.location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(course.statusText)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - Focus Widget

struct CountDownTodoFocusWidget: Widget {
    let kind: String = "CountDownTodoFocusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FocusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("专注")
        .description("查看专注状态和统计")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FocusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        content
            .widgetContainerBackground {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallFocus
        case .systemMedium:
            mediumFocus
        default:
            smallFocus
        }
    }

    private var smallFocus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.accentColor)
                Text("专注")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if entry.isPlaceholder {
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("专注模式")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if entry.snapshot.focus.isRunning {
                Text("专注中")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(entry.snapshot.focus.currentTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text("剩余 \(entry.snapshot.focus.formattedRemaining)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            } else {
                Text("今日专注")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.snapshot.focus.formattedTodayMinutes)
                    .font(.title)
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding()
    }

    private var mediumFocus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.accentColor)
                Text("专注状态")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            if entry.isPlaceholder {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("专注模式")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if entry.snapshot.focus.isRunning {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("专注中")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(entry.snapshot.focus.currentTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("剩余")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(entry.snapshot.focus.formattedRemaining)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
                Spacer()
                Text("今日已专注 \(entry.snapshot.focus.formattedTodayMinutes)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("今日专注")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.snapshot.focus.formattedTodayMinutes)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        Spacer()
                    }
                }
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - Habit Widget

struct CountDownTodoHabitWidget: Widget {
    let kind: String = "CountDownTodoHabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HabitWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日习惯")
        .description("查看今日习惯打卡进度")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HabitWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SimpleEntry

    var body: some View {
        content
            .widgetContainerBackground {
                Color.clear
            }
            .widgetURL(entry.snapshot.deepLinkURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            mediumHabit
        default:
            smallHabit
        }
    }

    private var displayedHabits: [WidgetHabitItem] {
        let all = entry.snapshot.habits ?? []
        return all.sorted { lhs, rhs in
            if lhs.goalMet != rhs.goalMet { return !lhs.goalMet }
            return lhs.title < rhs.title
        }
    }

    private var smallHabit: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal")
                    .foregroundColor(.accentColor)
                Text("今日习惯")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            Spacer()

            if entry.isPlaceholder || displayedHabits.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无习惯")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayedHabits.prefix(3), id: \.id) { habit in
                        habitRow(habit, compact: true)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private var mediumHabit: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.seal")
                    .foregroundColor(.accentColor)
                Text("今日习惯")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(displayedHabits.filter(\.goalMet).count)/\(displayedHabits.count) 达标")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if entry.isPlaceholder || displayedHabits.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.seal")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无习惯")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("在应用内创建习惯后展示进度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(displayedHabits.prefix(6), id: \.id) { habit in
                        habitRow(habit, compact: false)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    @ViewBuilder
    private func habitRow(_ habit: WidgetHabitItem, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text(habit.icon.isEmpty ? "🎯" : habit.icon)
                .font(compact ? .caption : .subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !compact {
                    progressBar(habit)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(habit.progressText)
                    .font(compact ? .system(size: 10) : .caption)
                    .foregroundColor(habit.goalMet ? .green : .secondary)
                    .lineLimit(1)
                quickCheckInButton(habit)
            }
        }
    }

    @ViewBuilder
    private func quickCheckInButton(_ habit: WidgetHabitItem) -> some View {
        if habit.goalMet {
            Text("✅")
                .font(.system(size: 10))
                .foregroundColor(.green)
        } else if #available(macOSApplicationExtension 14.0, *) {
            Button(intent: habit.quickCheckInIntent) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        } else {
            Text("○")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func progressBar(_ habit: WidgetHabitItem) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(habit.goalMet ? Color.green : Color.accentColor)
                    .frame(width: max(0, geo.size.width * CGFloat(habit.ratio)))
            }
        }
        .frame(height: 5)
    }
}

extension WidgetHabitItem {
    var ratio: Double {
        guard targetValue > 0 else { return 0 }
        return min(1, currentValue / targetValue)
    }
}

// MARK: - Habit Quick Check-In Intent

@available(macOS 14.0, *)
struct HabitQuickCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "习惯快捷打卡"
    static var description = IntentDescription("从习惯小组件快速打卡一次。")

    @Parameter(title: "习惯 ID")
    var habitId: String

    @Parameter(title: "快捷值")
    var quickValue: Double?

    init() {}

    init(habitId: String, quickValue: Double?) {
        self.habitId = habitId
        self.quickValue = quickValue
    }

    func perform() async throws -> some IntentResult {
        var components = URLComponents()
        components.scheme = "countdowntodo"
        components.host = "habitcheckin"
        components.queryItems = [
            URLQueryItem(name: "habitId", value: habitId)
        ]
        if let quickValue {
            components.queryItems?.append(
                URLQueryItem(name: "value", value: "\(quickValue)")
            )
        }
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

extension WidgetHabitItem {
    @available(macOS 14.0, *)
    var quickCheckInIntent: HabitQuickCheckInIntent {
        HabitQuickCheckInIntent(
            habitId: habitId,
            quickValue: quickValues.first
        )
    }
}

// MARK: - Configurable Recurrence Widget

@available(macOS 14.2, *)
struct CountDownTodoRecurrenceWidget: Widget {
    let kind: String = "CountDownTodoRecurrenceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectRecurrenceTodoIntent.self,
            provider: RecurrenceWidgetProvider()
        ) { entry in
            RecurrenceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("循环待办")
        .description("选择一个循环待办，持续查看本期状态与完成进度")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@available(macOS 14.2, *)
struct RecurrenceWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecurrenceWidgetEntry

    var body: some View {
        Group {
            if let series = entry.series {
                seriesContent(series)
            } else if entry.configuredSeriesId == nil {
                configurationEmptyState
            } else {
                unavailableState
            }
        }
        .widgetContainerBackground {
            Color.clear
        }
        .widgetURL(entry.series?.deepLinkURL)
    }

    @ViewBuilder
    private func seriesContent(_ series: WidgetRecurrenceSeriesItem) -> some View {
        if !series.isActive {
            endedState(series)
        } else if let presentation = series.presentation(at: entry.date) {
            switch family {
            case .systemMedium:
                mediumContent(series, presentation: presentation)
            default:
                smallContent(series, presentation: presentation)
            }
        } else {
            unavailableState
        }
    }

    private func smallContent(
        _ series: WidgetRecurrenceSeriesItem,
        presentation: RecurrenceWidgetPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            recurrenceHeader(series)

            Spacer(minLength: 1)

            Text(series.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            VStack(alignment: .leading, spacing: 3) {
                Label(
                    presentation.state.label,
                    systemImage: presentation.state.symbolName
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(presentation.state.color)

                Text(presentation.scheduleText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 1)

            Text(summaryText(series))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(series.title)，\(presentation.state.label)，\(presentation.scheduleText)，\(summaryText(series))"
        )
    }

    private func mediumContent(
        _ series: WidgetRecurrenceSeriesItem,
        presentation: RecurrenceWidgetPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            recurrenceHeader(series)

            Text(series.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            HStack(spacing: 10) {
                Label(
                    presentation.state.label,
                    systemImage: presentation.state.symbolName
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(presentation.state.color)

                Text(presentation.scheduleText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                Text(summaryText(series))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            recurrenceTimeline(series, presentation: presentation)

            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(series.title)，\(presentation.state.label)，\(presentation.scheduleText)，\(summaryText(series))"
        )
    }

    private func recurrenceHeader(_ series: WidgetRecurrenceSeriesItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "repeat.circle.fill")
                .foregroundColor(.accentColor)
            Text("循环待办")
                .font(.caption)
                .fontWeight(.semibold)
            Spacer()
            if isSnapshotStale {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .help("数据可能不是最新")
            }
            Text(series.recurrenceText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func recurrenceTimeline(
        _ series: WidgetRecurrenceSeriesItem,
        presentation: RecurrenceWidgetPresentation
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, occurrence in
                if index > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(height: 1)
                }
                recurrenceNode(
                    series,
                    occurrence: occurrence,
                    isSelected: occurrence.id == presentation.occurrence.id
                )
            }
        }
    }

    private func recurrenceNode(
        _ series: WidgetRecurrenceSeriesItem,
        occurrence: WidgetRecurrenceOccurrenceItem,
        isSelected: Bool
    ) -> some View {
        let state = series.state(of: occurrence, at: entry.date)
        return VStack(spacing: 3) {
            ZStack {
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 3)
                        .frame(width: 21, height: 21)
                }
                Image(systemName: state.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(state.color)
            }
            .frame(height: 22)

            Text(series.nodeLabel(for: occurrence, at: entry.date))
                .font(.system(size: 8.5, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: 36)
        .accessibilityLabel(
            "\(series.nodeLabel(for: occurrence, at: entry.date))，\(state.label)"
        )
    }

    private var configurationEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "repeat.circle")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("选择循环待办")
                .font(.headline)
            Text("右键编辑小组件并选择要提醒的循环系列")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var unavailableState: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(entry.configuredTitle ?? "待办不可用")
                .font(.headline)
                .lineLimit(2)
            Text("该循环可能已删除或无法访问，请重新选择")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func endedState(_ series: WidgetRecurrenceSeriesItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            recurrenceHeader(series)
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(series.title)
                .font(.headline)
                .lineLimit(2)
            Text("循环已结束")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(summaryText(series)) · 右键可重新选择")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func summaryText(_ series: WidgetRecurrenceSeriesItem) -> String {
        let completion: String
        if let totalCount = series.totalCount {
            completion = "已完成 \(series.completedCount)/\(totalCount) 期"
        } else {
            completion = "已完成 \(series.completedCount) 期"
        }
        if series.overdueCount > 0 {
            return "\(completion) · 逾期 \(series.overdueCount) 期"
        }
        return completion
    }

    private var isSnapshotStale: Bool {
        guard !entry.snapshotUpdatedAt.isEmpty else { return false }
        let preciseFormatter = ISO8601DateFormatter()
        preciseFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAt = preciseFormatter.date(from: entry.snapshotUpdatedAt) ??
            ISO8601DateFormatter().date(from: entry.snapshotUpdatedAt)
        guard let updatedAt else { return false }
        return entry.date.timeIntervalSince(updatedAt) > 24 * 60 * 60
    }
}

// MARK: - Widget Bundle

@available(macOS 14.2, *)
@main
struct CountDownTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        // macOS 桌面小组件画廊按扩展显示，WidgetBundle 编译期上限为 10 个
        // （Xcode 14+）。专注状态已并入总览小组件，因此专注条目让位给
        // 循环待办与习惯条目。
        CountDownTodoOverviewWidget()
        CountDownTodoCountdownWidget()
        CountDownTodoTodoWidget()
        CountDownTodoCourseWidget()
        CountDownTodoHabitWidget()
        CountDownTodoRecurrenceWidget()
    }
}

// MARK: - Previews

#if DEBUG
struct CountDownTodoWidget_Previews: PreviewProvider {
    static var previews: some View {
        let sampleSnapshot = WidgetSnapshot(
            updatedAt: "2026-06-08T10:40:00",
            countdowns: [
                WidgetCountdownItem(title: "四级考试", daysLeft: 5, dateText: "2026-06-13", subtitle: "考试"),
                WidgetCountdownItem(title: "计组期末", daysLeft: 14, dateText: "2026-06-22", subtitle: "考试"),
            ],
            todos: [
                WidgetTodoItem(title: "实验报告", timeText: "今天 18:00", priority: 2, isDone: false),
                WidgetTodoItem(title: "编译原理复习", timeText: "明天", priority: 1, isDone: false),
                WidgetTodoItem(title: "提交 PR", timeText: "", priority: 0, isDone: true),
            ],
            courses: [
                WidgetCourseItem(title: "计算机组成原理实验", timeText: "19:00 - 21:30", location: "电气楼513", statusText: "下一节课"),
            ],
            focus: WidgetFocusState(isRunning: false, currentTitle: "", todayMinutes: 80, sessionMinutes: 0, remainingSeconds: 0),
            recurrenceSeries: [WidgetRecurrenceSeriesItem.preview],
            habits: [
                WidgetHabitItem(
                    habitId: "preview-water",
                    title: "喝水",
                    icon: "💧",
                    sourceType: "quantityCheckIn",
                    currentValue: 680,
                    targetValue: 2000,
                    unit: "ml",
                    goalMet: false,
                    quickValues: [250, 500, 1000]
                ),
                WidgetHabitItem(
                    habitId: "preview-run",
                    title: "跑步",
                    icon: "🏃",
                    sourceType: "quantityCheckIn",
                    currentValue: 5,
                    targetValue: 5,
                    unit: "km",
                    goalMet: true,
                    quickValues: [1, 2, 5]
                ),
                WidgetHabitItem(
                    habitId: "preview-read",
                    title: "读书",
                    icon: "📖",
                    sourceType: "recurringTodo",
                    currentValue: 0,
                    targetValue: 1,
                    unit: "",
                    goalMet: false,
                    quickValues: []
                ),
            ]
        )
        let entry = SimpleEntry(date: Date(), snapshot: sampleSnapshot, isPlaceholder: false)

        Group {
            OverviewWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            OverviewWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            OverviewWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
            HabitWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("今日习惯 · 小号")
            HabitWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("今日习惯 · 中号")
            if #available(macOS 14.2, *) {
                RecurrenceWidgetEntryView(
                    entry: RecurrenceWidgetEntry(
                        date: Date(),
                        series: .preview,
                        configuredSeriesId: WidgetRecurrenceSeriesItem.preview.seriesId,
                        configuredTitle: WidgetRecurrenceSeriesItem.preview.title,
                        snapshotUpdatedAt: "2026-07-30T09:00:00.000+08:00",
                        isPlaceholder: false
                    )
                )
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("循环待办 · 小号")
                RecurrenceWidgetEntryView(
                    entry: RecurrenceWidgetEntry(
                        date: Date(),
                        series: .preview,
                        configuredSeriesId: WidgetRecurrenceSeriesItem.preview.seriesId,
                        configuredTitle: WidgetRecurrenceSeriesItem.preview.title,
                        snapshotUpdatedAt: "2026-07-30T09:00:00.000+08:00",
                        isPlaceholder: false
                    )
                )
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("循环待办 · 中号")
            }
        }
    }
}
#endif
