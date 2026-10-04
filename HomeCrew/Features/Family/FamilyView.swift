import CoreData
import SwiftUI

struct FamilyView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var presentedShare: SharePresentation?

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
                    List(families, id: \.objectID) { family in
                        FamilyRow(family: family, onSave: persistence.save) {
                            Task { await present(shareFor: family) }
                        }
                        .listRowBackground(Color.hcCard)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationTitle(AppTab.family.title)
            .sheet(item: $presentedShare) { presentation in
                CloudSharingView(share: presentation.share, container: persistence.cloudKitContainer)
                    .ignoresSafeArea()
            }
        }
    }

    @MainActor
    private func present(shareFor family: Family) async {
        if let share = try? await persistence.share(family) {
            presentedShare = SharePresentation(share: share)
        }
    }
}

private struct FamilyRow: View {
    @ObservedObject var family: Family
    let onSave: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            TextField("Nome da família", text: Binding(
                get: { family.name ?? "" },
                set: { family.name = $0 }
            ))
            .font(Theme.Typography.cardTitle)
            .foregroundStyle(Color.hcInk)
            .onSubmit(onSave)

            Button(action: onShare) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .frame(minWidth: Theme.minimumTapTarget, minHeight: Theme.minimumTapTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Partilhar"))
        }
    }
}

#Preview {
    FamilyView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
