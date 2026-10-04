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

    /// When this activity starts on `day`.
    func start(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: Int(startMinutes), to: calendar.startOfDay(for: day)) ?? day
    }
}

/// One activity on one day, the unit the agenda lists.
struct ActivityOccurrence: Identifiable, Equatable {
    let activity: Activity
    let start: Date

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
            .map { ActivityOccurrence(activity: $0, start: $0.start(on: day, calendar: calendar)) }
            .sorted { $0.start < $1.start }
    }
}

struct ActivityDraft: Equatable {
    var title = ""
    var symbolName = Activity.symbols[0]
    var child: Member?
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

    private func apply(_ draft: ActivityDraft, to activity: Activity) {
        activity.title = draft.title.trimmingCharacters(in: .whitespaces)
        activity.symbolName = draft.symbolName
        activity.child = draft.child
        activity.weekdays = draft.weekdays
        activity.startMinutes = Int16(clamping: draft.startMinutes)
        activity.durationMinutes = Int16(clamping: draft.durationMinutes)
        activity.location = draft.location.trimmingCharacters(in: .whitespaces)
        activity.equipment = draft.equipment.trimmingCharacters(in: .whitespaces)
        activity.notes = draft.notes
        activity.startDate = Calendar.current.startOfDay(for: draft.startDate)
    }
}
