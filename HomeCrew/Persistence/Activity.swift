import CoreData

/// A child's recurring activity (football, swimming…): weekdays, a time, where, and what to bring.
@objc(Activity)
final class Activity: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var title: String?
    @NSManaged var symbolName: String?
    @NSManaged var weekdayMask: Int16
    /// Minutes after midnight, so the time doesn't drift with time zones or daylight saving.
    @NSManaged var startMinutes: Int16
    @NSManaged var durationMinutes: Int16
    @NSManaged var location: String?
    @NSManaged var equipment: String?
    @NSManaged var notes: String?
    @NSManaged var startDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var family: Family?
    @NSManaged var child: Member?
    /// The general rule: who usually takes the child there and who brings them back.
    @NSManaged var dropOff: Member?
    @NSManaged var pickUp: Member?
    @NSManaged var exceptions: NSSet?

    /// Icons offered in the editor; the first is the fallback.
    static let symbols = [
        "figure.run", "soccerball", "figure.pool.swim", "basketball", "tennis.racket",
        "figure.martial.arts", "figure.gymnastics", "music.note", "paintpalette", "book",
    ]

    static func all() -> NSFetchRequest<Activity> {
        let request = NSFetchRequest<Activity>(entityName: "Activity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "startMinutes", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
        ]
        return request
    }

    var weekdays: Set<Int> {
        get { WeekdayMask.decode(weekdayMask) }
        set { weekdayMask = WeekdayMask.encode(newValue) }
    }

    var symbol: String { symbolName ?? Self.symbols[0] }

    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        Recurrence.weekly(weekdays).occurs(on: day, startingFrom: startDate ?? .distantPast, calendar: calendar)
    }

    func exception(on day: Date, calendar: Calendar = .current) -> ActivityException? {
        let all = (exceptions as? Set<ActivityException>) ?? []
        return all.first { $0.occurrenceDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }

    func isCancelled(on day: Date, calendar: Calendar = .current) -> Bool {
        exception(on: day, calendar: calendar)?.isCancelled ?? false
    }

    /// Who takes the child on `day`: that day's change if there is one, otherwise the rule.
    func dropOff(on day: Date, calendar: Calendar = .current) -> Member? {
        exception(on: day, calendar: calendar)?.dropOff ?? dropOff
    }

    func pickUp(on day: Date, calendar: Calendar = .current) -> Member? {
        exception(on: day, calendar: calendar)?.pickUp ?? pickUp
    }

    /// When this activity starts on `day`.
    func start(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: Int(startMinutes), to: calendar.startOfDay(for: day)) ?? day
    }
}

/// A change to a single occurrence (a different driver, or cancelled) that leaves the rule alone.
@objc(ActivityException)
final class ActivityException: NSManagedObject {
    @NSManaged var identifier: UUID?
    /// Start of the day the change applies to.
    @NSManaged var occurrenceDate: Date?
    @NSManaged var isCancelled: Bool
    /// nil means "as the rule says".
    @NSManaged var dropOff: Member?
    @NSManaged var pickUp: Member?
    @NSManaged var activity: Activity?

    var isEmpty: Bool { !isCancelled && dropOff == nil && pickUp == nil }
}

/// One activity on one day, the unit the agenda lists.
struct ActivityOccurrence: Identifiable, Equatable {
    let activity: Activity
    let start: Date
    var isCancelled = false
    var dropOff: Member?
    var pickUp: Member?

    var id: String { "\(activity.objectID.uriRepresentation().absoluteString)@\(start.timeIntervalSince1970)" }
}

enum ActivitySchedule {
    /// The seven days of the week containing `date`, Monday first.
    static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        var calendar = calendar
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The occurrences on `day`, earliest first.
    static func occurrences(of activities: [Activity], on day: Date, calendar: Calendar = .current) -> [ActivityOccurrence] {
        activities
            .filter { $0.occurs(on: day, calendar: calendar) }
            .map {
                ActivityOccurrence(
                    activity: $0,
                    start: $0.start(on: day, calendar: calendar),
                    isCancelled: $0.isCancelled(on: day, calendar: calendar),
                    dropOff: $0.dropOff(on: day, calendar: calendar),
                    pickUp: $0.pickUp(on: day, calendar: calendar)
                )
            }
            .sorted { $0.start < $1.start }
    }
}

