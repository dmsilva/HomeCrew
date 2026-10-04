import EventKit
import SwiftUI

/// An event from the iPhone's Calendar app (which includes Google or Exchange accounts added there).
/// Read-only: HomeCrew never writes to the user's calendars.
struct ExternalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: CGColor?

    static func == (lhs: ExternalEvent, rhs: ExternalEvent) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.start == rhs.start
            && lhs.end == rhs.end && lhs.isAllDay == rhs.isAllDay
    }
}

/// Reads the day's events from EventKit once the user has allowed it. Used from the main thread only.
final class DeviceCalendar: ObservableObject {
    enum Access: Equatable {
        case notAsked, granted, refused
    }

    @Published private(set) var access: Access
    @Published private(set) var events: [ExternalEvent] = []

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        access = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The day currently shown; changing it reloads.
    var day = Date.now {
        didSet { reload() }
    }

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run {
            access = granted ? .granted : .refused
            reload()
        }
    }

    func reload() {
        guard access == .granted else {
            events = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                ExternalEvent(
                    id: $0.calendarItemIdentifier + "@\($0.startDate.timeIntervalSince1970)",
                    title: $0.title ?? "",
                    start: $0.startDate,
                    end: $0.endDate,
                    isAllDay: $0.isAllDay,
                    color: $0.calendar?.cgColor
                )
            }
    }

    private static func access(for status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notAsked
        default: .refused
        }
    }
}
