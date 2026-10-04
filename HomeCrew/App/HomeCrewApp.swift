import SwiftUI

@main
struct HomeCrewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.managedObjectContext, PersistenceController.shared.viewContext)
        }
    }
}

struct RootTabView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var selection: AppTab = .today
    @State private var isWaitingForInvite = false

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                screen(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(.hcAccent)
        .fullScreenCover(isPresented: needsFirstRun) {
            FirstRunView(
                onCreate: { PersistenceController.shared.createFamily(named: $0) },
                onWaitForInvite: { isWaitingForInvite = true }
            )
        }
    }

    /// Closes on its own once a family exists, whether created here or arriving through an invitation.
    private var needsFirstRun: Binding<Bool> {
        Binding(
            get: { families.isEmpty && !isWaitingForInvite },
            set: { if !$0 { isWaitingForInvite = true } }
        )
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .agenda: AgendaView()
        case .family: FamilyView()
        case .health: HealthView()
        }
    }
}

#Preview {
    RootTabView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
