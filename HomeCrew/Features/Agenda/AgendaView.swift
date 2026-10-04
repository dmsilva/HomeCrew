import CoreData
import SwiftUI

struct AgendaView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @FetchRequest(fetchRequest: Chore.all()) private var chores: FetchedResults<Chore>
    @State private var editing: ChoreEditorTarget?

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Group {
                if chores.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: "checklist")
                            .font(Theme.Typography.heroIcon)
                            .foregroundStyle(Color.hcAccent)
                            .accessibilityHidden(true)
                    } description: {
                        Text("Sem tarefas")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Color.hcSecondaryInk)
                    }
                } else {
                    List {
                        ForEach(chores, id: \.objectID) { chore in
                            ChoreRow(chore: chore, day: .now) {
                                persistence.toggleDone(chore, on: .now)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = .existing(chore) }
                            .listRowBackground(Color.hcCard)
                        }
                        .onDelete { offsets in
                            offsets.map { chores[$0] }.forEach { persistence.delete($0) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationTitle(AppTab.agenda.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = .new } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Nova tarefa"))
                    .disabled(families.isEmpty)
                }
            }
            .sheet(item: $editing) { target in
                if let family = families.first {
                    ChoreEditor(target: target, family: family, persistence: persistence)
                }
            }
        }
    }
}

#Preview {
    AgendaView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
