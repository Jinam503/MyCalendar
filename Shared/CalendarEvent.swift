import Foundation
import SwiftUI

// MARK: - 일정 모델

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var colorIndex: Int = 0
    var notes: String = ""

    var color: Color { EventPalette.color(colorIndex) }

    /// "하루 종일" 또는 "오후 3:00"
    var timeText: String {
        isAllDay ? "하루 종일" : start.formatted(date: .omitted, time: .shortened)
    }

    /// "하루 종일" 또는 "오후 3:00 – 오후 4:00"
    var timeRangeText: String {
        if isAllDay { return "하루 종일" }
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        return "\(s) – \(e)"
    }

    static var samples: [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int) -> Date {
            cal.date(byAdding: DateComponents(day: dayOffset, hour: hour), to: today)!
        }
        return [
            CalendarEvent(title: "팀 회의", start: at(0, 10), end: at(0, 11), colorIndex: 0),
            CalendarEvent(title: "점심 약속", start: at(0, 12), end: at(0, 13), colorIndex: 3),
            CalendarEvent(title: "운동", start: at(1, 19), end: at(1, 20), colorIndex: 2),
            CalendarEvent(title: "생일 🎂", start: at(3, 0), end: at(4, 0).addingTimeInterval(-1), isAllDay: true, colorIndex: 5),
        ]
    }
}

enum EventPalette {
    static let colors: [Color] = [.blue, .red, .orange, .green, .purple, .pink, .teal]
    static func color(_ i: Int) -> Color {
        let n = colors.count
        return colors[((i % n) + n) % n]
    }
}

// MARK: - 날짜별 조회

extension Array where Element == CalendarEvent {
    /// 해당 날짜에 걸쳐 있는 일정 (하루 종일 일정 먼저, 그다음 시작 시간 순)
    func occurring(on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return filter { e in
            e.start < dayEnd && (e.end > dayStart || e.start >= dayStart)
        }
        .sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.start < b.start
        }
    }

    /// 아직 끝나지 않은 일정을 시작 순으로
    func upcoming(from now: Date, limit: Int) -> [CalendarEvent] {
        Array(filter { $0.end > now }.sorted { $0.start < $1.start }.prefix(limit))
    }
}

// MARK: - 달력 격자 계산

enum MonthGrid {
    /// 앞뒤 빈칸(nil)을 포함한 7의 배수 길이의 날짜 배열
    static func cells(for month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: d, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// 기기 설정의 주 시작 요일에 맞춘 요일 이름 (일 월 화 …)
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let s = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    static func isSunday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }
}

enum DayLabel {
    /// "오늘", "내일", 또는 "10월 23일 (금)" 형태
    static func relative(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInTomorrow(date) { return "내일" }
        return date.formatted(.dateTime.month(.defaultDigits).day().weekday(.short))
    }
}

// MARK: - 위젯 → 앱 딥링크

enum DeepLink {
    static let scheme = "mycalendar"

    static func url(for date: Date) -> URL? {
        URL(string: "\(scheme)://day?t=\(Int(date.timeIntervalSince1970))")
    }

    static func date(from url: URL) -> Date? {
        guard url.scheme == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let t = comps.queryItems?.first(where: { $0.name == "t" })?.value,
              let seconds = Double(t) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
