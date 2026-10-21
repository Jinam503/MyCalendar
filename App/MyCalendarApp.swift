import SwiftUI
import UserNotifications

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
    @Published private(set) var events: [CalendarEvent] = []
    private let repo = EventRepository.shared

    init() {
        events = repo.load()
    }

    func reload() {
        events = repo.load()
        NotificationScheduler.reschedule(events)
    }

    func upsert(_ event: CalendarEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            events.append(event)
        }
        persist()
    }

    /// 일정 전체 삭제 (반복이면 모든 반복)
    func delete(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        repo.deleteImages(event.imageNames)
        persist()
    }

    /// 반복 일정 중 하루만 삭제
    func deleteOccurrence(of event: CalendarEvent, on day: Date) {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[i].exceptions.append(Calendar.kr.startOfDay(for: day))
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
        for e in events where e.alert != .none {
            for o in e.occurrences(in: range, cal: cal) {
                if let fire = e.alert.fireDate(for: o.start, cal: cal), fire > now {
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
