import Foundation
import EventKit
import SwiftUI

// MARK: - 어떤 캘린더를 보여줄지 (앱·위젯 공용 설정)

enum CalendarSettings {
    static var defaults: UserDefaults {
        UserDefaults(suiteName: EventRepository.shared.groupID) ?? .standard
    }

    /// 숨긴 아이폰/구글 캘린더 ID (새 캘린더는 기본으로 보이게 "숨김" 목록으로 관리)
    static var hiddenCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "hiddenCalendarIDs") ?? []) }
        set { defaults.set(Array(newValue), forKey: "hiddenCalendarIDs") }
    }

    /// 앱 안에 저장한 일정(내 캘린더) 표시 여부
    static var showLocal: Bool {
        get { !defaults.bool(forKey: "hideLocal") }
        set { defaults.set(!newValue, forKey: "hideLocal") }
    }

    /// 새 일정 기본 저장 위치 (nil = 내 캘린더)
    static var defaultCalendarID: String? {
        get { defaults.string(forKey: "defaultCalendarID") }
        set { defaults.set(newValue, forKey: "defaultCalendarID") }
    }

    /// 처음 연결했을 때 "공휴일" 캘린더는 숨김 (앱에 공휴일이 이미 있어서 겹침)
    static func applyDefaultHiddenIfNeeded(_ calendars: [EKCalendar]) {
        guard !calendars.isEmpty, !defaults.bool(forKey: "didInitHidden") else { return }
        var hidden = hiddenCalendarIDs
        for c in calendars {
            let t = c.title
            if t.contains("공휴일") || t.localizedCaseInsensitiveContains("holiday") {
                hidden.insert(c.calendarIdentifier)
            }
        }
        hiddenCalendarIDs = hidden
        defaults.set(true, forKey: "didInitHidden")
    }
}

// MARK: - 아이폰 캘린더(구글 캘린더 포함) 읽기·쓰기

enum ExternalCalendarError: LocalizedError {
    case noAccess
    case calendarMissing

    var errorDescription: String? {
        switch self {
        case .noAccess: return "캘린더 접근 권한이 없어요. 설정에서 허용해 주세요."
        case .calendarMissing: return "선택한 캘린더를 찾을 수 없어요."
        }
    }
}

final class EKBridge {
    static let shared = EKBridge()

    let store = EKEventStore()
    private var cache: [String: [Occurrence]] = [:]
    private let lock = NSLock()

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async -> Bool {
        do {
            let ok = try await store.requestFullAccessToEvents()
            store.reset()
            invalidate()
            return ok
        } catch {
            return false
        }
    }

    func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    func allCalendars() -> [EKCalendar] {
        guard Self.hasAccess else { return [] }
        return store.calendars(for: .event)
    }

    func writableCalendars() -> [EKCalendar] {
        allCalendars().filter { $0.allowsContentModifications }
    }

    func calendar(id: String) -> EKCalendar? {
        guard Self.hasAccess else { return nil }
        return store.calendar(withIdentifier: id)
    }

    func visibleCalendars() -> [EKCalendar] {
        let all = allCalendars()
        CalendarSettings.applyDefaultHiddenIfNeeded(all)
        let hidden = CalendarSettings.hiddenCalendarIDs
        return all.filter { !hidden.contains($0.calendarIdentifier) }
    }

    /// 범위 안의 일정 (반복은 EventKit이 이미 펼쳐서 줌)
    func occurrences(in range: DateInterval) -> [Occurrence] {
        guard Self.hasAccess else { return [] }
        let key = "\(Int(range.start.timeIntervalSince1970))-\(Int(range.end.timeIntervalSince1970))"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let cals = visibleCalendars()
        var result: [Occurrence] = []
        if !cals.isEmpty {
            let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: cals)
            result = store.events(matching: predicate).map { ek in
                let e = makeEvent(ek)
                return Occurrence(event: e, start: e.start, end: e.end)
            }
        }

