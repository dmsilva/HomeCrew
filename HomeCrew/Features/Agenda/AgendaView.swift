import CoreData
import SwiftUI

/// The week: a day at a time for activities, or the chores as a grid of days, switched at the top.
/// Swipe sideways or use the arrows for another week; "Hoje" comes back to this one.
struct AgendaView: View {
    enum Segment: Hashable {
        case activities, chores
    }

    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var section = Segment.activities
    @State private var weekOffset = 0
    @State private var editingActivity: ActivityEditorTarget?
    @State private var editingChore: ChoreEditorTarget?

    private let persistence = PersistenceController.shared

    var body: some View {
        let days = ActivitySchedule.week(containing: referenceDate)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(days)
                    switch section {
                    case .activities:
                        ActivitiesWeekView(days: days, onEdit: { editingActivity = .existing($0) })
                    case .chores:
                        ChoresWeekView(days: days, onEdit: { editingChore = .existing($0) })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, Theme.Spacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) * 2 else { return }
                    withAnimation(.snappy) { weekOffset += drag.translation.width < 0 ? 1 : -1 }
                }
            )
            .background(Color.hcBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingActivity) { target in
                if let family = families.first {
                    ActivityEditor(target: target, family: family, persistence: persistence)
                }
            }
            .sheet(item: $editingChore) { target in
                if let family = families.first {
                    ChoreEditor(target: target, family: family, persistence: persistence)
                }
            }
        }
    }

    private var referenceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weekOffset, to: .now) ?? .now
    }

    private func header(_ days: [Date]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Agenda")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Color.hcInk)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("agenda-header")
                Spacer()
                HStack(spacing: 6) {
                    segmentButton(.activities, label: "Atividades")
                    segmentButton(.chores, label: "Tarefas")
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                if let first = days.first {
                    Text(first, format: .dateTime.month(.wide).year())
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Color.hcInk)
                        .textCase(nil)
                }
                Spacer()
                if weekOffset != 0 {
                    Button("Hoje") { withAnimation(.snappy) { weekOffset = 0 } }
                        .font(Theme.Typography.text(13, weight: .semibold))
                        .foregroundStyle(Color.hcAccent)
                        .accessibilityHint(Text("Voltar a esta semana"))
                }
                weekArrow("chevron.left", label: "Semana anterior", step: -1)
                weekArrow("chevron.right", label: "Semana seguinte", step: 1)
            }
        }
        .padding(.top, Theme.Spacing.l)
    }

    private func weekArrow(_ systemImage: String, label: LocalizedStringKey, step: Int) -> some View {
        Button {
            withAnimation(.snappy) { weekOffset += step }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.hcInk)
                .frame(width: 36, height: 36)
                .background(Color.hcCard, in: Circle())
                .overlay { Circle().strokeBorder(Color.hcSeparator, lineWidth: 1) }
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func segmentButton(_ segment: Segment, label: LocalizedStringKey) -> some View {
        let isOn = section == segment
        return Button {
            section = segment
        } label: {
            Text(label)
                .font(Theme.Typography.text(13, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.hcInk)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(isOn ? Color.hcAccent : Color.hcCard, in: Capsule())
                .overlay { Capsule().strokeBorder(isOn ? Color.clear : Color.hcSeparator, lineWidth: 1) }
                .frame(minHeight: Theme.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The chores as a grid: a row per chore with its icon on the assignee's colour, a square per day it is due.
/// Today's square (and earlier ones) can be ticked; a green square with a white tick is done.
struct ChoresWeekView: View {
    @FetchRequest(fetchRequest: Chore.all()) private var allChores: FetchedResults<Chore>
    let days: [Date]
    let onEdit: (Chore) -> Void

    @Environment(\.access) private var access
    private let persistence = PersistenceController.shared

    var body: some View {
        let chores = allChores.filter { chore in
            access.canSee(chore.assignee) && days.contains { chore.occurs(on: $0) }
        }
        if chores.isEmpty {
            EmptyHint(systemImage: "checklist", message: "Sem tarefas")
        } else {
            let done = chores.reduce(0) { total, chore in total + days.filter { chore.completion(on: $0) != nil }.count }
            let due = chores.reduce(0) { total, chore in total + days.filter { chore.occurs(on: $0) }.count }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Esta semana") {
                    Text(verbatim: "\(done)/\(due)")
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(done) de \(due) feitas esta semana"))
                }
                WeekGrid(days: days, rowCount: chores.count) { row in
                    choreIcon(chores[row])
                } cell: { row, column in
                    dayCell(chores[row], day: days[column])
                }
                .card(padding: 12)
            }
        }
    }

    private func choreIcon(_ chore: Chore) -> some View {
        Button {
            if access.canEdit { onEdit(chore) }
        } label: {
            Image(systemName: chore.symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(chore.assignee?.palette.foreground ?? Theme.Palette.ink))
                .frame(width: 40, height: 40)
                .background(Color(chore.assignee?.palette.soft ?? Theme.Palette.muted), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(chore.title ?? ""), \(chore.assignee?.name ?? "")"))
        .accessibilityIdentifier("chore-edit-\(chore.title ?? "")")
    }

    private func dayCell(_ chore: Chore, day: Date) -> some View {
        let isDue = chore.occurs(on: day)
        let isDone = chore.completion(on: day) != nil
        let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: .now)
        let isToday = Calendar.current.isDateInToday(day)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
        let colour = Color(chore.assignee?.palette.soft ?? Theme.Palette.accentSoft)

        return Button {
            persistence.toggleDone(chore, on: day)
        } label: {
            ZStack {
                if !isDue {
                    shape.fill(Color.hcMuted)
                } else if isDone {
                    shape.fill(Color.hcAccent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    shape.fill(isFuture ? Color.hcCard : colour.opacity(0.5))
                    shape.strokeBorder(colour, lineWidth: 2)
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isDue || isFuture || !access.canEdit)
        .accessibilityLabel(Text("\(chore.title ?? ""), \(day.formatted(.dateTime.weekday(.wide)))"))
        .accessibilityValue(isDone ? Text("Feita") : Text("Por fazer"))
        .accessibilityIdentifier(isToday ? "chore-week-\(chore.title ?? "")" : "")
        .accessibilityHidden(!isDue)
    }
}

/// One icon and one short line for an empty screen.
struct EmptyHint: View {
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Image(systemName: systemImage)
                .font(Theme.Typography.heroIcon)
                .foregroundStyle(Color.hcSecondaryInk)
                .accessibilityHidden(true)
        } description: {
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Color.hcSecondaryInk)
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview {
    AgendaView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
