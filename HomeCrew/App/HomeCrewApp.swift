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
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                screen(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(.hcAccent)
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