        lock.lock()
        cache[key] = result
        lock.unlock()
        return result
    }

    // MARK: EKEvent → 앱 일정

    func makeEvent(_ ek: EKEvent) -> CalendarEvent {
        let cal = Calendar.kr
        let allDay = ek.isAllDay
        let rawStart: Date = ek.startDate ?? Date()
        let start = allDay ? cal.startOfDay(for: rawStart) : rawStart

        var end: Date? = nil
        if let ed = ek.endDate {
            if allDay {
                let last = cal.startOfDay(for: ed.addingTimeInterval(-1))
                end = last > start ? last : nil
            } else if ed > start {
                end = ed
            }
        }

        var e = CalendarEvent(title: ek.title ?? "", start: start, end: end, isAllDay: allDay)
        e.notes = ek.notes ?? ""
        e.location = ek.location ?? ""
        e.url = ek.url?.absoluteString ?? ""
        if let alarm = ek.alarms?.first {
            if let absolute = alarm.absoluteDate {
                e.alertOffset = Int((start.timeIntervalSince(absolute) / 60).rounded())
            } else {
                e.alertOffset = Int((-alarm.relativeOffset / 60).rounded())
            }
        } else {
            e.alertOffset = nil
        }
        if let rule = ek.recurrenceRules?.first {
            e.repeatRule = Self.repeatRule(from: rule)
        }
        e.ekEventID = ek.eventIdentifier
        e.ekCalendarID = ek.calendar?.calendarIdentifier
        e.ekOccurrenceStart = ek.startDate
        if let cg = ek.calendar?.cgColor {
            e.colorHex = Color.hexString(from: cg)
        }
        return e
    }

    // MARK: 저장 · 삭제

    /// 반복 중 특정 날짜의 EKEvent
    private func occurrenceEvent(id: String, start: Date) -> EKEvent? {
        guard let base = store.event(withIdentifier: id) else { return nil }
        guard let baseCalendar = base.calendar else { return base }
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-60),
                                                 end: start.addingTimeInterval(86400 + 60),
                                                 calendars: [baseCalendar])
        let match = store.events(matching: predicate).first { ev in
            ev.eventIdentifier == id && abs(ev.startDate.timeIntervalSince(start)) < 1
        }
        return match ?? base
    }

    func save(_ e: CalendarEvent, calendarID: String) throws {
        guard Self.hasAccess else { throw ExternalCalendarError.noAccess }
        guard let calendar = store.calendar(withIdentifier: calendarID) else { throw ExternalCalendarError.calendarMissing }

        var ek: EKEvent? = nil
        if let id = e.ekEventID {
            if let occStart = e.ekOccurrenceStart {
                ek = occurrenceEvent(id: id, start: occStart)
            } else {
                ek = store.event(withIdentifier: id)
            }
        }
        let event = ek ?? EKEvent(eventStore: store)
        let wasRecurring = event.hasRecurrenceRules

        event.calendar = calendar
        event.title = e.title
        event.isAllDay = e.isAllDay
        event.startDate = e.start
        event.endDate = e.end ?? e.start
        event.location = e.location.isEmpty ? nil : e.location
        event.notes = e.notes.isEmpty ? nil : e.notes
        event.url = e.url.isEmpty ? nil : URL(string: e.url)
        if let off = e.alertOffset {
            event.alarms = [EKAlarm(relativeOffset: TimeInterval(-off * 60))]
        } else {
            event.alarms = nil
        }
        if let rule = e.repeatRule {
            event.recurrenceRules = [Self.ekRule(from: rule)]
        } else {
            event.recurrenceRules = nil
        }

        let span: EKSpan = (wasRecurring || e.repeatRule != nil) ? .futureEvents : .thisEvent
        try store.save(event, span: span, commit: true)
        invalidate()
    }

    /// onlyThis = 반복 중 그날만 / false = 일정 전체
    func delete(_ e: CalendarEvent, onlyThis: Bool) throws {
        guard Self.hasAccess, let id = e.ekEventID else { return }
        let target: EKEvent?
        if onlyThis, let occStart = e.ekOccurrenceStart {
            target = occurrenceEvent(id: id, start: occStart)
        } else {
            target = store.event(withIdentifier: id)
        }
        guard let ev = target else { return }
        try store.remove(ev, span: onlyThis ? .thisEvent : .futureEvents, commit: true)
        invalidate()
    }

    // MARK: 반복 규칙 변환

    static func repeatRule(from r: EKRecurrenceRule) -> RepeatRule? {
        let freq: RepeatFrequency
        switch r.frequency {
        case .daily: freq = .daily
        case .weekly: freq = .weekly
        case .monthly: freq = .monthly
        case .yearly: freq = .yearly
        @unknown default: return nil
        }
        var rule = RepeatRule(frequency: freq, interval: max(1, r.interval))
        if let days = r.daysOfTheWeek, !days.isEmpty {
            if freq == .weekly {
                rule.weekdays = days.map { $0.dayOfTheWeek.rawValue }
            } else if freq == .monthly, let d = days.first {
                let n = d.weekNumber == 0 ? 1 : d.weekNumber
                rule.monthly = .nthWeekday(ordinal: n, weekday: d.dayOfTheWeek.rawValue)
            }
        }
        if freq == .monthly, let dom = r.daysOfTheMonth?.map({ $0.intValue }), !dom.isEmpty {
            rule.monthly = dom.contains(-1) ? .lastDay : .days(dom.filter { $0 > 0 })
        }
        rule.until = r.recurrenceEnd?.endDate
        return rule
    }

    static func ekRule(from rule: RepeatRule) -> EKRecurrenceRule {
        let freq: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: freq = .daily
        case .weekly: freq = .weekly
        case .monthly: freq = .monthly
        case .yearly: freq = .yearly
        }

        var daysOfWeek: [EKRecurrenceDayOfWeek]? = nil
        var daysOfMonth: [NSNumber]? = nil
        switch rule.frequency {
        case .weekly:
            let list = rule.weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
            daysOfWeek = list.isEmpty ? nil : list
        case .monthly:
            switch rule.monthly {
            case .days(let l):
                daysOfMonth = l.isEmpty ? nil : l.map { NSNumber(value: $0) }
            case .lastDay:
                daysOfMonth = [NSNumber(value: -1)]
            case .nthWeekday(let ordinal, let weekday):
                if let wd = EKWeekday(rawValue: weekday) {
                    daysOfWeek = [EKRecurrenceDayOfWeek(wd, weekNumber: ordinal)]
                }
            }
        case .daily, .yearly:
            break
        }

        var end: EKRecurrenceEnd? = nil
        if let u = rule.until {
            let cal = Calendar.kr
            let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: cal.startOfDay(for: u)) ?? u
            end = EKRecurrenceEnd(end: endOfDay)
        }

        return EKRecurrenceRule(recurrenceWith: freq,
                                interval: max(1, rule.interval),
                                daysOfTheWeek: daysOfWeek,
                                daysOfTheMonth: daysOfMonth,
                                monthsOfTheYear: nil,
                                weeksOfTheYear: nil,
                                daysOfTheYear: nil,
                                setPositions: nil,
                                end: end)
    }
}

