import WidgetKit
import SwiftUI

// MARK: - 타임라인

struct CalendarEntry: TimelineEntry {
    let date: Date
    let events: [CalendarEvent]
}

struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: Date(), events: CalendarEvent.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        let events = EventRepository.shared.load()
        // 위젯 고르는 화면에서는 일정이 없어도 예시를 보여줌
        let shown = (context.isPreview && events.isEmpty) ? CalendarEvent.samples : events
        completion(CalendarEntry(date: Date(), events: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let events = EventRepository.shared.load()

        // 자정(날짜 바뀜) 또는 다음 일정 시작/종료 중 빠른 시각에 다시 그림
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let nextMidnight = cal.startOfDay(for: tomorrow)
        let nextChange = events.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
        let refresh = min(nextMidnight, nextChange ?? nextMidnight)

        completion(Timeline(entries: [CalendarEntry(date: now, events: events)],
                            policy: .after(refresh)))
    }
}

// MARK: - 위젯 묶음

@main
struct MyCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonthCalendarWidget()
        UpcomingEventsWidget()
        LockScreenCalendarWidget()
    }
}

struct MonthCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MonthCalendarWidget", provider: CalendarProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(Color(UIColor.systemBackground), for: .widget)
        }
        .configurationDisplayName("월간 달력")
        .description("이번 달 달력과 오늘 일정을 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UpcomingEventsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingEventsWidget", provider: CalendarProvider()) { entry in
            UpcomingWidgetView(entry: entry)
                .containerBackground(Color(UIColor.systemBackground), for: .widget)
        }
        .configurationDisplayName("다가오는 일정")
        .description("오늘 날짜와 곧 있을 일정을 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LockScreenCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreenCalendarWidget", provider: CalendarProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("다음 일정")
        .description("잠금 화면에 다음 일정을 보여줘요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - 월간 달력 위젯

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        switch family {
        case .systemSmall:
            MonthGridView(month: entry.date, events: entry.events, fontSize: 10)
                .widgetURL(DeepLink.url(for: entry.date))
        case .systemMedium:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TodayHeader(date: entry.date)
                    let today = entry.events.occurring(on: entry.date)
                    if today.isEmpty {
                        Text("오늘 일정 없음").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(today.prefix(2)) { EventLine(event: $0, compact: true) }
                        if today.count > 2 {
                            Text("외 \(today.count - 2)개").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 110, alignment: .leading)
                MonthGridView(month: entry.date, events: entry.events, fontSize: 9, linkable: true)
            }
            .widgetURL(DeepLink.url(for: entry.date))
        default:
            VStack(spacing: 8) {
                MonthGridView(month: entry.date, events: entry.events, fontSize: 13, linkable: true)
                Divider()
                let today = entry.events.occurring(on: entry.date)
                VStack(alignment: .leading, spacing: 5) {
                    if today.isEmpty {
                        Text("오늘 일정 없음").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(today.prefix(3)) { EventLine(event: $0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .widgetURL(DeepLink.url(for: entry.date))
        }
    }
}

struct MonthGridView: View {
    let month: Date
    let events: [CalendarEvent]
    var fontSize: CGFloat = 11
    var linkable: Bool = false

    private let cal = Calendar.current

    var body: some View {
        let cells = MonthGrid.cells(for: month)
        let rows = cells.count / 7
        VStack(spacing: 1) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.system(size: fontSize + 2, weight: .bold))
                    .foregroundStyle(.red)
                Spacer()
            }
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        cell(cells[r * 7 + c])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ date: Date?) -> some View {
        if let date {
            let isToday = cal.isDateInToday(date)
            let first = events.occurring(on: date).first
            let size = fontSize * 1.65
            let content = Text("\(cal.component(.day, from: date))")
                .font(.system(size: fontSize, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : (MonthGrid.isSunday(date) ? Color.red.opacity(0.75) : Color.primary))
                .frame(width: size, height: size)
                .background(Circle().fill(isToday ? Color.red : Color.clear))
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(first?.color ?? .clear)
                        .frame(width: 3, height: 3)
                        .offset(y: 2.5)
                        .opacity(isToday ? 0 : 1)
                }
            if linkable, let url = DeepLink.url(for: date) {
                Link(destination: url) { content }
            } else {
                content
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - 다가오는 일정 위젯

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        let list = entry.events.upcoming(from: entry.date, limit: family == .systemSmall ? 2 : 4)
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    TodayHeader(date: entry.date)
                    if list.isEmpty {
                        Text("예정된 일정 없음").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(list) { EventLine(event: $0, showDay: true, compact: true) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    TodayHeader(date: entry.date)
                        .frame(width: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 7) {
                        if list.isEmpty {
                            Text("예정된 일정 없음").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(list) { EventLine(event: $0, showDay: true) }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .widgetURL(DeepLink.url(for: entry.date))
    }
}

// MARK: - 잠금 화면 위젯

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        let next = entry.events.upcoming(from: entry.date, limit: 2)
        switch family {
        case .accessoryInline:
            if let n = next.first {
                Text("\(DayLabel.relative(n.start)) \(n.timeText) \(n.title)")
            } else {
                Text("예정된 일정 없음")
            }
        case .accessoryCircular:
            let cal = Calendar.current
            let count = entry.events.occurring(on: entry.date).count
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Text(entry.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10, weight: .semibold))
                        .widgetAccentable()
                    Text("\(cal.component(.day, from: entry.date))")
                        .font(.system(size: 20, weight: .bold))
                    if count > 0 {
                        Text("\(count)개").font(.system(size: 9))
                    }
                }
            }
            .widgetURL(DeepLink.url(for: entry.date))
        default:
            VStack(alignment: .leading, spacing: 1) {
                if let n = next.first {
                    Text("\(DayLabel.relative(n.start)) · \(n.timeText)")
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(n.title).font(.headline).lineLimit(1)
                    if next.count > 1 {
                        Text("다음: \(next[1].title)").font(.caption).lineLimit(1).opacity(0.7)
                    }
                } else {
                    Text(entry.date.formatted(.dateTime.month().day().weekday(.short)))
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text("예정된 일정 없음").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.url(for: next.first?.start ?? entry.date))
        }
    }
}

// MARK: - 공통 조각

struct TodayHeader: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 34, weight: .light))
        }
    }
}

struct EventLine: View {
    let event: CalendarEvent
    var showDay: Bool = false
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                Text(showDay && !Calendar.current.isDateInToday(event.start)
                     ? "\(DayLabel.relative(event.start)) · \(event.timeText)"
                     : event.timeText)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
