import SwiftUI

@main
struct MyCalendarApp: App {
    @StateObject private var store = EventStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
    }

    func upsert(_ event: CalendarEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            events.append(event)
        }
        repo.save(events)
    }

    func delete(_ event: CalendarEvent) {
        events.removeAll { $0.id == event.id }
        repo.save(events)
    }
}
