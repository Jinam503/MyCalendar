import SwiftUI

/// 편집 화면을 여는 정보 (새 일정이면 event == nil)
struct EditorTarget: Identifiable {
    let id = UUID()
    let event: CalendarEvent?
    /// 새 일정: 기본 날짜 / 기존 일정: 눌렀던 날짜(반복 중 하루 삭제용)
    let date: Date
}

struct ContentView: View {
    @EnvironmentObject private var store: EventStore
    @State private var month: Date = Date()
    @State private var selected: Date = Calendar.kr.startOfDay(for: Date())
    @State private var forward = true
    @State private var editorTarget: EditorTarget?
    @State private var showSearch = false

    private let cal = Calendar.kr

    private var monthKey: Int {
        cal.component(.year, from: month) * 100 + cal.component(.month, from: month)
    }

    var body: some View {
        let days = MonthGrid.days(for: month, cal: cal)
        let range = MonthGrid.range(of: days, cal: cal)
        let map = store.events.byDay(in: range, cal: cal)

        GeometryReader { geo in
            let total = geo.size.height
            let headerH: CGFloat = 60
            let weekdayH: CGFloat = 24
            let gridH = max(100, total * 0.7 - headerH - weekdayH)
            let panelH = max(80, total - headerH - weekdayH - gridH - 1)

            VStack(spacing: 0) {
                header.frame(height: headerH)
                weekdayRow.frame(height: weekdayH)

                ZStack {
                    MonthGridView(month: month,
                                  days: days,
                                  selected: selected,
                                  byDay: map,
                                  onTap: tap)
                        .id(monthKey)
                        .transition(.push(from: forward ? .trailing : .leading))
                }
                .frame(height: gridH)
                .clipped()

                Rectangle().fill(Theme.line).frame(height: 1)

                DayPanel(date: selected,
                         items: map[selected] ?? store.events.occurrences(on: selected, cal: cal),
                         marks: KoreanHolidays.marks(for: selected, cal: cal),
                         onOpen: { o in editorTarget = EditorTarget(event: o.event, date: o.start) },
                         onAdd: { editorTarget = EditorTarget(event: nil, date: selected) },
                         onDelete: { o, onlyThis in
                             if onlyThis { store.deleteOccurrence(of: o.event, on: o.start) }
                             else { store.delete(o.event) }
                         })
                    .frame(height: panelH)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        .fullScreenCover(item: $editorTarget) { target in
            EventEditor(event: target.event, date: target.date)
                .environmentObject(store)
                .environment(\.locale, koLocale)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView { date in go(to: date) }
                .environmentObject(store)
                .environment(\.locale, koLocale)
                .preferredColorScheme(.dark)
        }
        .onOpenURL { url in
            if let d = DeepLink.date(from: url) { go(to: d) }
        }
    }

    // MARK: 위쪽

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(cal.component(.month, from: month))월")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
            Text(verbatim: "\(cal.component(.year, from: month))년")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            HStack(spacing: 4) {
                iconButton("magnifyingglass") { showSearch = true }
                iconButton("calendar") { go(to: Date()) }
            }
        }
        .padding(.horizontal, 16)
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(MonthGrid.weekdaySymbols.enumerated()), id: \.offset) { i, s in
                Text(s)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(i >= 5 ? Theme.weekendText : Color(white: 0.85))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 스와이프로 달 넘기기 (화면 어디서든)

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { v in
                let dx = v.translation.width
                let dy = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                shiftMonth(dx < 0 ? 1 : -1)
            }
    }

    private func shiftMonth(_ delta: Int) {
        guard let m = cal.date(byAdding: .month, value: delta, to: month) else { return }
        let newSelected: Date
        if cal.isDate(m, equalTo: Date(), toGranularity: .month) {
            newSelected = cal.startOfDay(for: Date())
        } else {
            newSelected = cal.dateInterval(of: .month, for: m)?.start ?? m
        }
        change(to: m, select: newSelected, forward: delta > 0)
    }

    private func change(to newMonth: Date, select day: Date, forward isForward: Bool) {
        forward = isForward
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                month = newMonth
                selected = day
            }
        }
    }

    private func tap(_ day: Date) {
        if cal.isDate(day, equalTo: month, toGranularity: .month) {
            selected = day
        } else {
            change(to: day, select: day, forward: day > month)
        }
    }

    private func go(to date: Date) {
        let d = cal.startOfDay(for: date)
        if cal.isDate(d, equalTo: month, toGranularity: .month) {
            selected = d
        } else {
            change(to: d, select: d, forward: d > month)
        }
    }
}

// MARK: - 달력 격자

