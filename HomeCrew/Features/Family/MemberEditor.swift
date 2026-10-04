import SwiftUI

/// Which member the editor works on; drives `.sheet(item:)`.
enum EditorTarget: Identifiable {
    case new
    case existing(Member)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let member): member.objectID.uriRepresentation().absoluteString
        }
    }
}

struct MemberEditor: View {
    let target: EditorTarget
    let family: Family
    let persistence: PersistenceController

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MemberDraft()
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $draft.name)
                        .font(Theme.Typography.cardTitle)
                        .textInputAutocapitalization(.words)

                    Picker("Tipo", selection: $draft.kind) {
                        Label("Adulto", systemImage: "person.fill").tag(Member.Kind.adult)
                        Label("Criança", systemImage: "figure.child").tag(Member.Kind.child)
                    }
                    .pickerStyle(.segmented)

                    DatePicker("Data de nascimento", selection: $draft.birthDate, in: ...Date.now, displayedComponents: .date)
                }

                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(Theme.Palette.members.indices, id: \.self) { index in
                            colorSwatch(index: Int16(index))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if case .existing = target {
                    Section {
                        Button("Remover", role: .destructive) { isConfirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isNew ? Text("Novo membro") : Text("Editar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!draft.isValid)
                }
            }
            .confirmationDialog("Remover membro?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Remover", role: .destructive) {
                    if case .existing(let member) = target { persistence.delete(member) }
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

    private func colorSwatch(index: Int16) -> some View {
        let pair = Theme.Palette.members[Int(index)]
        let isSelected = draft.colorIndex == index
        return Button {
            draft.colorIndex = index
        } label: {
            Circle()
                .fill(Color(pair.foreground))
                .frame(width: 32, height: 32)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Cor \(Int(index) + 1)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func loadDraft() {
        switch target {
        case .new:
            draft = MemberDraft()
            draft.colorIndex = family.nextColorIndex
        case .existing(let member):
            draft = MemberDraft(member)
        }
    }

    private func save() {
        switch target {
        case .new: persistence.addMember(draft, to: family)
        case .existing(let member): persistence.update(member, with: draft)
        }
        dismiss()
    }
}
