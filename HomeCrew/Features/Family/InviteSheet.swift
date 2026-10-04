import CoreData
import SwiftUI

/// The role choice shared by the invite form and the member editor: three icons, and for a carer
/// which children and which days.
struct RoleFields: View {
    let family: Family
    @Binding var role: Role
    @Binding var children: Set<NSManagedObjectID>
    @Binding var weekdays: Set<Int>

    var body: some View {
        Section {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Role.allCases) { option in
                    let isSelected = role == option
                    Button {
                        role = option
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: option.systemImage)
                                .font(.title2)
                                .frame(width: 52, height: 52)
                                .background(isSelected ? Color.hcNight : Color.hcMuted, in: Circle())
                                .foregroundStyle(isSelected ? Color.hcLime : Color.hcInk)
                            Text(option.title)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Color.hcInk)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("role-\(option.rawValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        } footer: {
            Text(summary)
        }

        if role == .carer {
            Section {
                let kids = family.sortedMembers.filter { $0.kind == .child }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(kids, id: \.objectID) { child in
                            let isOn = children.contains(child.objectID)
                            Button {
                                if isOn { children.remove(child.objectID) } else { children.insert(child.objectID) }
                            } label: {
                                SelectableAvatar(member: child, isSelected: isOn)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(child.name ?? ""))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
                WeekdayPicker(selection: $weekdays)
            } header: {
                Label("Filhos e dias", systemImage: "calendar")
            } footer: {
                Text("Sem dias escolhidos, vê todos os dias.")
            }
        }
    }

    private var summary: LocalizedStringKey {
        switch role {
        case .parent: "Vê e edita tudo."
        case .carer: "Vê só os filhos e os dias escolhidos."
        case .guest: "Vê só a agenda, sem editar."
        }
    }
}

/// Invite someone: name and role first, then Apple's sharing sheet sends the link by Messages or WhatsApp.
struct InviteSheet: View {
    let family: Family
    let onInvite: (Role) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = InviteDraft()

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $draft.name)
                        .font(Theme.Typography.cardTitle)
                        .textInputAutocapitalization(.words)
                }
                RoleFields(family: family, role: $draft.role, children: $draft.children, weekdays: $draft.weekdays)
            }
            .editorStyle()
            .navigationTitle(Text("Convidar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Convidar") {
                        persistence.addInvitee(draft, to: family)
                        onInvite(draft.role)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }
}
