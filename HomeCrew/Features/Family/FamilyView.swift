import CoreData
import SwiftUI

struct FamilyView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Group {
                if families.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: AppTab.family.systemImage)
                            .font(Theme.Typography.heroIcon)
                            .foregroundStyle(Color.hcAccent)
                            .accessibilityHidden(true)
                    } description: {
                        Text("Ainda sem membros")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Color.hcSecondaryInk)
                    } actions: {
                        Button("Criar família") {
                            persistence.createFamily(named: String(localized: "A nossa família"))
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: Theme.minimumTapTarget)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            ForEach(families, id: \.objectID) { family in
                                FamilySection(family: family, persistence: persistence)
                            }
                        }
                        .padding(Theme.Spacing.l)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationTitle(AppTab.family.title)
        }
    }
}

/// One family: its name, a card per person, and a card to add someone.
private struct FamilySection: View {
    @ObservedObject var family: Family
    let persistence: PersistenceController

    @State private var editing: EditorTarget?
    @State private var presentedShare: SharePresentation?
    @State private var isRenaming = false
    @State private var isInviting = false
    @State private var newName = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text(family.name ?? "")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcSecondaryInk)
                Spacer()
                Menu {
                    Button {
                        newName = family.name ?? ""
                        isRenaming = true
                    } label: {
                        Label("Mudar nome", systemImage: "pencil")
                    }
                    Button {
                        isInviting = true
                    } label: {
                        Label("Convidar", systemImage: "person.crop.circle.badge.plus")
                    }
                    Button {
                        Task { await presentShare(for: .parent) }
                    } label: {
                        Label("Gerir acessos", systemImage: "person.2.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
                }
                .accessibilityLabel(Text("Opções da família"))
            }

            LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                ForEach(family.sortedMembers, id: \.objectID) { member in
                    Button { editing = .existing(member) } label: { MemberCard(member: member) }
                        .buttonStyle(.plain)
                }
                Button { editing = .new } label: { AddMemberCard() }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Adicionar membro"))
            }

            if family.sortedMembers.contains(where: { $0.kind == .child }) {
                NavigationLink {
                    CustodyView(family: family)
                } label: {
                    Label("Guarda", systemImage: "calendar")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Color.hcInk)
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $editing) { target in
            MemberEditor(target: target, family: family, persistence: persistence)
        }
        .sheet(item: $presentedShare) { presentation in
            CloudSharingView(share: presentation.share, container: persistence.cloudKitContainer, role: presentation.role)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isInviting) {
            InviteSheet(family: family) { role in
                Task {
                    // Let the invite form close before Apple's sharing sheet opens.
                    try? await Task.sleep(for: .milliseconds(600))
                    await presentShare(for: role)
                }
            }
        }
        .alert("Mudar nome", isPresented: $isRenaming) {
            TextField("Nome da família", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { persistence.rename(family, to: newName) }
        }
    }

    @MainActor
    private func presentShare(for role: Role) async {
        if let share = try? await persistence.share(family) {
            presentedShare = SharePresentation(share: share, role: role)
        }
    }
}

private struct MemberCard: View {
    @ObservedObject var member: Member

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            MemberAvatar(member: member)
            Text(member.name ?? "")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Color.hcInk)
                .lineLimit(1)
            if member.kind == .child, let age = member.age(on: .now) {
                Text("\(age) anos")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
            } else {
                Image(systemName: "person.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
                    .accessibilityLabel(Text("Adulto"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

private struct AddMemberCard: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color.hcAccent)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Color.hcAccentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview {
    FamilyView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
