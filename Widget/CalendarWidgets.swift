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
        let shown = (context.isPreview && events.isEmpty) ? CalendarEvent.samples : events
        completion(CalendarEntry(date: Date(), events: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let cal = Calendar.kr
        let now = Date()
        let events = EventRepository.shared.load()

        // 자정 또는 오늘 남은 일정의 시작·종료 시각에 다시 그림
        let today = cal.startOfDay(for: now)
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86400)
        let todays = events.occurrences(in: DateInterval(start: today, end: nextMidnight), cal: cal)
        let changes = todays.flatMap { o -> [Date] in
            var list = [o.start]
            if let e = o.end { list.append(e) } else { list.append(o.start.addingTimeInterval(30 * 60)) }
            return list
        }
        let nextChange = changes.filter { $0 > now }.min()
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
                .environment(\.locale, koLocale)
                .containerBackground(Theme.bg, for: .widget)
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
                .environment(\.locale, koLocale)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("다가오는 일정")
        .description("오늘 할 일과 곧 있을 일정을 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LockScreenCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreenCalendarWidget", provider: CalendarProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .environment(\.locale, koLocale)
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

    private let cal = Calendar.kr

    var body: some View {
        let days = MonthGrid.days(for: entry.date, cal: cal)
        let map = entry.events.byDay(in: MonthGrid.range(of: days, cal: cal), cal: cal)
        let today = cal.startOfDay(for: entry.date)

        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 2) {
                monthTitle(size: 12)
                WidgetMonthGrid(month: entry.date, days: days, byDay: map,
                                fontSize: 10, showChips: false, linkable: false)
            }
            .widgetURL(DeepLink.url(for: entry.date))

        case .systemMedium:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    TodayHeader(date: entry.date)
                    let items = map[today] ?? []
                    if items.isEmpty {
                        Text("오늘 일정 없음")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(items.prefix(3)) { EventLine(occurrence: $0, compact: true) }
                        if items.count > 3 {
                            Text(verbatim: "외 \(items.count - 3)개")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 108, alignment: .leading)

                WidgetMonthGrid(month: entry.date, days: days, byDay: map,
                                fontSize: 9, showChips: false, linkable: true)
            }
            .widgetURL(DeepLink.url(for: entry.date))

        default:
            VStack(alignment: .leading, spacing: 4) {
                monthTitle(size: 16)
                WidgetMonthGrid(month: entry.date, days: days, byDay: map,
                                fontSize: 12, showChips: true, linkable: true)
            }
            .widgetURL(DeepLink.url(for: entry.date))
        }
    }

    private func monthTitle(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "\(cal.component(.month, from: entry.date))월")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
            Text(verbatim: "\(cal.component(.year, from: entry.date))년")
                .font(.system(size: size - 3, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
    }
}

struct WidgetMonthGrid: View {
    let month: Date
    let days: [Date]
    let byDay: [Date: [Occurrence]]
    let fontSize: CGFloat
    let showChips: Bool
    let linkable: Bool

    private let cal = Calendar.kr

