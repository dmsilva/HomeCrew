import SwiftUI

/// Shown right after opening an episode: the coming activities to cancel, ticked by default,
/// and nothing changes until "Cancelar" is tapped.
struct IllnessAgendaSheet: View {
    let occurrences: [ActivityOccurrence]
    let assignee: Member?

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var addWarningTasks = true

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(occurrences) { occurrence in
                        let isOn = selected.contains(occurrence.id)
                        Button {
                            if isOn { selected.remove(occurrence.id) } else { selected.insert(occurrence.id) }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                ActivityIcon(activity: occurrence.activity, size: 36)
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text(occurrence.activity.title ?? "")
                                        .font(Theme.Typography.cardTitle)
                                        .foregroundStyle(Color.hcInk)
                                    Text(occurrence.start, format: .dateTime.weekday(.wide).hour().minute())
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Color.hcSecondaryInk)
                                }
                                Spacer()
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(isOn ? Color.hcWarning : Color.hcSeparator)
                            }
                        }
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                } header: {
                    Label("Cancelar estas atividades?", systemImage: "calendar.badge.minus")
                }
                .listRowBackground(Color.hcCard)

                Section {
                    Toggle(isOn: $addWarningTasks) {
                        Label("Tarefa para avisar escola ou treinador", systemImage: "checklist")
                    }
                }
                .listRowBackground(Color.hcCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Agora não") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancelar \(selected.count)") {
                        persistence.cancelForIllness(
                            occurrences.filter { selected.contains($0.id) },
                            addWarningTasks: addWarningTasks,
                            assignee: assignee
                        )
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .onAppear { selected = Set(occurrences.map(\.id)) }
    }
}
