import CoreData
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
    @State private var isConfirmingRemoveAccess = false
    @State private var role: Role = .parent
    @State private var caredChildren: Set<NSManagedObjectID> = []
    @State private var careWeekdays: Set<Int> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        Text(verbatim: draft.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                            .font(Theme.Typography.display(26))
                            .foregroundStyle(Color.hcNight)
                            .frame(width: 56, height: 56)
                            .background(Color(Theme.Palette.members[Int(draft.colorIndex) % Theme.Palette.members.count].soft), in: Circle())
                            .accessibilityHidden(true)
                        TextField("Nome", text: $draft.name)
                            .font(Theme.Typography.display(26))
                            .textInputAutocapitalization(.words)
                    }

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

                if draft.kind == .adult {
                    RoleFields(family: family, role: $role, children: $caredChildren, weekdays: $careWeekdays)
                }

                if case .existing(let member) = target {
                    Section {
                        if persistence.hasAccess(member) {
                            Button("Remover acesso", role: .destructive) { isConfirmingRemoveAccess = true }
                                .frame(maxWidth: .infinity)
                        }
                        Button("Remover", role: .destructive) { isConfirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .editorStyle()
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
            .confirmationDialog("Remover acesso?", isPresented: $isConfirmingRemoveAccess, titleVisibility: .visible) {
                Button("Remover acesso", role: .destructive) {
                    if case .existing(let member) = target {
                        Task { await persistence.removeAccess(of: member) }
                    }
                    dismiss()
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
                .fill(Color(pair.soft))
                .frame(width: 36, height: 36)
                .padding(3)
                .overlay {
                    Circle().strokeBorder(Color.hcNight, lineWidth: isSelected ? 3 : 0)
                }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(Color.hcNight)
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
            role = member.role
            caredChildren = Set(member.caredChildrenList.map(\.objectID))
            careWeekdays = member.careWeekdays
        }
    }

    private func save() {
        let member: Member
        switch target {
        case .new: member = persistence.addMember(draft, to: family)
        case .existing(let existing):
            persistence.update(existing, with: draft)
            member = existing
        }
        if draft.kind == .adult, member.role != role || Set(member.caredChildrenList.map(\.objectID)) != caredChildren
            || member.careWeekdays != careWeekdays {
            persistence.setRole(role, children: caredChildren, weekdays: careWeekdays, for: member)
        }
        dismiss()
    }
}