struct MonthGridView: View {
    let month: Date
    let days: [Date]
    let selected: Date
    let byDay: [Date: [Occurrence]]
    let onTap: (Date) -> Void

    private let cal = Calendar.kr

    var body: some View {
        GeometryReader { geo in
            let rows = max(1, days.count / 7)
            let cellW = geo.size.width / 7
            let cellH = geo.size.height / CGFloat(rows)
            let maxChips = max(0, Int((cellH - 30) / 16))

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            cell(days[r * 7 + c], maxChips: maxChips)
                                .frame(width: cellW, height: cellH)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date, maxChips: Int) -> some View {
        DayCellView(day: day,
                    inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                    isToday: cal.isDateInToday(day),
                    isSelected: cal.isDate(day, inSameDayAs: selected),
                    marks: KoreanHolidays.marks(for: day, cal: cal),
                    occurrences: byDay[day] ?? [],
                    maxChips: maxChips)
            .contentShape(Rectangle())
            .onTapGesture { onTap(day) }
    }
}

struct DayCellView: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let marks: [DayMark]
    let occurrences: [Occurrence]
    let maxChips: Int

    private var isHoliday: Bool { marks.contains { $0.isHoliday } }

    private var chips: [ChipItem] {
        let m = marks.map {
            ChipItem(id: "m-" + $0.name,
                     title: $0.name,
                     color: $0.isHoliday ? Theme.holiday : Color(white: 0.5),
                     filled: $0.isHoliday)
        }
        let o = occurrences.map {
            ChipItem(id: $0.id, title: $0.title, color: $0.color, filled: $0.isAllDay)
        }
        return m + o
    }

    private var numberColor: Color {
        if isHoliday { return Theme.holiday }
        if isToday { return .black }
        if MonthGrid.isWeekend(day) { return Theme.weekendText }
        return .white
    }

    private var background: Color {
        if isToday { return .white }
        if isSelected { return Theme.surface2 }
        return .clear
    }

    var body: some View {
        let all = chips
        let overflow = all.count > maxChips
        let shown = overflow ? max(0, maxChips - 1) : all.count
        let hidden = all.count - shown

        VStack(spacing: 3) {
            Text(verbatim: "\(Calendar.kr.component(.day, from: day))")
                .font(.system(size: 17, weight: isToday ? .bold : .medium))
                .foregroundStyle(numberColor)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(all.prefix(shown)) { chip in
                    ChipView(chip: chip, onLight: isToday)
                }
                if hidden > 0 && maxChips > 0 {
                    Text(verbatim: "+\(hidden)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Color.black.opacity(0.6) : Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(background)
        .opacity(inMonth ? 1 : 0.35)
    }
}

// MARK: - 아래쪽 일정 목록

struct DayPanel: View {
    let date: Date
    let items: [Occurrence]
    let marks: [DayMark]
    let onOpen: (Occurrence) -> Void
    let onAdd: () -> Void
    let onDelete: (Occurrence, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(KFmt.fullDate(date))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                if !marks.isEmpty {
                    Text(marks.map(\.name).joined(separator: ", "))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(marks.contains { $0.isHoliday } ? Theme.holiday : Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items) { o in
                        EventRowView(occurrence: o)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpen(o) }
                            .contentShape(.contextMenuPreview, Rectangle())
                            .contextMenu {
                                if o.event.repeatRule != nil {
                                    Button(role: .destructive) { onDelete(o, true) } label: {
                                        Label("이 일정만 삭제", systemImage: "minus.circle")
                                    }
                                    Button(role: .destructive) { onDelete(o, false) } label: {
                                        Label("모든 반복 일정 삭제", systemImage: "trash")
                                    }
                                } else {
                                    Button(role: .destructive) { onDelete(o, false) } label: {
                                        Label("삭제", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    Button(action: onAdd) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                            Text("새로운 일정")
                            Spacer()
                        }
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Theme.surface)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}

struct EventRowView: View {
    let occurrence: Occurrence

    var body: some View {
        let o = occurrence
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(o.timeLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.85))
                if !o.isAllDay, let end = o.end {
                    Text(KFmt.time(end))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 48, alignment: .leading)

            Rectangle().fill(o.color).frame(width: 4, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(o.title.isEmpty ? "제목 없음" : o.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let sub = subtitle(o) {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if o.event.repeatRule != nil { Image(systemName: "repeat") }
                if !o.event.imageNames.isEmpty { Image(systemName: "photo") }
                if o.event.alert != .none { Image(systemName: "bell") }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }

    private func subtitle(_ o: Occurrence) -> String? {
        var parts: [String] = []
        if let r = o.rangeText { parts.append(r) }
        if !o.event.location.isEmpty { parts.append(o.event.location) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
