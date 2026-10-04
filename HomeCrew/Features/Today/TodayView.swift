import CoreData
import SwiftUI

/// The day at a glance: alerts, then activities with who takes them, then chores.
struct TodayView: View {
    @FetchRequest(fetchRequest: Activity.all()) private var activities: FetchedResults<Activity>
    @FetchRequest(fetchRequest: Chore.all()) private var chores: FetchedResults<Chore>
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>

    /// Which adult uses this iPhone, chosen once; until accounts map to members (invitations ticket).
    @AppStorage("meMemberID") private var meMemberID = ""
    @AppStorage("onlyMine") private var onlyMine = false
    @State private var isChoosingMe = false

    private let persistence = PersistenceController.shared

    var body: some View {
        let today = Date.now
        let digest = TodayDigest.build(
            day: today,
            activities: Array(activities),
            chores: Array(chores),
            me: onlyMine ? me : nil
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if !digest.alerts.isEmpty {
                        alertsCard(digest.alerts)
                    }
                    if !digest.activities.isEmpty {
                        card(systemImage: "figure.run") {
                            ForEach(digest.activities) { occurrence in
                                ActivityRow(occurrence: occurrence)
                            }
                        }
                    }
                    if !digest.chores.isEmpty {
                        card(systemImage: "checklist") {
                            ForEach(digest.chores, id: \.objectID) { chore in
                                ChoreRow(chore: chore, day: today) {
                                    persistence.toggleDone(chore, on: today)
                                }
                            }
                        }
                    }
                    if digest.isEmpty {
                        EmptyHint(systemImage: AppTab.today.systemImage, message: "Nada para hoje")
                            .padding(.top, 80)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationTitle(AppTab.today.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if me == nil {
                            isChoosingMe = true
                        } else {
                            onlyMine.toggle()
                        }
                    } label: {
                        if let me, onlyMine {
                            MemberAvatar(member: me, size: 30)
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityLabel(Text("Só eu"))
                    .accessibilityAddTraits(onlyMine ? .isSelected : [])
                    .contextMenu {
                        Button("Quem sou eu?") { isChoosingMe = true }
                    }
                }
            }
            .sheet(isPresented: $isChoosingMe) {
                WhoAmIView(adults: families.first?.adults ?? []) { member in
                    meMemberID = member.identifier?.uuidString ?? ""
                    onlyMine = true
                    isChoosingMe = false
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var me: Member? {
        guard !meMemberID.isEmpty else { return nil }
        return families.lazy.flatMap(\.sortedMembers).first { $0.identifier?.uuidString == meMemberID }
    }

    private func card<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Color.hcSecondaryInk)
                .accessibilityHidden(true)
            content()
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func alertsCard(_ alerts: [TodayAlert]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(alerts) { alert in
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: alert.systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.hcWarning)
                    Text(alert.title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Color.hcInk)
                    Spacer()
                    if let member = alert.member {
                        MemberAvatar(member: member, size: 28)
                    }
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hcWarningSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// Pick which adult uses this iPhone, so "só eu" knows what is yours.
struct WhoAmIView: View {
    let adults: [Member]
    let onPick: (Member) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Text("Quem sou eu?")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Color.hcInk)
            if adults.isEmpty {
                EmptyHint(systemImage: "person.2", message: "Ainda sem adultos")
            } else {
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(adults, id: \.objectID) { adult in
                        Button { onPick(adult) } label: {
                            VStack(spacing: Theme.Spacing.s) {
                                MemberAvatar(member: adult, size: 64)
                                Text(adult.name ?? "")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Color.hcInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

#Preview {
    TodayView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
