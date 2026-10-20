import Foundation
import WidgetKit

/// 앱과 위젯이 같은 일정 파일을 보도록 App Group 공유 폴더에 JSON으로 저장합니다.
final class EventRepository {
    static let shared = EventRepository()

    /// project.yml 의 App Group 과 같은 값
    static let defaultAppGroupID = "group.com.mycalendar.shared"

    private let fileName = "events.json"
    private let queue = DispatchQueue(label: "EventRepository")

    /// AltStore 같은 사이드로딩 도구는 App Group 이름을 바꿔서 서명하고
    /// 바뀐 이름을 Info.plist 의 `ALTAppGroups` 에 적어 둡니다. 그 값부터 시도합니다.
    private lazy var containerURL: URL = {
        var candidates: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates += alt
        }
        candidates.append(Self.defaultAppGroupID)
        for id in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        // App Group 을 못 쓰는 경우: 앱은 동작하지만 위젯과 데이터 공유는 안 됨
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    private var fileURL: URL { containerURL.appendingPathComponent(fileName) }

    func load() -> [CalendarEvent] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([CalendarEvent].self, from: data)) ?? []
        }
    }

    func save(_ events: [CalendarEvent]) {
        queue.sync {
            do {
                let data = try JSONEncoder().encode(events)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("일정 저장 실패: \(error)")
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
