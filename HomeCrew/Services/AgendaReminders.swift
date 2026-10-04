import CoreData
import UserNotifications

/// Which agenda notifications this iPhone wants; each can be turned off.
struct AgendaNotificationSettings: Equatable {
    static let beforeActivityKey = "notifyBeforeActivity"
    static let dailySummaryKey = "notifyDailySummary"
    static let summaryMinutesKey = "dailySummaryMinutes"
    static let changesKey = "notifyAgendaChanges"

    var beforeActivity = true
    var dailySummary = true
    /// Minutes after midnight; 7:30 by default.
    var summaryMinutes = 7 * 60 + 30
    var changes = true

    init() {}

    init(_ defaults: UserDefaults) {
        beforeActivity = defaults.object(forKey: Self.beforeActivityKey) as? Bool ?? true
        dailySummary = defaults.object(forKey: Self.dailySummaryKey) as? Bool ?? true
        summaryMinutes = defaults.object(forKey: Self.summaryMinutesKey) as? Int ?? 7 * 60 + 30
        changes = defaults.object(forKey: Self.changesKey) as? Bool ?? true
    }
}

struct PlannedAgendaNotice: Equatable {
    static let identifierPrefix = "agenda-"

    let identifier: String
    let fireAt: Date
    let title: String
    let body: String
}

enum AgendaReminders {
    static let minutesBefore = 30
    /// How far ahead notifications are scheduled; iOS keeps at most 64 pending per app.
    static let daysAhead = 3
    static let maxPending = 40

    /// "Leva" reminders 30 minutes before, only for whoever takes the child that day, and the morning summary.
    static func plan(
        activities: [Activity],
        chores: [Chore],
        me: Member?,
        access: AccessPolicy,
        settings: AgendaNotificationSettings,
        now: Date,
        calendar: Calendar = .current
    ) -> [PlannedAgendaNotice] {
        guard let me else { return [] }
        let today = calendar.startOfDay(for: now)
        let days = (0..<daysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        var notices: [PlannedAgendaNotice] = []

        if settings.beforeActivity {
            for day in days {
                for occurrence in ActivitySchedule.occurrences(of: activities, on: day, calendar: calendar)
                where !occurrence.isCancelled && occurrence.dropOff == me {
                    let fireAt = occurrence.start.addingTimeInterval(TimeInterval(-minutesBefore * 60))
                    guard fireAt > now else { continue }
                    let activity = occurrence.activity
                    let child = activity.child?.name ?? ""
                    let place = activity.location ?? ""
                    notices.append(PlannedAgendaNotice(
                        identifier: PlannedAgendaNotice.identifierPrefix + "before-" + occurrence.id,
                        fireAt: fireAt,
                        title: [activity.title ?? "", child].filter { !$0.isEmpty }.joined(separator: " · "),
                        body: [occurrence.start.formatted(date: .omitted, time: .shortened), place]
                            .filter { !$0.isEmpty }.joined(separator: " · ")
                    ))
                }
            }
        }

        if settings.dailySummary {
            for day in days {
                guard let fireAt = calendar.date(byAdding: .minute, value: settings.summaryMinutes, to: day), fireAt > now else { continue }
                let digest = TodayDigest.build(
                    day: day, activities: activities, chores: chores, access: access, viewer: me, calendar: calendar
                )
                let activityCount = digest.activities.filter { !$0.isCancelled }.count
                let choreCount = digest.chores.count
                guard activityCount + choreCount > 0 else { continue }
                let first = digest.activities.first { !$0.isCancelled }.map {
                    "\($0.start.formatted(date: .omitted, time: .shortened)) \($0.activity.title ?? "")"
                }
                let counts = String(localized: "\(activityCount) atividades · \(choreCount) tarefas")
                notices.append(PlannedAgendaNotice(
                    identifier: PlannedAgendaNotice.identifierPrefix + "summary-\(Int(day.timeIntervalSince1970))",
                    fireAt: fireAt,
                    title: String(localized: "O teu dia"),
                    body: [counts, first].compactMap { $0 }.joined(separator: " · ")
                ))
            }
        }

        return Array(notices.sorted { $0.fireAt < $1.fireAt }.prefix(maxPending))
    }

    /// Changes that arrived from someone else and touch this person: their drives, their chores.
    static func changeNotice(changed: [NSManagedObject], me: Member?, now: Date) -> PlannedAgendaNotice? {
        guard let me else { return nil }
        var titles: [String] = []
        for object in changed {
            switch object {
            case let exception as ActivityException:
                guard let activity = exception.activity,
                      exception.dropOff == me || exception.pickUp == me || activity.dropOff == me || activity.pickUp == me
                else { continue }
                titles.append(activity.title ?? "")
            case let activity as Activity:
                guard activity.dropOff == me || activity.pickUp == me else { continue }
                titles.append(activity.title ?? "")
            case let chore as Chore:
                guard chore.assignee == me else { continue }
                titles.append(chore.title ?? "")
            default:
                continue
            }
        }
        let unique = titles.filter { !$0.isEmpty }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !unique.isEmpty else { return nil }
        return PlannedAgendaNotice(
            identifier: PlannedAgendaNotice.identifierPrefix + "change-\(Int(now.timeIntervalSince1970))",
            fireAt: now,
            title: String(localized: "Alterações na agenda"),
            body: unique.joined(separator: ", ")
        )
    }
}

extension PersistenceController {
    /// The member this iPhone said it is ("Quem sou eu?").
    func me(from defaults: UserDefaults) -> Member? {
        guard let id = defaults.string(forKey: "meMemberID"), let uuid = UUID(uuidString: id) else { return nil }
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "identifier == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
}

/// Keeps the agenda notifications pending and announces changes merged in from iCloud.
final class AgendaReminderCenter {
    static let shared = AgendaReminderCenter(
        persistence: .shared,
        scheduler: UNUserNotificationCenter.current(),
        defaults: .standard
    )

