import SwiftUI

@main
struct HomeCrewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            PersistenceController.shared.seedDemoFamilyIfEmpty()
        }
    }

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
    @State private var creating: HomeTabBar.CreateAction?
    @AppStorage("meMemberID") private var meMemberID = ""
    @Environment(\.scenePhase) private var scenePhase

    private let persistence = PersistenceController.shared

    var body: some View {
        let access = self.access
        TabView(selection: $selection) {
            ForEach(access.tabs) { tab in
                screen(for: tab)
                    .toolbar(.hidden, for: .tabBar)
                    // Keeps the last row of every screen clear of the floating bar.
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: HomeTabBar.height) }
                    .tag(tab)
            }
        }
        .overlay(alignment: .bottom) {
            if !families.isEmpty {
                HomeTabBar(
                    tabs: access.tabs,
                    selection: $selection,
                    onCreate: access.canEdit ? { creating = $0 } : nil
                )
            }
        }
        .sheet(item: $creating) { action in
            if let family = families.first {
                switch action {
                case .activity: ActivityEditor(target: .new, family: family, persistence: persistence)
                case .chore: ChoreEditor(target: .new, family: family, persistence: persistence)
                }
            }
        }
        .environment(\.access, access)
        .tint(.hcAccent)
        .onAppear { keepSelectionVisible(in: access) }
        .task(id: joinedOnly) { await recogniseAccount() }
        .onChange(of: access) { _, newAccess in keepSelectionVisible(in: newAccess) }
        .onChange(of: scenePhase) { _, phase in
            // Catches what changed while away, such as who uses this iPhone.
            if phase == .active {
                Task {
                    await DoseReminderCenter.shared.refresh()
                    await AgendaReminderCenter.shared.refresh()
                    WidgetSync.shared.scheduleWrite()
                }
            }
        }
        .fullScreenCover(isPresented: needsFirstRun) {
            FirstRunView(
                onCreate: { persistence.createFamily(named: $0) },
                onWaitForInvite: { isWaitingForInvite = true }
            )
        }
        .fullScreenCover(isPresented: needsIdentity) {
            WhoAmIView(adults: families.flatMap(\.adults)) { member in
                meMemberID = member.identifier?.uuidString ?? ""
                Task {
                    if let account = await persistence.currentAccountRecordName() {
                        persistence.link(member, toAccount: account)
                    }
                }
            }
        }
    }

    private var me: Member? {
        families.lazy.compactMap { $0.member(withID: meMemberID) }.first
    }

    /// Whoever created a family here is a parent; someone who joined a shared one gets the role they were invited with.
    private var access: AccessPolicy {
        if let me { return AccessPolicy(for: me) }
        return joinedOnly ? .unidentified : .full
    }

    private var joinedOnly: Bool {
        !families.isEmpty && families.allSatisfy(persistence.isJoined)
    }

    /// Closes on its own once a family exists, whether created here or arriving through an invitation.
    private var needsFirstRun: Binding<Bool> {
        Binding(
            get: { families.isEmpty && !isWaitingForInvite },
            set: { if !$0 { isWaitingForInvite = true } }
        )
    }

    /// After joining someone's family, the app asks once which of its adults this is, to know their role.
    private var needsIdentity: Binding<Bool> {
        Binding(get: { joinedOnly && me == nil }, set: { _ in })
    }

    /// On a reinstall or a second iPhone, the account already linked to a member answers "who am I".
    private func recogniseAccount() async {
        guard joinedOnly, me == nil, let account = await persistence.currentAccountRecordName() else { return }
        if let member = families.lazy.flatMap(\.adults).first(where: { $0.accountID == account }) {
            meMemberID = member.identifier?.uuidString ?? ""
        }
    }

    private func keepSelectionVisible(in access: AccessPolicy) {
        if !access.tabs.contains(selection), let first = access.tabs.first {
            selection = first
        }
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

extension HomeTabBar.CreateAction: Identifiable {
    var id: Self { self }
}
