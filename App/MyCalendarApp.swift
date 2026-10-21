import SwiftUI
import UserNotifications
import EventKit
import WidgetKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 앱을 보고 있을 때도 알림 배너 표시
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct MyCalendarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = EventStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, koLocale)
                .preferredColorScheme(.dark)
                .task { NotificationScheduler.requestAuthorization() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
    }
}

@MainActor
final class EventStore: ObservableObject {
    /// 앱 안에 저장한 일정
    @Published private(set) var events: [CalendarEvent] = []
    /// 아이폰/구글 캘린더나 표시 설정이 바뀌면 올라감 → 화면 다시 그림
    @Published private(set) var version = 0
    @Published private(set) var calendarStatus: EKAuthorizationStatus = EKBridge.status

    private let repo = EventRepository.shared
    private var observer: NSObjectProtocol?

    init() {
        events = repo.load()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
                                                          object: EKBridge.shared.store,
                                                          queue: .main) { [weak self] _ in
            Task { @MainActor in self?.externalChanged() }
        }
    }

    func reload() {
        events = repo.load()
        NotificationScheduler.reschedule(events)
        externalChanged()
    }

    func externalChanged() {
        EKBridge.shared.invalidate()
        calendarStatus = EKBridge.status
        version += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    func requestCalendarAccess() async {
        _ = await EKBridge.shared.requestAccess()
        externalChanged()
    }

    // MARK: 조회

    func byDay(in range: DateInterval) -> [Date: [Occurrence]] {
        CombinedSource.byDay(local: events, in: range)
    }

    func occurrences(on day: Date) -> [Occurrence] {
        CombinedSource.onDay(local: events, day)
    }

    // MARK: 저장

    /// calendarID == nil 이면 앱(내 캘린더)에, 아니면 아이폰/구글 캘린더에 저장
    func save(_ event: CalendarEvent, to calendarID: String?, original: CalendarEvent?) throws {
        var e = event
        if let calID = calendarID {
            if let o = original, !o.isExternal {
                // 내 캘린더 → 구글로 옮김
                removeLocal(o)
                e.ekEventID = nil
                e.ekOccurrenceStart = nil
            }
            try EKBridge.shared.save(e, calendarID: calID)
            externalChanged()
        } else {
            if let o = original, o.isExternal {
                // 구글 → 내 캘린더로 옮김
                try EKBridge.shared.delete(o, onlyThis: false)
                e.id = UUID()
                e.ekEventID = nil
                e.ekCalendarID = nil
                e.ekOccurrenceStart = nil
                e.colorHex = nil
                externalChanged()
            }
            upsertLocal(e)
        }
    }

    /// 일정 전체 삭제 (반복이면 모든 반복)
    func delete(_ event: CalendarEvent) {
        if event.isExternal {
            try? EKBridge.shared.delete(event, onlyThis: false)
            externalChanged()
        } else {
            removeLocal(event)
        }
    }

    /// 반복 일정 중 하루만 삭제
    func deleteOccurrence(of event: CalendarEvent, on day: Date) {
        if event.isExternal {
            try? EKBridge.shared.delete(event, onlyThis: true)
            externalChanged()
            return
        }
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[i].exceptions.append(Calendar.kr.startOfDay(for: day))
        persist()
    }

    func settingsChanged() {
        externalChanged()
    }

    private func upsertLocal(_ event: CalendarEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            events.append(event)
        }
        persist()
    }

    private func removeLocal(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        repo.deleteImages(event.imageNames)
        persist()
    }

    private func persist() {
        repo.save(events)
        NotificationScheduler.reschedule(events)
    }
}

// MARK: - 알림 예약

enum NotificationScheduler {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 앞으로 두 달 안의 알림을 다시 예약 (iOS 제한 64개 → 60개까지)
    static func reschedule(_ events: [CalendarEvent]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let cal = Calendar.kr
        let now = Date()
        let range = DateInterval(start: cal.startOfDay(for: now), end: now.addingTimeInterval(62 * 86400))

        var items: [(fire: Date, occ: Occurrence)] = []
        for e in events where e.alertOffset != nil {
            for o in e.occurrences(in: range, cal: cal) {
                if let fire = AlertText.fireDate(offset: e.alertOffset, start: o.start, allDay: e.isAllDay, cal: cal), fire > now {
                    items.append((fire, o))
                }
            }
        }
        items.sort { $0.fire < $1.fire }

        for item in items.prefix(60) {
            let o = item.occ
            let content = UNMutableNotificationContent()
            content.title = o.title.isEmpty ? "일정" : o.title
            var body = o.isAllDay
                ? "\(DayLabel.relative(o.start)) 할 일"
                : "\(DayLabel.relative(o.start)) \(KFmt.time(o.start))"
            if !o.event.location.isEmpty { body += " · \(o.event.location)" }
            content.body = body
            content.sound = .default

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: o.id, content: content, trigger: trigger))
        }
    }
}

// MARK: - 이미지 줄이기

extension UIImage {
    func resizedForStorage(maxSide: CGFloat = 1600) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