struct ActivityDraft: Equatable {
    var title = ""
    var symbolName = Activity.symbols[0]
    var child: Member?
    var dropOff: Member?
    var pickUp: Member?
    var weekdays: Set<Int> = []
    var startMinutes = 18 * 60
    var durationMinutes = 60
    var location = ""
    var equipment = ""
    var notes = ""
    var startDate = Date.now

    init() {}

    init(_ activity: Activity) {
        title = activity.title ?? ""
        symbolName = activity.symbol
        child = activity.child
        dropOff = activity.dropOff
        pickUp = activity.pickUp
        weekdays = activity.weekdays
        startMinutes = Int(activity.startMinutes)
        durationMinutes = Int(activity.durationMinutes)
        location = activity.location ?? ""
        equipment = activity.equipment ?? ""
        notes = activity.notes ?? ""
        startDate = activity.startDate ?? .now
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !weekdays.isEmpty
    }
}

extension PersistenceController {
    @discardableResult
    func addActivity(_ draft: ActivityDraft, to family: Family) -> Activity {
        let activity = Activity(context: viewContext)
        if let store = family.objectID.persistentStore {
            viewContext.assign(activity, to: store)
        }
        activity.identifier = UUID()
        activity.createdAt = .now
        activity.family = family
        apply(draft, to: activity)
        save()
        return activity
    }

    func update(_ activity: Activity, with draft: ActivityDraft) {
        apply(draft, to: activity)
        save()
    }

    func delete(_ activity: Activity) {
        viewContext.delete(activity)
        save()
    }

    /// Changes who takes or brings the child on one day only. Passing nil for both returns the day to the rule.
    func overrideDrivers(_ activity: Activity, on day: Date, dropOff: Member?, pickUp: Member?, calendar: Calendar = .current) {
        let exception = self.exception(for: activity, on: day, calendar: calendar)
        exception.dropOff = dropOff
        exception.pickUp = pickUp
        tidy(exception)
        save()
    }

    func setCancelled(_ cancelled: Bool, _ activity: Activity, on day: Date, calendar: Calendar = .current) {
        let exception = self.exception(for: activity, on: day, calendar: calendar)
        exception.isCancelled = cancelled
        tidy(exception)
        save()
    }

    private func exception(for activity: Activity, on day: Date, calendar: Calendar) -> ActivityException {
        if let existing = activity.exception(on: day, calendar: calendar) { return existing }
        let exception = ActivityException(context: viewContext)
        if let store = activity.objectID.persistentStore {
            viewContext.assign(exception, to: store)
        }
        exception.identifier = UUID()
        exception.occurrenceDate = calendar.startOfDay(for: day)
        exception.activity = activity
        return exception
    }

    /// An exception that no longer changes anything is deleted, so the day follows the rule again.
    private func tidy(_ exception: ActivityException) {
        if exception.isEmpty { viewContext.delete(exception) }
    }

    private func apply(_ draft: ActivityDraft, to activity: Activity) {
        activity.title = draft.title.trimmingCharacters(in: .whitespaces)
        activity.symbolName = draft.symbolName
        activity.child = draft.child
        activity.dropOff = draft.dropOff
        activity.pickUp = draft.pickUp
        activity.weekdays = draft.weekdays
        activity.startMinutes = Int16(clamping: draft.startMinutes)
        activity.durationMinutes = Int16(clamping: draft.durationMinutes)
        activity.location = draft.location.trimmingCharacters(in: .whitespaces)
        activity.equipment = draft.equipment.trimmingCharacters(in: .whitespaces)
        activity.notes = draft.notes
        activity.startDate = Calendar.current.startOfDay(for: draft.startDate)
    }
}
