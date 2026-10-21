import Foundation
import SwiftUI

// MARK: - 알림

enum AlertOption: String, Codable, CaseIterable, Identifiable {
    case none, atTime, min5, min10, min15, min30, hour1, day1
    case dayOf9am, dayBefore9pm

    var id: String { rawValue }

    /// 시간 있는 일정용
    static let timedOptions: [AlertOption] = [.none, .atTime, .min5, .min10, .min15, .min30, .hour1, .day1]
    /// 할 일(시간 없음)용
    static let allDayOptions: [AlertOption] = [.none, .dayOf9am, .dayBefore9pm]

    static func defaultFor(allDay: Bool) -> AlertOption { allDay ? .dayOf9am : .min30 }

    var label: String {
        switch self {
        case .none: return "알림 없음"
        case .atTime: return "정시"
        case .min5: return "5분 전"
        case .min10: return "10분 전"
        case .min15: return "15분 전"
        case .min30: return "30분 전"
        case .hour1: return "1시간 전"
        case .day1: return "하루 전"
        case .dayOf9am: return "당일 오전 9시"
        case .dayBefore9pm: return "전날 오후 9시"
        }
    }

    func fireDate(for start: Date, cal: Calendar = .kr) -> Date? {
        switch self {
        case .none: return nil
        case .atTime: return start
        case .min5: return start.addingTimeInterval(-5 * 60)
        case .min10: return start.addingTimeInterval(-10 * 60)
        case .min15: return start.addingTimeInterval(-15 * 60)
        case .min30: return start.addingTimeInterval(-30 * 60)
        case .hour1: return start.addingTimeInterval(-3600)
        case .day1: return start.addingTimeInterval(-86400)
        case .dayOf9am: return cal.startOfDay(for: start).addingTimeInterval(9 * 3600)
        case .dayBefore9pm: return cal.startOfDay(for: start).addingTimeInterval(-3 * 3600)
        }
    }
}

// MARK: - 반복

enum RepeatFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .daily: return "일"
        case .weekly: return "주"
        case .monthly: return "월"
        case .yearly: return "년"
        }
    }

    func intervalText(_ n: Int) -> String {
        switch self {
        case .daily: return n == 1 ? "매일" : "\(n)일마다"
        case .weekly: return n == 1 ? "매주" : "\(n)주마다"
        case .monthly: return n == 1 ? "매월" : "\(n)개월마다"
        case .yearly: return n == 1 ? "매년" : "\(n)년마다"
        }
    }
}

enum MonthlyRule: Codable, Hashable {
    /// 매월 특정 날짜들 (1...31). 비어 있으면 시작일의 날짜
    case days([Int])
    /// 매월 마지막 날
    case lastDay
    /// 매월 n번째 X요일 (ordinal 1...5, -1 = 마지막 / weekday 1=일 ... 7=토)
    case nthWeekday(ordinal: Int, weekday: Int)
}

struct RepeatRule: Codable, Hashable {
    var frequency: RepeatFrequency
    var interval: Int = 1
    /// 매주 반복할 요일 (1=일 ... 7=토). 비어 있으면 시작일의 요일
    var weekdays: [Int] = []
    var monthly: MonthlyRule = .days([])
    /// 이 날짜까지 반복 (nil = 계속)
    var until: Date? = nil
}

enum RepeatText {
    static func summary(_ rule: RepeatRule?, start: Date, cal: Calendar = .kr) -> String {
        guard let r = rule else { return "반복되지 않음" }
        let n = max(1, r.interval)
        var s = r.frequency.intervalText(n)
        switch r.frequency {
        case .daily:
            break
        case .weekly:
            let list = r.weekdays.isEmpty ? [cal.component(.weekday, from: start)] : r.weekdays
            let names = list.sorted { order($0) < order($1) }.map { KFmt.weekdayName($0) }
            s += " " + names.joined(separator: ", ")
        case .monthly:
            switch r.monthly {
            case .days(let l):
                let list = l.isEmpty ? [cal.component(.day, from: start)] : l.sorted()
                s += " " + list.map { String($0) }.joined(separator: ", ") + "일"
            case .lastDay:
                s += " 마지막 날"
            case .nthWeekday(let o, let w):
                s += " " + (o == -1 ? "마지막" : "\(o)번째") + " " + KFmt.weekdayName(w) + "요일"
            }
        case .yearly:
            s += " " + KFmt.string(start, "M월 d일")
        }
        if let u = r.until {
            s += " · " + KFmt.dotDate(u) + "까지"
        }
        return s
    }

