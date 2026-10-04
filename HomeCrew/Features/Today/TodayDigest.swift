import Foundation

/// Something that needs attention before anything else today (a sick child, a dose due…).
/// Health tickets add the sources; the screen already has the slot at the top.
struct TodayAlert: Identifiable, Equatable {
    let id: String
    let systemImage: String
    let title: String
    let member: Member?
}

/// Everything the Today screen shows, in the order it shows it: alerts, then the day's
/// activities by time, then chores still to do (done ones last).
struct TodayDigest: Equatable {
    var alerts: [TodayAlert] = []
    var activities: [ActivityOccurrence] = []
    var chores: [Chore] = []

    var isEmpty: Bool { alerts.isEmpty && activities.isEmpty && chores.isEmpty }

    /// `me`, when set, keeps only what involves that person: their own activities, the ones
    /// they take or bring that day, and chores given to them.
    static func build(
        day: Date,
        activities: [Activity],
        chores: [Chore],
        alerts: [TodayAlert] = [],
        me: Member? = nil,
        calendar: Calendar = .current
    ) -> TodayDigest {
        var occurrences = ActivitySchedule.occurrences(of: activities, on: day, calendar: calendar)
        var dueChores = chores.filter { $0.occurs(on: day, calendar: calendar) }
        var shownAlerts = alerts

        if let me {
            occurrences = occurrences.filter {
                $0.activity.child == me || $0.dropOff == me || $0.pickUp == me
            }
            dueChores = dueChores.filter { $0.assignee == me }
            shownAlerts = alerts.filter { $0.member == nil || $0.member == me }
        }

        // Stable partition: still-to-do first, keeping the chores' own order within each group.
        let pending = dueChores.filter { $0.completion(on: day, calendar: calendar) == nil }
        let done = dueChores.filter { $0.completion(on: day, calendar: calendar) != nil }

        return TodayDigest(alerts: shownAlerts, activities: occurrences, chores: pending + done)
    }
}
