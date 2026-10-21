import Foundation

/// 달력 칸에 표시할 공휴일·기념일
struct DayMark: Hashable {
    let name: String
    /// true = 빨간 날(공휴일), false = 쉬지 않는 기념일
    let isHoliday: Bool
}

enum KoreanHolidays {
    /// 쉬지 않는 기념일 (월, 일, 이름)
    private static let observances: [(month: Int, day: Int, name: String)] = [
        (2, 14, "발렌타인데이"),
        (3, 14, "화이트데이"),
        (4, 5, "식목일"),
        (5, 8, "어버이날"),
        (5, 15, "스승의날"),
        (10, 1, "국군의날"),
        (11, 11, "빼빼로데이"),
        (12, 24, "크리스마스 이브"),
    ]

    static func key(_ date: Date, cal: Calendar = .kr) -> Int {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func marks(for date: Date, cal: Calendar = .kr) -> [DayMark] {
        let k = key(date, cal: cal)
        var out = (KoreanHolidayData.table[k] ?? []).map { DayMark(name: $0, isHoliday: true) }
        let month = (k / 100) % 100
        let day = k % 100
        for o in observances where o.month == month && o.day == day {
            if !out.contains(where: { $0.name == o.name }) {
                out.append(DayMark(name: o.name, isHoliday: false))
            }
        }
        return out
    }

    static func isHoliday(_ date: Date, cal: Calendar = .kr) -> Bool {
        KoreanHolidayData.table[key(date, cal: cal)] != nil
    }
}
