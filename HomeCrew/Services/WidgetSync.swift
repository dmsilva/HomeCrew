import CoreData
import WidgetKit

extension WidgetSnapshot {
    /// Today's agenda as this person sees it on Today, plus every medicine still being given.
    static func build(
        day: Date,
        activities: [Activity],
        chores: [Chore],
        medications: [Medication],
        me: Member?,
        access: AccessPolicy,
        now: Date,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        let digest = TodayDigest.build(
            day: day, activities: activities, chores: chores, access: access, viewer: me, calendar: calendar
        )
        let timed = digest.activities.map { occurrence in
            Item(
                id: occurrence.id,
                start: occurrence.start,
                title: occurrence.activity.title ?? "",
                symbol: occurrence.activity.symbol,
                person: occurrence.activity.child?.name ?? "",
                colorIndex: Int(occurrence.activity.child?.colorIndex ?? 0),
                isDone: false,
                isCancelled: occurrence.isCancelled
            )
        }
        let todo = digest.chores.map { chore in
            Item(
                id: chore.objectID.uriRepresentation().absoluteString,
                start: nil,
                title: chore.title ?? "",
                symbol: "checklist",
                person: chore.assignee?.name ?? "",
                colorIndex: Int(chore.assignee?.colorIndex ?? 0),
                isDone: chore.completion(on: day, calendar: calendar) != nil,
                isCancelled: false
            )
        }
        let doses = medications
            .filter { $0.isActive && access.canSee($0.episode?.member) }
            .map { medication in
                Dose(
                    id: medication.identifier?.uuidString ?? medication.objectID.uriRepresentation().absoluteString,
                    medicine: medication.name ?? "",
                    amount: medication.dose ?? "",
                    person: medication.episode?.member?.name ?? "",
                    colorIndex: Int(medication.episode?.member?.colorIndex ?? 0),
                    nextAt: medication.nextDoseAt
                )
            }
        return WidgetSnapshot(generatedAt: now, day: calendar.startOfDay(for: day), items: timed + todo, doses: doses)
    }
}

/// Rewrites the widgets' snapshot whenever something they show changes, then asks WidgetKit to redraw.
final class WidgetSync {
    static let shared = WidgetSync(persistence: .shared, defaults: .standard)

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    init(persistence: PersistenceController, defaults: UserDefaults) {
        self.persistence = persistence
        self.defaults = defaults
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: persistence.viewContext, queue: .main
        ) { [weak self] _ in
            self?.scheduleWrite()
        }
        scheduleWrite()
    }

    func scheduleWrite() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    @MainActor
    func write(now: Date = .now) {
        let context = persistence.viewContext
        let me = persistence.me(from: defaults)
        let snapshot = WidgetSnapshot.build(
            day: now,
            activities: (try? context.fetch(Activity.all())) ?? [],
            chores: (try? context.fetch(Chore.all())) ?? [],
            medications: (try? context.fetch(Medication.all())) ?? [],
            me: me,
            access: me.map(AccessPolicy.init(for:)) ?? .full,
            now: now
        )
        if let current = WidgetSnapshot.load(),
           current.day == snapshot.day, current.items == snapshot.items, current.doses == snapshot.doses {
            return
        }
        try? snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