    /// 월=0 ... 일=6
    static func order(_ weekday: Int) -> Int { (weekday + 5) % 7 }
}

// MARK: - 일정

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    /// 할 일: 그날 0시 / 시간 일정: 시작 시각
    var start: Date
    /// nil = 끝 시간(끝 날짜) 없음. 할 일이면 마지막 날의 0시
    var end: Date? = nil
    /// true = 할 일 (시간 없음)
    var isAllDay: Bool = true
    var colorIndex: Int = 0
    var notes: String = ""
    var location: String = ""
    var url: String = ""
    var imageNames: [String] = []
    var alert: AlertOption = .dayOf9am
    var repeatRule: RepeatRule? = nil
    /// 반복 중 지운 날짜들 (0시)
    var exceptions: [Date] = []

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, isAllDay, colorIndex, notes, location, url, imageNames, alert, repeatRule, exceptions
    }

    var color: Color { EventPalette.color(colorIndex) }

    var duration: TimeInterval {
        guard let end else { return 0 }
        return max(0, end.timeIntervalSince(start))
    }

    static var samples: [CalendarEvent] {
        let cal = Calendar.kr
        let today = cal.startOfDay(for: Date())
        return [
            CalendarEvent(title: "장보기", start: today, colorIndex: 5),
            CalendarEvent(title: "팀 회의", start: today.addingTimeInterval(10 * 3600), end: today.addingTimeInterval(11 * 3600), isAllDay: false, colorIndex: 0, alert: .min30),
            CalendarEvent(title: "저녁 약속", start: today.addingTimeInterval(19 * 3600), isAllDay: false, colorIndex: 1, alert: .min30),
        ]
    }
}

extension CalendarEvent {
    /// 이전 버전 데이터도 읽을 수 있게 없는 항목은 기본값으로
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        imageNames = try c.decodeIfPresent([String].self, forKey: .imageNames) ?? []
        alert = (try? c.decodeIfPresent(AlertOption.self, forKey: .alert)) ?? AlertOption.defaultFor(allDay: isAllDay)
        repeatRule = try? c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
        exceptions = (try? c.decodeIfPresent([Date].self, forKey: .exceptions)) ?? []

        if isAllDay {
            let cal = Calendar.kr
            start = cal.startOfDay(for: start)
            if let e = end {
                let lastDay = cal.startOfDay(for: e)
                end = lastDay > start ? lastDay : nil
            }
        }
    }
}

// MARK: - 실제로 달력에 나타나는 한 번의 일정 (반복 펼친 것)

struct Occurrence: Identifiable, Hashable {
    let event: CalendarEvent
    let start: Date
    let end: Date?

    var id: String { event.id.uuidString + "-" + String(Int(start.timeIntervalSince1970)) }
    var title: String { event.title }
    var color: Color { event.color }
    var isAllDay: Bool { event.isAllDay }

    /// 이 일정이 걸쳐 있는 마지막 날 (0시)
    func lastDay(_ cal: Calendar = .kr) -> Date {
        let sDay = cal.startOfDay(for: start)
        guard let end else { return sDay }
        if isAllDay { return max(sDay, cal.startOfDay(for: end)) }
        if end <= start { return sDay }
        return max(sDay, cal.startOfDay(for: end.addingTimeInterval(-1)))
    }

    /// 목록 왼쪽에 쓰는 짧은 시간
    var timeLabel: String { isAllDay ? "할 일" : KFmt.time(start) }

    var isMultiDay: Bool {
        let cal = Calendar.kr
        return lastDay(cal) > cal.startOfDay(for: start)
    }

