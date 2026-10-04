import CoreData

/// What an illness does to the agenda: the coming activities the sick person would miss.
enum IllnessAgenda {
    /// Today and the next two days.
    static let daysAhead = 3

    /// The person's activities still to come in the next few days that are not already cancelled, earliest first.
    static func affected(
        for member: Member,
        from date: Date,
        days: Int = daysAhead,
        calendar: Calendar = .current
    ) -> [ActivityOccurrence] {
        let activities = Array((member.activities as? Set<Activity>) ?? [])
        let today = calendar.startOfDay(for: date)
        return (0..<days)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .flatMap { ActivitySchedule.occurrences(of: activities, on: $0, calendar: calendar) }
            .filter { !$0.isCancelled && $0.start >= date }
    }

    /// The task that reminds someone to tell the school or coach; the app itself never messages anyone.
    static func warningTitle(for activity: Activity) -> String {
        let person = activity.child?.name ?? ""
        let title = activity.title ?? ""
        return person.isEmpty ? String(localized: "Avisar \(title)") : String(localized: "Avisar \(title) · \(person)")
    }
}

extension PersistenceController {
    /// Cancels only the confirmed occurrences and, when asked, adds one warning task per activity for today.
    @discardableResult
    func cancelForIllness(
        _ confirmed: [ActivityOccurrence],
        addWarningTasks: Bool,
        assignee: Member?,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> [Chore] {
        for occurrence in confirmed {
            setCancelled(true, occurrence.activity, on: occurrence.start, calendar: calendar)
        }
        guard addWarningTasks else { return [] }

        var seen = Set<NSManagedObjectID>()
        return confirmed.compactMap { occurrence -> Chore? in
            let activity = occurrence.activity
            guard seen.insert(activity.objectID).inserted, let family = activity.family else { return nil }
            var draft = ChoreDraft()
            draft.title = IllnessAgenda.warningTitle(for: activity)
            draft.recurrence = .once
            draft.startDate = date
            draft.assignee = assignee
            return addChore(draft, to: family)
        }
    }
}
