import WidgetKit
import SwiftUI

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

    static let empty = WidgetSnapshot(
        updatedAt: "",
        countdowns: [],
        todos: [],
        courses: [],
        focus: WidgetFocusState.empty
    )
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

    static let empty = WidgetTodoItem(title: "", timeText: "", priority: 0, isDone: false)
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

    func loadSnapshot() -> WidgetSnapshot {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let jsonString = userDefaults.string(forKey: key) else {
            return .empty
        }

        guard let data = jsonString.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }

        return snapshot
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

// MARK: - Helper Extensions

extension WidgetSnapshot {
    var isEmpty: Bool {
        countdowns.isEmpty && todos.isEmpty && courses.isEmpty && !focus.isRunning
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

// MARK: - Widget Bundle

@main
struct CountDownTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CountDownTodoOverviewWidget()
        CountDownTodoCountdownWidget()
        CountDownTodoTodoWidget()
        CountDownTodoCourseWidget()
        CountDownTodoFocusWidget()
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
            focus: WidgetFocusState(isRunning: false, currentTitle: "", todayMinutes: 80, sessionMinutes: 0, remainingSeconds: 0)
        )
        let entry = SimpleEntry(date: Date(), snapshot: sampleSnapshot, isPlaceholder: false)

        Group {
            OverviewWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            OverviewWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            OverviewWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
