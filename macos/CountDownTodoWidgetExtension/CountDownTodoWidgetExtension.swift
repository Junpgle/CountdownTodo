import WidgetKit
import SwiftUI

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

struct WidgetSnapshot: Codable {
    let todayTodoCount: Int
    let nextTodoTitle: String
    let nextTodoDueText: String
    let nearestCountdownTitle: String
    let nearestCountdownDaysText: String
    let pomodoroStateText: String
    let pomodoroLeftText: String
    let widgetMode: String
    let updatedAt: String

    static let empty = WidgetSnapshot(
        todayTodoCount: 0,
        nextTodoTitle: "",
        nextTodoDueText: "",
        nearestCountdownTitle: "",
        nearestCountdownDaysText: "",
        pomodoroStateText: "",
        pomodoroLeftText: "",
        widgetMode: "todo",
        updatedAt: ""
    )
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), snapshot: loadSnapshot())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = SimpleEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadSnapshot() -> WidgetSnapshot {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.mathquiz.junpgle.countdowntodo"
        ) else {
            return .empty
        }

        let fileURL = containerURL.appendingPathComponent("widget_snapshot.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }

        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }

        return snapshot
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct CountDownTodoWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

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
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    // MARK: - Small Widget
    private var smallView: some View {
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

            if entry.snapshot.nearestCountdownTitle.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无倒计时")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(entry.snapshot.nearestCountdownTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text(entry.snapshot.nearestCountdownDaysText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Medium Widget
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("CountDownTodo")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if !entry.snapshot.updatedAt.isEmpty {
                    Text(formatUpdatedAt(entry.snapshot.updatedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("倒计时", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if entry.snapshot.nearestCountdownTitle.isEmpty {
                        Text("暂无倒计时")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(entry.snapshot.nearestCountdownTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(entry.snapshot.nearestCountdownDaysText)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Label("今日待办", systemImage: "checklist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(entry.snapshot.todayTodoCount) 项")
                        .font(.title3)
                        .fontWeight(.bold)
                    if !entry.snapshot.nextTodoTitle.isEmpty {
                        Text(entry.snapshot.nextTodoTitle)
                            .font(.subheadline)
                            .lineLimit(2)
                        if !entry.snapshot.nextTodoDueText.isEmpty {
                            Text(entry.snapshot.nextTodoDueText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("暂无待办")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    // MARK: - Large Widget
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text("CountDownTodo")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if !entry.snapshot.updatedAt.isEmpty {
                    Text(formatUpdatedAt(entry.snapshot.updatedAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            GroupBox(label: Label("今日待办", systemImage: "checklist").font(.caption)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(entry.snapshot.todayTodoCount) 项待办")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    if !entry.snapshot.nextTodoTitle.isEmpty {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                            Text(entry.snapshot.nextTodoTitle)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            if !entry.snapshot.nextTodoDueText.isEmpty {
                                Text(entry.snapshot.nextTodoDueText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("暂无待办")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox(label: Label("倒计时", systemImage: "calendar").font(.caption)) {
                if entry.snapshot.nearestCountdownTitle.isEmpty {
                    Text("暂无倒计时")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    HStack {
                        Text(entry.snapshot.nearestCountdownTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(entry.snapshot.nearestCountdownDaysText)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.vertical, 4)
                }
            }

            GroupBox(label: Label("专注", systemImage: "timer").font(.caption)) {
                if entry.snapshot.pomodoroStateText.isEmpty {
                    Text("今日暂无专注记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    Text(entry.snapshot.pomodoroStateText)
                        .font(.subheadline)
                        .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private func formatUpdatedAt(_ dateString: String) -> String {
        guard !dateString.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm"
            return displayFormatter.string(from: date)
        }
        let formatter2 = ISO8601DateFormatter()
        if let date2 = formatter2.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm"
            return displayFormatter.string(from: date2)
        }
        return ""
    }
}

@main
struct CountDownTodoWidgetExtension: Widget {
    let kind: String = "CountDownTodoWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CountDownTodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("CountDownTodo")
        .description("查看倒计时、待办和专注状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#if DEBUG
struct CountDownTodoWidgetExtension_Previews: PreviewProvider {
    static var previews: some View {
        let sampleSnapshot = WidgetSnapshot(
            todayTodoCount: 3,
            nextTodoTitle: "完成报告",
            nextTodoDueText: "今天 18:00",
            nearestCountdownTitle: "生日",
            nearestCountdownDaysText: "还有 3 天",
            pomodoroStateText: "今日总专注: 45 分钟",
            pomodoroLeftText: "",
            widgetMode: "todo",
            updatedAt: "2026-06-07T10:30:00"
        )
        let entry = SimpleEntry(date: Date(), snapshot: sampleSnapshot)

        Group {
            CountDownTodoWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            CountDownTodoWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            CountDownTodoWidgetEntryView(entry: entry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
#endif