    var rangeText: String? {
        guard isMultiDay else { return nil }
        let last = lastDay()
        if isAllDay { return KFmt.monthDay(start) + " – " + KFmt.monthDay(last) }
        guard let end else { return nil }
        return KFmt.string(start, "M/d HH:mm") + " – " + KFmt.string(end, "M/d HH:mm")
    }
}

extension CalendarEvent {
    func occurrences(in range: DateInterval, cal: Calendar = .kr) -> [Occurrence] {
        let dur = duration
        let hasEnd = end != nil

        func make(_ s: Date) -> Occurrence {
            Occurrence(event: self, start: s, end: hasEnd ? s.addingTimeInterval(dur) : nil)
        }
        func overlaps(_ o: Occurrence) -> Bool {
            let sDay = cal.startOfDay(for: o.start)
            guard let afterLast = cal.date(byAdding: .day, value: 1, to: o.lastDay(cal)) else { return false }
            return sDay < range.end && afterLast > range.start
        }

        guard let rule = repeatRule else {
            let o = make(start)
            return overlaps(o) ? [o] : []
        }

        let seriesDay = cal.startOfDay(for: start)
        let timeOffset = start.timeIntervalSince(seriesDay)
        let skipped = Set(exceptions.map { cal.startOfDay(for: $0) })
        var limit = range.end
        if let until = rule.until,
           let u = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: until)) {
            limit = min(limit, u)
        }
        let earliest = cal.startOfDay(for: range.start.addingTimeInterval(-dur - 86400))
        let interval = max(1, rule.interval)
        var out: [Occurrence] = []
        var loops = 0

        func emit(_ day: Date) {
            guard day >= seriesDay, day < limit, !skipped.contains(day) else { return }
            let o = make(day.addingTimeInterval(timeOffset))
            if overlaps(o) { out.append(o) }
        }

        switch rule.frequency {
        case .daily:
            let gap = cal.dateComponents([.day], from: seriesDay, to: earliest).day ?? 0
            var n = max(0, gap / interval)
            while let day = cal.date(byAdding: .day, value: n * interval, to: seriesDay), day < limit, loops < 3000 {
                emit(day)
                n += 1
                loops += 1
            }

        case .weekly:
            let days = rule.weekdays.isEmpty ? [cal.component(.weekday, from: start)] : rule.weekdays
            guard let anchor = cal.dateInterval(of: .weekOfYear, for: seriesDay)?.start else { return out }
            let gapDays = cal.dateComponents([.day], from: anchor, to: earliest).day ?? 0
            var w = max(0, gapDays / 7 / interval) * interval
            while let weekStart = cal.date(byAdding: .day, value: w * 7, to: anchor), weekStart < limit, loops < 1000 {
                for i in 0..<7 {
                    if let day = cal.date(byAdding: .day, value: i, to: weekStart),
                       days.contains(cal.component(.weekday, from: day)) {
                        emit(day)
                    }
                }
                w += interval
                loops += 1
            }

        case .monthly:
            guard let anchor = cal.dateInterval(of: .month, for: seriesDay)?.start else { return out }
            let gap = cal.dateComponents([.month], from: anchor, to: earliest).month ?? 0
            var m = max(0, gap / interval) * interval
            while let monthStart = cal.date(byAdding: .month, value: m, to: anchor), monthStart < limit, loops < 600 {
                for day in Self.monthlyDays(rule.monthly, monthStart: monthStart, seriesStart: start, cal: cal) {
                    emit(day)
                }
                m += interval
                loops += 1
            }

        case .yearly:
            let md = cal.dateComponents([.month, .day], from: seriesDay)
            let startYear = cal.component(.year, from: seriesDay)
            let earliestYear = cal.component(.year, from: earliest)
            var y = max(0, (earliestYear - startYear) / interval) * interval
            while loops < 200 {
                guard let yearStart = cal.date(from: DateComponents(year: startYear + y, month: 1, day: 1)),
                      yearStart < limit else { break }
                if let day = cal.date(from: DateComponents(year: startYear + y, month: md.month, day: md.day)),
                   cal.component(.day, from: day) == md.day {
                    emit(day)
                }
                y += interval
                loops += 1
            }
        }
        return out
    }

    static func monthlyDays(_ rule: MonthlyRule, monthStart: Date, seriesStart: Date, cal: Calendar) -> [Date] {
        guard let count = cal.range(of: .day, in: .month, for: monthStart)?.count else { return [] }
        func day(_ d: Int) -> Date? { cal.date(byAdding: .day, value: d - 1, to: monthStart) }
        switch rule {
        case .days(let list):
            let l = list.isEmpty ? [cal.component(.day, from: seriesStart)] : list
            return l.sorted().filter { $0 >= 1 && $0 <= count }.compactMap { day($0) }
        case .lastDay:
            return [day(count)].compactMap { $0 }
        case .nthWeekday(let ordinal, let weekday):
            let matches = (1...count).compactMap { day($0) }.filter { cal.component(.weekday, from: $0) == weekday }
            if ordinal == -1 {
                if let last = matches.last { return [last] }
                return []
            }
            return (ordinal >= 1 && ordinal <= matches.count) ? [matches[ordinal - 1]] : []
        }
    }
}