    var body: some View {
        GeometryReader { geo in
            let rows = max(1, days.count / 7)
            let headerH = fontSize + 5
            let cellW = geo.size.width / 7
            let cellH = max(1, (geo.size.height - headerH) / CGFloat(rows))
            let chipFont = max(7, fontSize - 4)
            let maxChips = showChips ? max(0, Int((cellH - fontSize - 6) / (chipFont + 5))) : 0

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(MonthGrid.weekdaySymbols.enumerated()), id: \.offset) { i, s in
                        Text(s)
                            .font(.system(size: fontSize - 2, weight: .semibold))
                            .foregroundStyle(i >= 5 ? Theme.weekendText : Color(white: 0.8))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: headerH)

                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            let day = days[r * 7 + c]
                            linked(day) {
                                WidgetDayCell(day: day,
                                              inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                                              isToday: cal.isDate(day, inSameDayAs: month),
                                              marks: KoreanHolidays.marks(for: day, cal: cal),
                                              occurrences: byDay[day] ?? [],
                                              fontSize: fontSize,
                                              chipFont: chipFont,
                                              maxChips: maxChips)
                            }
                            .frame(width: cellW, height: cellH)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linked<Content: View>(_ day: Date, @ViewBuilder content: () -> Content) -> some View {
        if linkable, let url = DeepLink.url(for: day) {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }
}

struct WidgetDayCell: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let marks: [DayMark]
    let occurrences: [Occurrence]
    let fontSize: CGFloat
    let chipFont: CGFloat
    let maxChips: Int

    var body: some View {
        let isHoliday = marks.contains { $0.isHoliday }
        let numberColor: Color = isHoliday ? Theme.holiday
            : (isToday ? .black : (MonthGrid.isWeekend(day) ? Theme.weekendText : .white))

        let markChips: [ChipItem] = marks.map { m in
            ChipItem(id: "m-" + m.name, title: m.name,
                     color: m.isHoliday ? Theme.holiday : Color(white: 0.5),
                     filled: m.isHoliday)
        }
        let eventChips: [ChipItem] = occurrences.map { o in
            ChipItem(id: o.id, title: o.title, color: o.color, filled: o.isAllDay)
        }
        let chips = markChips + eventChips

        VStack(spacing: 1) {
            Text(verbatim: "\(Calendar.kr.component(.day, from: day))")
                .font(.system(size: fontSize, weight: isToday ? .bold : .medium))
                .foregroundStyle(numberColor)
                .padding(.top, 2)

            if maxChips > 0 {
                VStack(spacing: 1) {
                    ForEach(chips.prefix(maxChips)) { chip in
                        ChipView(chip: chip, onLight: isToday, fontSize: chipFont)
                    }
                }
                .padding(.horizontal, 1)
            } else if let first = occurrences.first {
                Rectangle()
                    .fill(isToday ? Color.black.opacity(0.7) : first.color)
                    .frame(width: 4, height: 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isToday ? Color.white : Color.clear)
        .opacity(inMonth ? 1 : 0.35)
    }
}

// MARK: - 다가오는 일정 위젯

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    var body: some View {
        let small = family == .systemSmall
        let list = entry.events.upcoming(from: entry.date, limit: small ? 3 : 4)

        Group {
            if small {
                VStack(alignment: .leading, spacing: 5) {
                    TodayHeader(date: entry.date)
                    if list.isEmpty {
                        Text("예정된 일정 없음")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(list) { EventLine(occurrence: $0, showDay: true, compact: true) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    TodayHeader(date: entry.date)
                        .frame(width: 78, alignment: .leading)
                    VStack(alignment: .leading, spacing: 7) {
                        if list.isEmpty {
                            Text("예정된 일정 없음")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            ForEach(list) { EventLine(occurrence: $0, showDay: true) }
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
                Text(verbatim: "\(DayLabel.relative(n.start)) \(n.timeLabel) \(n.title)")
            } else {
                Text("예정된 일정 없음")
            }

        case .accessoryCircular:
            let count = entry.events.occurrences(on: entry.date).count
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Text(KFmt.string(entry.date, "E"))
                        .font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                    Text(verbatim: "\(Calendar.kr.component(.day, from: entry.date))")
                        .font(.system(size: 20, weight: .bold))
                    if count > 0 {
                        Text(verbatim: "\(count)개")
                            .font(.system(size: 9))
                    }
                }
            }
            .widgetURL(DeepLink.url(for: entry.date))

        default:
            VStack(alignment: .leading, spacing: 1) {
                if let n = next.first {
                    Text(verbatim: "\(DayLabel.relative(n.start)) · \(n.timeLabel)")
                        .font(.system(size: 12, weight: .semibold))
                        .widgetAccentable()
                    Text(n.title)
                        .font(.headline)
                        .lineLimit(1)
                    if next.count > 1 {
                        Text(verbatim: "다음: \(next[1].title)")
                            .font(.caption)
                            .lineLimit(1)
                            .opacity(0.7)
                    }
                } else {
                    Text(KFmt.monthDay(entry.date))
                        .font(.system(size: 12, weight: .semibold))
                        .widgetAccentable()
                    Text("예정된 일정 없음")
                        .font(.headline)
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
            Text(KFmt.string(date, "M월 EEEE"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(verbatim: "\(Calendar.kr.component(.day, from: date))")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
        }
    }
}

struct EventLine: View {
    let occurrence: Occurrence
    var showDay: Bool = false
    var compact: Bool = false

    var body: some View {
        let o = occurrence
        let dayPrefix = (showDay && !Calendar.kr.isDateInToday(o.start) && o.start > Date())
            ? DayLabel.relative(o.start) + " · " : ""
        HStack(spacing: 6) {
            Rectangle()
                .fill(o.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(o.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(dayPrefix + o.timeLabel)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
