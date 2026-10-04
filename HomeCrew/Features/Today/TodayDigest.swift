import Foundation

/// Something that needs attention before anything else today (a sick child, a dose due…).
/// Health tickets add the sources; the screen already has the slot at the top.
struct TodayAlert: Identifiable, Equatable {
    let id: String
    let systemImage: String
    let title: String
    let member: Member?
}

/// One line of the day's agenda: a family activity or an event from the iPhone's calendar.
enum AgendaItem: Identifiable, Equatable {
    case activity(ActivityOccurrence)
    case external(ExternalEvent)

    var id: String {
        switch self {
        case .activity(let occurrence): "activity-\(occurrence.id)"
        case .external(let event): "external-\(event.id)"
        }
    }

    var start: Date {
        switch self {
        case .activity(let occurrence): occurrence.start
        case .external(let event): event.start
        }
    }
}

/// Everything the Today screen shows, in the order it shows it: alerts, then the day's
/// activities by time, then chores still to do (done ones last).
struct TodayDigest: Equatable {
    var alerts: [TodayAlert] = []
    var activities: [ActivityOccurrence] = []
    var externalEvents: [ExternalEvent] = []
    var chores: [Chore] = []

    var isEmpty: Bool { alerts.isEmpty && agenda.isEmpty && chores.isEmpty }

    /// Activities and calendar events mixed by start time; all-day events first.
    var agenda: [AgendaItem] {
        let allDay = externalEvents.filter(\.isAllDay).map(AgendaItem.external)
        let timed = activities.map(AgendaItem.activity) + externalEvents.filter { !$0.isAllDay }.map(AgendaItem.external)
        return allDay + timed.sorted { $0.start < $1.start }
    }

    /// `me`, when set, keeps only what involves that person: their own activities, the ones
    /// they take or bring that day, and chores given to them.
    static func build(
        day: Date,
        activities: [Activity],
        chores: [Chore],
        alerts: [TodayAlert] = [],
        externalEvents: [ExternalEvent] = [],
        me: Member? = nil,
        access: AccessPolicy = .full,
        viewer: Member? = nil,
        calendar: Calendar = .current
    ) -> TodayDigest {
        // Children at the other house today are left out: Today is about the children who are with you.
        func isHere(_ member: Member?) -> Bool { member?.isWith(viewer, on: day, calendar: calendar) ?? true }

        var occurrences = access.filter(ActivitySchedule.occurrences(of: activities, on: day, calendar: calendar), calendar: calendar)
            .filter { isHere($0.activity.child) }
        var dueChores = access.filter(chores.filter { $0.occurs(on: day, calendar: calendar) }, on: day, calendar: calendar)
            .filter { isHere($0.assignee) }
        var shownAlerts = alerts.filter { access.canSee($0.member) }

        if let me {
            occurrences = occurrences.filter {
                $0.activity.child == me || $0.dropOff == me || $0.pickUp == me
            }
            dueChores = dueChores.filter { $0.assignee == me }
            shownAlerts = shownAlerts.filter { $0.member == nil || $0.member == me }
        }

        // Stable partition: still-to-do first, keeping the chores' own order within each group.
        let pending = dueChores.filter { $0.completion(on: day, calendar: calendar) == nil }
        let done = dueChores.filter { $0.completion(on: day, calendar: calendar) != nil }

        // Calendar events come from this iPhone, so they are already "mine".
        return TodayDigest(alerts: shownAlerts, activities: occurrences, externalEvents: externalEvents, chores: pending + done)
    }
}
