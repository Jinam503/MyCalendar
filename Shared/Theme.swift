import SwiftUI

let koLocale = Locale(identifier: "ko_KR")

extension Calendar {
    /// 한국어 · 월요일 시작 달력
    static let kr: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = koLocale
        c.timeZone = TimeZone.current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 1
        return c
    }()
}

// MARK: - 색

enum Theme {
    static let bg = Color(white: 0.07)
    static let surface = Color(white: 0.13)
    static let surface2 = Color(white: 0.20)
    static let line = Color(white: 0.22)
    static let secondaryText = Color(white: 0.62)
    static let weekendText = Color(white: 0.55)
    static let holiday = Color(red: 0.95, green: 0.33, blue: 0.30)
    static let accent = Color(red: 0.49, green: 0.83, blue: 0.88)
}

enum EventPalette {
    static let colors: [Color] = [
        Color(red: 0.49, green: 0.83, blue: 0.88), // 하늘
        Color(red: 0.62, green: 0.45, blue: 0.90), // 보라
        Color(red: 0.95, green: 0.38, blue: 0.38), // 빨강
        Color(red: 0.98, green: 0.62, blue: 0.27), // 주황
        Color(red: 0.98, green: 0.84, blue: 0.30), // 노랑
        Color(red: 0.42, green: 0.80, blue: 0.47), // 초록
        Color(red: 0.36, green: 0.56, blue: 0.98), // 파랑
        Color(red: 0.95, green: 0.50, blue: 0.75), // 분홍
        Color(white: 0.60)                         // 회색
    ]

    static func color(_ i: Int) -> Color {
        let n = colors.count
        return colors[((i % n) + n) % n]
    }
}

// MARK: - 날짜 글자 (항상 한국어)

enum KFmt {
    static func string(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = koLocale
        f.calendar = Calendar.kr
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f.string(from: date)
    }

    /// 19:00
    static func time(_ d: Date) -> String { string(d, "HH:mm") }
    /// 2026년 10월 21일 (수)
    static func fullDate(_ d: Date) -> String { string(d, "yyyy년 M월 d일 (E)") }
    /// 10월 21일 (수)
    static func monthDay(_ d: Date) -> String { string(d, "M월 d일 (E)") }
    /// 2026. 10. 31.
    static func dotDate(_ d: Date) -> String { string(d, "yyyy. M. d.") }

    static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"] // Calendar weekday 1...7

    static func weekdayName(_ weekday: Int) -> String {
        weekdayNames[((weekday - 1) % 7 + 7) % 7]
    }
}

enum DayLabel {
    /// "오늘", "내일", 또는 "10월 23일 (금)"
    static func relative(_ date: Date, calendar: Calendar = .kr) -> String {
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInTomorrow(date) { return "내일" }
        return KFmt.monthDay(date)
    }
}

// MARK: - 각진 스위치

struct SquareSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? Color.white : Theme.surface2)
                    .frame(width: 48, height: 28)
                Rectangle()
                    .fill(isOn ? Color.black : Color(white: 0.55))
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
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
