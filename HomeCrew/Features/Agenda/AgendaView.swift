import CoreData
import SwiftUI

/// Activities by week, and the household chores, behind one segmented switch.
struct AgendaView: View {
    enum Segment: Hashable {
        case activities, chores
    }

    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var section = Segment.activities
    @State private var editingActivity: ActivityEditorTarget?
    @State private var editingChore: ChoreEditorTarget?

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Secção", selection: $section) {
                    Label("Atividades", systemImage: "figure.run").tag(Segment.activities)
                    Label("Tarefas", systemImage: "checklist").tag(Segment.chores)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)

                switch section {
                case .activities:
                    ActivitiesWeekView(onEdit: { editingActivity = .existing($0) })
                case .chores:
                    ChoresListView(onEdit: { editingChore = .existing($0) })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationTitle(AppTab.agenda.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        switch section {
                        case .activities: editingActivity = .new
                        case .chores: editingChore = .new
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(section == .activities ? Text("Nova atividade") : Text("Nova tarefa"))
                    .disabled(families.isEmpty)
                }
            }
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
}

/// The family's chores with a tick for today.
struct ChoresListView: View {
    @FetchRequest(fetchRequest: Chore.all()) private var chores: FetchedResults<Chore>
    let onEdit: (Chore) -> Void

    private let persistence = PersistenceController.shared

    var body: some View {
        if chores.isEmpty {
            EmptyHint(systemImage: "checklist", message: "Sem tarefas")
        } else {
            List {
                ForEach(chores, id: \.objectID) { chore in
                    ChoreRow(chore: chore, day: .now) {
                        persistence.toggleDone(chore, on: .now)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(chore) }
                    .listRowBackground(Color.hcCard)
                }
                .onDelete { offsets in
                    offsets.map { chores[$0] }.forEach { persistence.delete($0) }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// One icon and one short line for an empty list.
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
