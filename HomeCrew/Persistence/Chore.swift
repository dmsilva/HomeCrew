import CoreData

/// When a chore happens. Pure value logic, so it is tested without Core Data.
enum Recurrence: Equatable {
    case once
    case daily
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday, as `Calendar` numbers them.
    case weekly(Set<Int>)

    func occurs(on day: Date, startingFrom start: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: day)
        let start = calendar.startOfDay(for: start)
        switch self {
        case .once:
            return day == start
        case .daily:
            return day >= start
        case .weekly(let weekdays):
            return day >= start && weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    /// Every day in `interval` (start of day, inclusive of both ends) on which the chore happens.
    func occurrences(in interval: DateInterval, startingFrom start: Date, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day <= interval.end {
            if occurs(on: day, startingFrom: start, calendar: calendar) { days.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}

/// A household task given to an adult or a child, done once or on a repeat.
/// Named Chore so it never clashes with Swift's `Task`.
@objc(Chore)
final class Chore: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var title: String?
    @NSManaged var recurrenceValue: String?
    @NSManaged var weekdayMask: Int16
    @NSManaged var startDate: Date?
    @NSManaged var points: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var family: Family?
    @NSManaged var assignee: Member?
    @NSManaged var completions: NSSet?

    static func all() -> NSFetchRequest<Chore> {
        let request = NSFetchRequest<Chore>(entityName: "Chore")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    var recurrence: Recurrence {
        get {
            switch recurrenceValue {
            case "daily": return .daily
            case "weekly": return .weekly(Self.weekdays(from: weekdayMask))
            default: return .once
            }
        }
        set {
            switch newValue {
            case .once:
                recurrenceValue = "once"
                weekdayMask = 0
            case .daily:
                recurrenceValue = "daily"
                weekdayMask = 0
            case .weekly(let weekdays):
                recurrenceValue = "weekly"
                weekdayMask = Self.mask(from: weekdays)
            }
        }
    }

    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        recurrence.occurs(on: day, startingFrom: startDate ?? .distantPast, calendar: calendar)
    }

    func completion(on day: Date, calendar: Calendar = .current) -> ChoreCompletion? {
        let all = (completions as? Set<ChoreCompletion>) ?? []
        return all.first { $0.occurrenceDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }

    static func mask(from weekdays: Set<Int>) -> Int16 {
        weekdays.filter { (1...7).contains($0) }.reduce(0) { $0 | Int16(1 << ($1 - 1)) }
    }

    static func weekdays(from mask: Int16) -> Set<Int> {
        Set((1...7).filter { mask & Int16(1 << ($0 - 1)) != 0 })
    }
}

/// One occurrence of a chore marked as done: who did it and when.
@objc(ChoreCompletion)
final class ChoreCompletion: NSManagedObject {
    @NSManaged var identifier: UUID?
    /// The day of the occurrence (start of day), not the moment it was ticked.
    @NSManaged var occurrenceDate: Date?
    @NSManaged var completedAt: Date?
    /// Phase 2: points earned, copied from the chore so later edits don't rewrite history.
    @NSManaged var pointsAwarded: Int16
    @NSManaged var chore: Chore?
    @NSManaged var completedBy: Member?
}

/// What the chore editor collects; a cancelled edit changes nothing.
struct ChoreDraft: Equatable {
    var title = ""
    var assignee: Member?
    var recurrence: Recurrence = .daily
    var startDate = Date.now

    init() {}

    init(_ chore: Chore) {
        title = chore.title ?? ""
        assignee = chore.assignee
        recurrence = chore.recurrence
        startDate = chore.startDate ?? .now
    }

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if case .weekly(let weekdays) = recurrence { return !weekdays.isEmpty }
        return true
    }
}

extension PersistenceController {
    @discardableResult
    func addChore(_ draft: ChoreDraft, to family: Family) -> Chore {
        let chore = Chore(context: viewContext)
        if let store = family.objectID.persistentStore {
            viewContext.assign(chore, to: store)
        }
        chore.identifier = UUID()
        chore.createdAt = .now
        chore.family = family
        apply(draft, to: chore)
        save()
        return chore
    }

    func update(_ chore: Chore, with draft: ChoreDraft) {
        apply(draft, to: chore)
        save()
    }

    func delete(_ chore: Chore) {
        viewContext.delete(chore)
        save()
    }

    /// Marks the occurrence on `day` done by `member` (the assignee unless told otherwise),
    /// or undoes it when it was already done.
    func toggleDone(_ chore: Chore, on day: Date, by member: Member? = nil, calendar: Calendar = .current) {
        if let existing = chore.completion(on: day, calendar: calendar) {
            viewContext.delete(existing)
        } else {
            let completion = ChoreCompletion(context: viewContext)
            if let store = chore.objectID.persistentStore {
                viewContext.assign(completion, to: store)
            }
            completion.identifier = UUID()
            completion.occurrenceDate = calendar.startOfDay(for: day)
            completion.completedAt = .now
            completion.completedBy = member ?? chore.assignee
            completion.pointsAwarded = chore.points
            completion.chore = chore
        }
        save()
    }

    private func apply(_ draft: ChoreDraft, to chore: Chore) {
        chore.title = draft.title.trimmingCharacters(in: .whitespaces)
        chore.assignee = draft.assignee
        chore.recurrence = draft.recurrence
        chore.startDate = Calendar.current.startOfDay(for: draft.startDate)
    }
}
