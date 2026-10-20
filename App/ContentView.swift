import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: EventStore
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var editing: CalendarEvent?
    @State private var showingNew = false

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                CalendarGrid(month: displayedMonth,
                             selectedDate: $selectedDate,
                             events: store.events)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 30).onEnded { v in
                            if v.translation.width < -50 { shiftMonth(1) }
                            else if v.translation.width > 50 { shiftMonth(-1) }
                        }
                    )
                Divider().padding(.top, 8)
                dayEvents
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("오늘") { go(to: Date()) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) {
                EventEditor(event: nil, defaultDate: selectedDate)
                    .environmentObject(store)
            }
            .sheet(item: $editing) { event in
                EventEditor(event: event, defaultDate: event.start)
                    .environmentObject(store)
            }
            .onOpenURL { url in
                if let d = DeepLink.date(from: url) { go(to: d) }
            }
        }
    }

    // MARK: 상단 월 표시

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Spacer()
            Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title2.bold())
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: 선택한 날의 일정

    private var dayEvents: some View {
        let items = store.events.occurring(on: selectedDate)
        return VStack(alignment: .leading, spacing: 0) {
            Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            if items.isEmpty {
                VStack(spacing: 12) {
                    Text("일정이 없어요").foregroundStyle(.secondary)
                    Button("일정 추가") { showingNew = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { event in
                        Button { editing = event } label: { EventRow(event: event) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        offsets.map { items[$0] }.forEach(store.delete)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: 이동

    private func shiftMonth(_ delta: Int) {
        guard let m = cal.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = m
            if cal.isDate(m, equalTo: Date(), toGranularity: .month) {
                selectedDate = Date()
            } else {
                selectedDate = cal.dateInterval(of: .month, for: m)?.start ?? m
            }
        }
    }

    private func go(to date: Date) {
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = date
            selectedDate = date
        }
    }
}

// MARK: - 달력 격자

struct CalendarGrid: View {
    let month: Date
    @Binding var selectedDate: Date
    let events: [CalendarEvent]

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let cells = MonthGrid.cells(for: month)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells.indices, id: \.self) { i in
                    if let date = cells[i] {
                        DayCell(date: date,
                                isSelected: cal.isDate(date, inSameDayAs: selectedDate),
                                isToday: cal.isDateInToday(date),
                                colors: events.occurring(on: date).prefix(3).map(\.color))
                            .onTapGesture { selectedDate = date }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let colors: [Color]

    var body: some View {
        let day = Calendar.current.component(.day, from: date)
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.system(size: 16, weight: isToday || isSelected ? .semibold : .regular))
                .foregroundStyle(textColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(fillColor))
            HStack(spacing: 2) {
                ForEach(colors.indices, id: \.self) { i in
                    Circle().fill(colors[i]).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var fillColor: Color {
        guard isSelected else { return .clear }
        return isToday ? .red : .primary
    }

    private var textColor: Color {
        if isSelected { return Color(UIColor.systemBackground) }
        if isToday { return .red }
        return MonthGrid.isSunday(date) ? .red.opacity(0.75) : .primary
    }
}

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium))
                Text(event.timeRangeText).font(.subheadline).foregroundStyle(.secondary)
                if !event.notes.isEmpty {
                    Text(event.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
