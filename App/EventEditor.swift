import SwiftUI

struct EventEditor: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss

    private let original: CalendarEvent?

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var colorIndex: Int
    @State private var notes: String
    @State private var confirmDelete = false

    init(event: CalendarEvent?, defaultDate: Date) {
        original = event
        if let e = event {
            _title = State(initialValue: e.title)
            _isAllDay = State(initialValue: e.isAllDay)
            _start = State(initialValue: e.start)
            _end = State(initialValue: e.end)
            _colorIndex = State(initialValue: e.colorIndex)
            _notes = State(initialValue: e.notes)
        } else {
            // 기본값: 선택한 날짜, 지금 시각의 다음 정시부터 1시간
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: defaultDate)
            comps.hour = min(cal.component(.hour, from: Date()) + 1, 23)
            comps.minute = 0
            let s = cal.date(from: comps) ?? defaultDate
            _title = State(initialValue: "")
            _isAllDay = State(initialValue: false)
            _start = State(initialValue: s)
            _end = State(initialValue: s.addingTimeInterval(3600))
            _colorIndex = State(initialValue: 0)
            _notes = State(initialValue: "")
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var components: DatePickerComponents { isAllDay ? [.date] : [.date, .hourAndMinute] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $title)
                }
                Section {
                    Toggle("하루 종일", isOn: $isAllDay)
                    DatePicker("시작", selection: $start, displayedComponents: components)
                    DatePicker("종료", selection: $end, displayedComponents: components)
                }
                Section("색상") {
                    HStack(spacing: 14) {
                        ForEach(EventPalette.colors.indices, id: \.self) { i in
                            Circle()
                                .fill(EventPalette.colors[i])
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .opacity(colorIndex == i ? 1 : 0)
                                )
                                .onTapGesture { colorIndex = i }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("메모") {
                    TextField("메모", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if original != nil {
                    Section {
                        Button("일정 삭제", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "새 일정" : "일정 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onChange(of: start) { old, new in
                // 시작을 옮기면 종료도 같은 간격만큼 따라가게
                let duration = max(end.timeIntervalSince(old), 0)
                end = new.addingTimeInterval(duration)
            }
            .confirmationDialog("이 일정을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if let original { store.delete(original) }
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        var s = start
        var e = end
        if isAllDay {
            s = cal.startOfDay(for: start)
            let lastDay = cal.startOfDay(for: max(end, start))
            e = cal.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay) ?? lastDay
        }
        if e < s { e = s }
        let event = CalendarEvent(id: original?.id ?? UUID(),
                                  title: trimmedTitle,
                                  start: s,
                                  end: e,
                                  isAllDay: isAllDay,
                                  colorIndex: colorIndex,
                                  notes: notes)
        store.upsert(event)
        dismiss()
    }
}
