import CoreData
import UserNotifications

/// A local notification the app wants pending for the next dose of a medication.
struct PlannedReminder: Equatable {
    static let identifierPrefix = "dose-"
    static let category = "dose"
    static let giveNowAction = "give-now"
    static let medicationKey = "medication"

    let medicationID: UUID
    let fireAt: Date
    let title: String
    let body: String

    var identifier: String { Self.identifierPrefix + medicationID.uuidString }
}

enum DoseReminders {
    /// One reminder per active medication with a next dose in the future, only on the iPhone of the person
    /// responsible for it. With nobody responsible, whoever has the child that day per the custody calendar is
    /// reminded; before this iPhone knows who uses it, it is reminded too.
    static func plan(medications: [Medication], me: Member?, now: Date) -> [PlannedReminder] {
        medications.compactMap { medication in
            guard let id = medication.identifier, let next = medication.nextDoseAt, next > now else { return nil }
            if let responsible = medication.responsible, let me, responsible != me { return nil }
            // With nobody responsible, the parent who has the child at dose time is the one reminded.
            if medication.responsible == nil, let child = medication.episode?.member, !child.isWith(me, on: next) {
                return nil
            }
            let name = medication.name ?? ""
            let person = medication.episode?.member?.name ?? ""
            return PlannedReminder(
                medicationID: id,
                fireAt: next,
                title: person.isEmpty ? name : "\(name) · \(person)",
                body: (medication.dose ?? "").isEmpty ? String(localized: "Hora da dose") : medication.dose ?? ""
            )
        }
    }
}

/// The part of UNUserNotificationCenter the reminders use, so tests can stand in for it.
protocol NotificationScheduling: AnyObject {
    func pendingRequestIdentifiers() async -> [String]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
    func pendingRequestIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }
}

/// Keeps pending dose notifications in step with the data, whether it changed here or arrived from iCloud.
final class DoseReminderCenter {
    static let shared = DoseReminderCenter(
        persistence: .shared,
        scheduler: UNUserNotificationCenter.current(),
        defaults: .standard
    )

    private let persistence: PersistenceController
    private let scheduler: NotificationScheduling
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    init(persistence: PersistenceController, scheduler: NotificationScheduling, defaults: UserDefaults) {
        self.persistence = persistence
        self.scheduler = scheduler
        self.defaults = defaults
    }

    func start() {
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: PlannedReminder.category,
                actions: [UNNotificationAction(identifier: PlannedReminder.giveNowAction, title: String(localized: "Dei agora"))],
                intentIdentifiers: []
            ),
        ])
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: persistence.viewContext,
            queue: .main
        ) { [weak self] note in
            guard Self.touchesMedication(note) else { return }
            self?.scheduleRefresh()
        }
        scheduleRefresh()
    }

    func requestAuthorization() {
        // UI tests run on a throwaway store; a system permission alert would only get in their way.
        guard !ProcessInfo.processInfo.arguments.contains("-inMemoryStore") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Coalesces bursts of changes (a save, a sync) into one refresh.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    @MainActor
    func refresh(now: Date = .now) async {
        let medications = (try? persistence.viewContext.fetch(Medication.all())) ?? []
        let plan = DoseReminders.plan(medications: medications, me: me, now: now)
        let wanted = Set(plan.map(\.identifier))
        let stale = await scheduler.pendingRequestIdentifiers()
            .filter { $0.hasPrefix(PlannedReminder.identifierPrefix) && !wanted.contains($0) }
        scheduler.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in plan {
            try? await scheduler.add(Self.request(for: reminder, now: now))
        }
    }

    /// "Dei agora" from the notification itself.
    @MainActor
    func giveNow(medicationID: UUID, at date: Date = .now) {
        guard let medication = persistence.medication(withIdentifier: medicationID), medication.isActive else { return }
        persistence.giveDose(of: medication, by: me, at: date)
    }

    private var me: Member? {
        guard let id = defaults.string(forKey: "meMemberID"), let uuid = UUID(uuidString: id) else { return nil }
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "identifier == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try? persistence.viewContext.fetch(request).first
    }

    static func request(for reminder: PlannedReminder, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = PlannedReminder.category
        content.userInfo = [PlannedReminder.medicationKey: reminder.medicationID.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(reminder.fireAt.timeIntervalSince(now), 1), repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }

    private static func touchesMedication(_ note: Notification) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
        return keys.contains { key in
            ((note.userInfo?[key] as? Set<NSManagedObject>) ?? []).contains {
                $0 is Medication || $0 is DoseGiven || $0 is IllnessEpisode || $0 is CustodyPlan
            }
        }
    }
}