// MARK: - 날짜별 조회

extension Array where Element == Occurrence {
    /// 할 일 먼저, 그다음 시간 일정을 시간 순으로
    func sortedForDay() -> [Occurrence] {
        sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.start != b.start { return a.start < b.start }
            return a.title < b.title
        }
    }
}

extension Array where Element == CalendarEvent {
    func occurrences(in range: DateInterval, cal: Calendar = .kr) -> [Occurrence] {
        flatMap { $0.occurrences(in: range, cal: cal) }
    }

    /// 범위 안의 날짜(0시)별 일정
    func byDay(in range: DateInterval, cal: Calendar = .kr) -> [Date: [Occurrence]] {
        var map: [Date: [Occurrence]] = [:]
        for o in occurrences(in: range, cal: cal) {
            var d = Swift.max(cal.startOfDay(for: o.start), range.start)
            let last = o.lastDay(cal)
            var guardCount = 0
            while d <= last && d < range.end && guardCount < 400 {
                map[d, default: []].append(o)
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
                guardCount += 1
            }
        }
        for k in map.keys {
            map[k] = map[k]?.sortedForDay()
        }
        return map
    }

    func occurrences(on day: Date, cal: Calendar = .kr) -> [Occurrence] {
        let s = cal.startOfDay(for: day)
        guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return [] }
        return byDay(in: DateInterval(start: s, end: e), cal: cal)[s] ?? []
    }

    /// 오늘 할 일 + 앞으로 있을 일정 (위젯용)
    func upcoming(from now: Date, limit: Int, cal: Calendar = .kr) -> [Occurrence] {
        let today = cal.startOfDay(for: now)
        guard let rangeEnd = cal.date(byAdding: .day, value: 31, to: today) else { return [] }
        let all = occurrences(in: DateInterval(start: today, end: rangeEnd), cal: cal).filter { o in
            if o.isAllDay { return o.lastDay(cal) >= today }
            if let end = o.end { return end > now }
            return o.start >= now.addingTimeInterval(-30 * 60)
        }
        let sorted = all.sorted { a, b in
            let da = Swift.max(cal.startOfDay(for: a.start), today)
            let db = Swift.max(cal.startOfDay(for: b.start), today)
            if da != db { return da < db }
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            return a.start < b.start
        }
        return Array(sorted.prefix(limit))
    }
}

// MARK: - 달력 격자 (월요일 시작, 앞뒤 달 날짜 포함)

enum MonthGrid {
    static let weekdaySymbols = ["월", "화", "수", "목", "금", "토", "일"]

    static func days(for month: Date, cal: Calendar = .kr) -> [Date] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let total = Int((Double(leading + count) / 7.0).rounded(.up)) * 7
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0..<total).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    static func range(of days: [Date], cal: Calendar = .kr) -> DateInterval {
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else {
            let now = cal.startOfDay(for: Date())
            return DateInterval(start: now, duration: 86400)
        }
        return DateInterval(start: first, end: end)
    }

    static func isWeekend(_ date: Date, cal: Calendar = .kr) -> Bool {
        let w = cal.component(.weekday, from: date)
        return w == 1 || w == 7
    }
}
