import SwiftUI

/// One chore: a tick for today, its title, who does it and how often, in icons rather than words.
struct ChoreRow: View {
    @ObservedObject var chore: Chore
    let day: Date
    let onToggle: () -> Void

    var body: some View {
        let isDue = chore.occurs(on: day)
        let isDone = chore.completion(on: day) != nil

        HStack(spacing: Theme.Spacing.m) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? Color.hcAccent : Color.hcSecondaryInk)
                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
            }
            .buttonStyle(.borderless)
            .disabled(!isDue)
            .opacity(isDue ? 1 : 0.3)
            .accessibilityLabel(isDone ? Text("Feita") : Text("Por fazer"))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(chore.title ?? "")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                    .strikethrough(isDone)
                RecurrenceBadge(recurrence: chore.recurrence)
            }

            Spacer()

            if let assignee = chore.assignee {
                MemberAvatar(member: assignee, size: 32)
            }
        }
    }
}

/// "Every day", "Mon Wed" or a single date, as an icon plus the fewest characters possible.
struct RecurrenceBadge: View {
    let recurrence: Recurrence

    var body: some View {
        Label {
            switch recurrence {
            case .once: Text("Uma vez")
            case .daily: Text("Todos os dias")
            case .weekly(let weekdays): Text(Self.shortNames(for: weekdays))
            }
        } icon: {
            Image(systemName: recurrence == .once ? "1.circle" : "repeat")
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Color.hcSecondaryInk)
    }

    /// Weekday names in calendar order starting on Monday, e.g. "seg., qua.".
    static func shortNames(for weekdays: Set<Int>, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return WeekdayPicker.mondayFirst
            .filter(weekdays.contains)
            .map { symbols[$0 - 1] }
            .joined(separator: " ")
    }
}
