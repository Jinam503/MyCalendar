import SwiftUI
import EventKit

/// 오른쪽 위 캘린더 버튼: 보여줄 캘린더 고르기 + 구글 캘린더 연결
struct CalendarSettingsView: View {
    @EnvironmentObject private var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var hidden: Set<String> = CalendarSettings.hiddenCalendarIDs
    @State private var showLocal: Bool = CalendarSettings.showLocal
    @State private var defaultID: String? = CalendarSettings.defaultCalendarID

    private struct SourceGroup: Identifiable {
        let id: String
        let title: String
        let calendars: [EKCalendar]
    }

    private var groups: [SourceGroup] {
        let all = EKBridge.shared.allCalendars()
        let grouped = Dictionary(grouping: all) { $0.source?.title ?? "기타" }
        return grouped
            .map { key, cals in
                SourceGroup(id: key,
                            title: sourceTitle(key, cals.first?.source),
                            calendars: cals.sorted { $0.title < $1.title })
            }
            .sorted { a, b in
                let ga = a.title.contains("Google") ? 0 : 1
                let gb = b.title.contains("Google") ? 0 : 1
                if ga != gb { return ga < gb }
                return a.title < b.title
            }
    }

    private func sourceTitle(_ title: String, _ source: EKSource?) -> String {
        guard let source else { return title }
        let lower = title.lowercased()
        if lower.contains("gmail") || lower.contains("google") { return "Google Calendar" }
        if source.sourceType == .calDAV && title.contains("@") { return "Google Calendar / " + title }
        if source.sourceType == .local { return "iPhone" }
        if lower == "icloud" { return "iCloud" }
        return title
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("이 앱에서 표시할 캘린더를 선택해주세요.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)

                    section("이 앱") {
                        calendarRow(title: "내 캘린더", color: Theme.accent, on: showLocal) {
                            showLocal.toggle()
                            CalendarSettings.showLocal = showLocal
                            store.settingsChanged()
                        }
                    }

                    if store.calendarStatus == .fullAccess {
                        ForEach(groups) { g in
                            section(g.title) {
                                ForEach(g.calendars, id: \.calendarIdentifier) { c in
                                    calendarRow(title: c.title,
                                                color: Color(cgColor: c.cgColor),
                                                on: !hidden.contains(c.calendarIdentifier)) {
                                        toggle(c.calendarIdentifier)
                                    }
                                }
                            }
                        }
                        defaultSection
                    } else if store.calendarStatus == .notDetermined {
                        connectCard
                    } else {
                        deniedCard
                    }

                    helpCard
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("캘린더")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
    }

    // MARK: 조각

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func calendarRow(title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(on ? color : Color.clear)
                        .overlay(Circle().stroke(color, lineWidth: 2))
                        .frame(width: 26, height: 26)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
    }

    private var defaultSection: some View {
        let writable = EKBridge.shared.writableCalendars()
        let currentName: String = {
            if let id = defaultID, let c = writable.first(where: { $0.calendarIdentifier == id }) { return c.title }
            return "내 캘린더"
        }()

        return section("새 일정 기본 저장 위치") {
            Menu {
                Button("내 캘린더") { setDefault(nil) }
                ForEach(writable, id: \.calendarIdentifier) { c in
                    Button(c.title) { setDefault(c.calendarIdentifier) }
                }
            } label: {
                HStack {
                    Text(currentName)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("구글 캘린더 연결")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text("아이폰에 추가한 구글·iCloud 캘린더를 이 앱에서 보고, 일정을 추가·수정할 수 있어요.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
            Button {
                Task { await store.requestCalendarAccess() }
            } label: {
                Text("캘린더 접근 허용하기")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("캘린더 접근이 꺼져 있어요")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text("설정 → 앱 → MyCalendar → 캘린더에서 \"전체 접근\"을 켜 주세요.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("설정 열기")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("구글 계정이 안 보이면")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text("아이폰 설정 → 앱 → 캘린더 → 캘린더 계정 → 계정 추가 → Google 에서 로그인하고 \"캘린더\"를 켜 주세요. 그러면 여기에 나타나요.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: 동작

    private func toggle(_ id: String) {
        if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
        CalendarSettings.hiddenCalendarIDs = hidden
        store.settingsChanged()
    }

    private func setDefault(_ id: String?) {
        defaultID = id
        CalendarSettings.defaultCalendarID = id
    }
}
