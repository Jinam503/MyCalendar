import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (Date) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private let cal = Calendar.kr

    private var results: [CalendarEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return store.events
            .filter { e in
                [e.title, e.location, e.notes, e.url].contains { $0.localizedCaseInsensitiveContains(q) }
            }
            .sorted { displayDate($0) > displayDate($1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.secondaryText)
                    TextField("일정 검색", text: $query, prompt: Text("제목, 위치, 메모 검색").foregroundColor(Theme.secondaryText))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.surface)

                Button("닫기") { dismiss() }
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                Text("찾을 일정을 입력하세요")
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            } else if results.isEmpty {
                Spacer()
                Text("검색 결과가 없어요")
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(results) { e in
                            Button {
                                onPick(displayDate(e))
                                dismiss()
                            } label: {
                                resultRow(e)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { focused = true }
    }

    /// 반복 일정이면 오늘 이후 가장 가까운 날, 아니면 시작일
    private func displayDate(_ e: CalendarEvent) -> Date {
        guard e.repeatRule != nil else { return e.start }
        let today = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 400, to: today) else { return e.start }
        let next = e.occurrences(in: DateInterval(start: today, end: end), cal: cal)
            .map(\.start)
            .min()
        return next ?? e.start
    }

    private func resultRow(_ e: CalendarEvent) -> some View {
        let d = displayDate(e)
        return HStack(spacing: 12) {
            Rectangle().fill(e.color).frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title.isEmpty ? "제목 없음" : e.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail(e, date: d))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if e.repeatRule != nil {
                Image(systemName: "repeat")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .contentShape(Rectangle())
    }

    private func detail(_ e: CalendarEvent, date: Date) -> String {
        var s = KFmt.fullDate(date)
        s += e.isAllDay ? " · 할 일" : " · " + KFmt.time(date)
        if !e.location.isEmpty { s += " · " + e.location }
        return s
    }
}
