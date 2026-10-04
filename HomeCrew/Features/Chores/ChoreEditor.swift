import SwiftUI

enum ChoreEditorTarget: Identifiable {
    case new
    case existing(Chore)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let chore): chore.objectID.uriRepresentation().absoluteString
        }
    }
}

struct ChoreEditor: View {
    let target: ChoreEditorTarget
    let family: Family
    let persistence: PersistenceController

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ChoreDraft()
    @State private var frequency = Frequency.daily
    @State private var weekdays: Set<Int> = []
    @State private var isConfirmingDelete = false

    enum Frequency: Hashable {
        case once, daily, weekly
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tarefa", text: $draft.title)
                        .font(Theme.Typography.cardTitle)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(family.sortedMembers, id: \.objectID) { member in
                                assigneeButton(member)
                            }
                        }
                    }
                }

                Section {
                    Picker("Repetição", selection: $frequency) {
                        Text("Uma vez").tag(Frequency.once)
                        Text("Diária").tag(Frequency.daily)
                        Text("Semanal").tag(Frequency.weekly)
                    }
                    .pickerStyle(.segmented)

                    if frequency == .weekly {
                        WeekdayPicker(selection: $weekdays)
                    }

                    DatePicker(
                        frequency == .once ? LocalizedStringKey("Dia") : LocalizedStringKey("Início"),
                        selection: $draft.startDate,
                        displayedComponents: .date
                    )
                }

                if case .existing = target {
                    Section {
                        Button("Apagar", role: .destructive) { isConfirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isNew ? Text("Nova tarefa") : Text("Editar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!composedDraft.isValid)
                }
            }
            .confirmationDialog("Apagar tarefa?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Apagar", role: .destructive) {
                    if case .existing(let chore) = target { persistence.delete(chore) }
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadDraft)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    /// The draft with the recurrence rebuilt from the frequency and weekday controls.
    private var composedDraft: ChoreDraft {
        var result = draft
        switch frequency {
        case .once: result.recurrence = .once
        case .daily: result.recurrence = .daily
        case .weekly: result.recurrence = .weekly(weekdays)
        }
        return result
    }

    private func assigneeButton(_ member: Member) -> some View {
        let isSelected = draft.assignee == member
        return Button {
            draft.assignee = isSelected ? nil : member
        } label: {
            MemberAvatar(member: member, size: 44)
                .overlay {
                    Circle().strokeBorder(Color.hcAccent, lineWidth: isSelected ? 3 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(member.name ?? ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func loadDraft() {
        switch target {
        case .new:
            draft = ChoreDraft()
        case .existing(let chore):
            draft = ChoreDraft(chore)
        }
        switch draft.recurrence {
        case .once: frequency = .once
        case .daily: frequency = .daily
        case .weekly(let days):
            frequency = .weekly
            weekdays = days
        }
    }

    private func save() {
        let result = composedDraft
        switch target {
        case .new: persistence.addChore(result, to: family)
        case .existing(let chore): persistence.update(chore, with: result)
        }
        dismiss()
    }
}

/// Seven round toggles, Monday first as is usual in Portugal.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    /// Calendar weekday numbers (1 = Sunday) in Monday-first order.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 0) {
            ForEach(Self.mondayFirst, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(symbols[weekday - 1])
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundStyle(isOn ? Color.white : Color.hcInk)
                        .frame(width: 34, height: 34)
                        .background(isOn ? Color.hcAccent : Color.hcAccentSoft, in: Circle())
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Calendar.current.weekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}