// MARK: - 앱 일정 + 아이폰/구글 일정 합치기

enum CombinedSource {
    static func occurrences(local: [CalendarEvent], in range: DateInterval, cal: Calendar = .kr) -> [Occurrence] {
        var out: [Occurrence] = CalendarSettings.showLocal ? local.occurrences(in: range, cal: cal) : []
        out += EKBridge.shared.occurrences(in: range)
        return out
    }

    static func byDay(local: [CalendarEvent], in range: DateInterval, cal: Calendar = .kr) -> [Date: [Occurrence]] {
        Occurrences.bucket(occurrences(local: local, in: range, cal: cal), in: range, cal: cal)
    }

    static func onDay(local: [CalendarEvent], _ day: Date, cal: Calendar = .kr) -> [Occurrence] {
        let s = cal.startOfDay(for: day)
        guard let e = cal.date(byAdding: .day, value: 1, to: s) else { return [] }
        return byDay(local: local, in: DateInterval(start: s, end: e), cal: cal)[s] ?? []
    }

    static func upcoming(local: [CalendarEvent], from now: Date, limit: Int, cal: Calendar = .kr) -> [Occurrence] {
        let today = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 31, to: today) else { return [] }
        let list = occurrences(local: local, in: DateInterval(start: today, end: end), cal: cal)
        return Occurrences.upcoming(list, from: now, limit: limit, cal: cal)
    }
}
