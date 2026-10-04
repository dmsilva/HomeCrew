import CoreData
import SwiftUI

/// The week (Direção E): activities or chores as a grid of days, switched by two icons.
/// Swipe sideways for another week; tap the title to come back to this one.
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
        HStack {
            Button {
                withAnimation(.snappy) { weekOffset = 0 }
            } label: {
                Group {
                    if weekOffset == 0 {
                        Text("Semana")
                    } else if let first = days.first, let last = days.last {
                        Text(verbatim: "\(first.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day().month(.abbreviated)))")
                    }
                }
                .font(Theme.Typography.display(weekOffset == 0 ? 34 : 26))
                .foregroundStyle(Color.hcInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agenda-header")
            .accessibilityHint(weekOffset == 0 ? Text("") : Text("Voltar a esta semana"))

            Spacer()

            HStack(spacing: 0) {
                segmentButton(.activities, systemImage: "soccerball", label: "Atividades")
                segmentButton(.chores, systemImage: "checkmark", label: "Tarefas")
            }
            .padding(4)
            .background(Color.hcMuted, in: Capsule())
        }
        .padding(.top, Theme.Spacing.l)
    }

    private func segmentButton(_ segment: Segment, systemImage: String, label: LocalizedStringKey) -> some View {
        let isOn = section == segment
        return Button {
            section = segment
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isOn ? Color.hcLime : Color.hcInk)
                .frame(width: 44, height: 44)
                .background(isOn ? Color.hcNight : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The chores as a grid: a row per chore with its icon on the assignee's colour, a square per day it is due.
/// Today's square (and earlier ones) can be ticked; a dark square with a lime tick is done.
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
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                WeekGrid(days: days, rowCount: chores.count) { row in
                    choreIcon(chores[row])
                } cell: { row, column in
                    dayCell(chores[row], day: days[column])
                }
                Text(verbatim: "\(done)/\(due)")
                    .font(Theme.Typography.display(28))
                    .foregroundStyle(Color.hcInk)
                    .monospacedDigit()
                    .accessibilityLabel(Text("\(done) de \(due) feitas esta semana"))
            }
        }
    }

    private func choreIcon(_ chore: Chore) -> some View {
        Button {
            if access.canEdit { onEdit(chore) }
        } label: {
            Image(systemName: chore.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.hcNight)
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
                    shape.fill(Color.hcNight)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Color.hcLime)
                } else {
                    shape.fill(isFuture ? Color.hcCard : colour.opacity(0.35))
                    shape.strokeBorder(colour, lineWidth: 3)
                }
            }
            .frame(height: 48)
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
                .foregroundStyle(Color.hcAccent)
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