    private let persistence: PersistenceController
    private let scheduler: NotificationScheduling
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    init(persistence: PersistenceController, scheduler: NotificationScheduling, defaults: UserDefaults) {
        self.persistence = persistence
        self.scheduler = scheduler
        self.defaults = defaults
    }

    func start() {
        let context = persistence.viewContext
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: .main
        ) { [weak self] note in
            guard Self.touchesAgenda(note) else { return }
            self?.scheduleRefresh()
        })
        // Only merges carry other people's edits; this iPhone's own edits never reach this notification.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didMergeChangesObjectIDsNotification, object: context, queue: .main
        ) { [weak self] note in
            self?.announceMergedChanges(note)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh()
        })
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    @MainActor
    func refresh(now: Date = .now) async {
        let context = persistence.viewContext
        let me = persistence.me(from: defaults)
        let plan = AgendaReminders.plan(
            activities: (try? context.fetch(Activity.all())) ?? [],
            chores: (try? context.fetch(Chore.all())) ?? [],
            me: me,
            access: me.map(AccessPolicy.init(for:)) ?? .full,
            settings: AgendaNotificationSettings(defaults),
            now: now
        )
        let wanted = Set(plan.map(\.identifier))
        let stale = await scheduler.pendingRequestIdentifiers().filter {
            $0.hasPrefix(PlannedAgendaNotice.identifierPrefix) && !$0.contains("-change-") && !wanted.contains($0)
        }
        scheduler.removePendingNotificationRequests(withIdentifiers: stale)
        for notice in plan {
            try? await scheduler.add(Self.request(for: notice, now: now))
        }
    }

    private func announceMergedChanges(_ note: Notification) {
        guard AgendaNotificationSettings(defaults).changes else { return }
        let context = persistence.viewContext
        let keys = [NSInsertedObjectIDsKey, NSUpdatedObjectIDsKey]
        let ids = keys.flatMap { (note.userInfo?[$0] as? Set<NSManagedObjectID>) ?? [] }
        let objects = ids.compactMap { try? context.existingObject(with: $0) }
        guard let notice = AgendaReminders.changeNotice(changed: objects, me: persistence.me(from: defaults), now: .now) else { return }
        Task { try? await scheduler.add(Self.request(for: notice, now: .now)) }
    }

    static func request(for notice: PlannedAgendaNotice, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        let delay = notice.fireAt.timeIntervalSince(now)
        let trigger = delay > 1 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        return UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger)
    }

    private static func touchesAgenda(_ note: Notification) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
        return keys.contains { key in
            ((note.userInfo?[key] as? Set<NSManagedObject>) ?? []).contains {
                $0 is Activity || $0 is ActivityException || $0 is Chore || $0 is CustodyPlan || $0 is CustodySwap || $0 is Member
            }
        }
    }
}
