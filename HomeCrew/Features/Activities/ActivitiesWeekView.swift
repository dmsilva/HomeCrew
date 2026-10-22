import CoreData
import SwiftUI

/// The week a day at a time: a strip of days to pick from, a filter per child, and that day's activities as rows.
struct ActivitiesWeekView: View {
    @FetchRequest(fetchRequest: Activity.all()) private var activities: FetchedResults<Activity>
    let days: [Date]
    let onEdit: (Activity) -> Void

    @State private var selectedDay: Date?
    @State private var person: NSManagedObjectID?
    @Environment(\.access) private var access

    var body: some View {
        let byDay = days.map { day in access.filter(ActivitySchedule.occurrences(of: Array(activities), on: day)) }
        let day = chosenDay
        let children = byDay.flatMap { $0.compactMap(\.activity.child) }.uniqued()
            .sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
        let index = days.firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } ?? 0
        let shown = (byDay.indices.contains(index) ? byDay[index] : [])
            .filter { person == nil || $0.activity.child?.objectID == person }

        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            DayStrip(days: days, selected: day, busy: byDay.map { !$0.isEmpty }) { selectedDay = $0 }
            if children.count > 1 {
                PersonFilter(people: children, selection: $person)
            }
            VStack(spacing: 0) {
                if shown.isEmpty {
                    Text("Sem atividades neste dia")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Color.hcSecondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { offset, occurrence in
                    if offset > 0 { RowDivider() }
                    NavigationLink {
                        ActivityDetailView(activity: occurrence.activity, day: day, onEdit: onEdit)
                    } label: {
                        AgendaRow(occurrence: occurrence, isNext: false, isPast: occurrence.start < .now)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 0)
        }
    }

    /// The day the person tapped if it is in this week, otherwise today, otherwise the week's first day.
    private var chosenDay: Date {
        let calendar = Calendar.current
        if let selectedDay, days.contains(where: { calendar.isDate($0, inSameDayAs: selectedDay) }) { return selectedDay }
        return days.first(where: calendar.isDateInToday) ?? days.first ?? .now
    }
}

/// The week's days as chips: short weekday over the date, green when chosen, a dot when something is on.
struct DayStrip: View {
    let days: [Date]
    let selected: Date
    let busy: [Bool]
    let onPick: (Date) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                let isToday = Calendar.current.isDateInToday(day)
                Button { onPick(day) } label: {
                    VStack(spacing: 3) {
                        Text(Self.weekday(day))
                            .font(Theme.Typography.text(11, weight: .regular, relativeTo: .caption2))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.hcSecondaryInk)
                        Text(day, format: .dateTime.day())
                            .font(Theme.Typography.text(15, weight: .bold))
                            .foregroundStyle(isSelected ? Color.white : isToday ? Color.hcAccent : Color.hcInk)
                        Circle()
                            .fill(busy.indices.contains(index) && busy[index] ? (isSelected ? Color.white : Color.hcAccent) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.hcAccent : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day()))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    /// "Seg", "Ter"…
    static func weekday(_ date: Date) -> String {
        let symbols = DateFormatter()
        symbols.locale = Locale(identifier: "pt_PT")
        let name = symbols.shortWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
            .replacingOccurrences(of: ".", with: "")
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

/// "Todos" and one pill per person, to show only one person's things.
struct PersonFilter: View {
    let people: [Member]
    @Binding var selection: NSManagedObjectID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                pill(Text("Todos"), isOn: selection == nil) { selection = nil }
                ForEach(people, id: \.objectID) { member in
                    pill(Text(verbatim: member.name ?? ""), isOn: selection == member.objectID) { selection = member.objectID }
                }
            }
        }
    }

    private func pill(_ label: Text, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(Theme.Typography.text(13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.hcInk)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isOn ? Color.hcAccent : Color.hcCard, in: Capsule())
                .overlay { Capsule().strokeBorder(isOn ? Color.clear : Color.hcSeparator, lineWidth: 1) }
                .frame(minHeight: Theme.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The grid shared by activities and chores: a leading column, then seven day columns with today marked.
struct WeekGrid<Header: View, Cell: View>: View {
    let days: [Date]
    let rowCount: Int
    @ViewBuilder let header: (Int) -> Header
    @ViewBuilder let cell: (Int, Int) -> Cell

    static var leadingWidth: CGFloat { 44 }

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: Self.leadingWidth, height: 22)
                ForEach(days, id: \.self) { day in
                    dayLetter(day)
                }
            }
            ForEach(0..<rowCount, id: \.self) { row in
                GridRow {
                    header(row).frame(width: Self.leadingWidth)
                    ForEach(days.indices, id: \.self) { column in
                        cell(row, column)
                    }
                }
            }
        }
    }

    private func dayLetter(_ day: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let letter = day.formatted(.dateTime.weekday(.narrow)).uppercased()
        return Text(verbatim: letter)
            .font(Theme.Typography.text(12, weight: .semibold))
            .foregroundStyle(isToday ? Color.white : Color.hcSecondaryInk)
            .frame(width: 28, height: 22)
            .background(isToday ? Color.hcAccent : Color.clear, in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day()))
    }
}

/// The activity's symbol on its child's colour (green when nobody is set).
struct ActivityIcon: View {
    @ObservedObject var activity: Activity
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: activity.symbol)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(Color(activity.child?.palette.foreground ?? Theme.Palette.accent))
            .frame(width: size, height: size)
            .background(Color(activity.child?.palette.soft ?? Theme.Palette.accentSoft), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .accessibilityHidden(true)
    }
}
