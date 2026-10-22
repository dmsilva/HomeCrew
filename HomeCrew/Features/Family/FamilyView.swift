import CoreData
import SwiftUI

/// The family: the children as cards across the top, the adults as a list below with their role and this
/// week's drives, and the drives split between two adults at the bottom.
struct FamilyView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Group {
                if let family = families.first {
                    ScrollView {
                        FamilySection(family: family, persistence: persistence)
                            .padding(.horizontal, 20)
                            .padding(.top, Theme.Spacing.l)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    ContentUnavailableView {
                        Image(systemName: AppTab.family.systemImage)
                            .font(Theme.Typography.heroIcon)
                            .foregroundStyle(Color.hcSecondaryInk)
                            .accessibilityHidden(true)
                    } actions: {
                        Button("Criar família") {
                            persistence.createFamily(named: String(localized: "A nossa família"))
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: Theme.minimumTapTarget)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hcBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// One family: a menu on the title, a "+" to add someone, a circle per person and the drives bar.
private struct FamilySection: View {
    @ObservedObject var family: Family
    let persistence: PersistenceController

    @State private var editing: EditorTarget?
    @State private var presentedShare: SharePresentation?
    @State private var isRenaming = false
    @State private var isInviting = false
    @State private var newName = ""
    @State private var isShowingCustody = false

    @FetchRequest(fetchRequest: Activity.all()) private var activities: FetchedResults<Activity>

    var body: some View {
        let drives = weekDrives
        let children = family.sortedMembers.filter { $0.kind == .child }
        let adults = family.adults
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Família")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Color.hcInk)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("family-header")
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
                    if !children.isEmpty {
                        Button {
                            isShowingCustody = true
                        } label: {
                            Label("Guarda", systemImage: "calendar")
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.hcInk)
                        .frame(width: 38, height: 38)
                        .background(Color.hcCard, in: Circle())
                        .overlay { Circle().strokeBorder(Color.hcSeparator, lineWidth: 1) }
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel(Text("Opções da família"))
            }

            if !children.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Os filhos")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(children, id: \.objectID) { child in
                                Button { editing = .existing(child) } label: {
                                    ChildCard(member: child, symbols: symbols(for: child))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 2)
                    }
                    .padding(.vertical, -8)
                }
            }

            Button { editing = .new } label: {
                Label("Adicionar", systemImage: "plus")
                    .font(Theme.Typography.text(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.hcAccent, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Adicionar membro"))

            if !adults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Adultos")
                    VStack(spacing: 0) {
                        ForEach(Array(adults.enumerated()), id: \.element.objectID) { index, adult in
                            if index > 0 { RowDivider(inset: 68) }
                            Button { editing = .existing(adult) } label: {
                                AdultRow(member: adult, drives: drives[adult.objectID, default: 0])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card(padding: 0)
                }
            }

            let driving = adults.filter { drives[$0.objectID, default: 0] > 0 }
            if driving.count >= 2 {
                DrivesBalance(adults: Array(driving.prefix(2)), drives: drives)
            }
        }
        .navigationDestination(isPresented: $isShowingCustody) {
            CustodyView(family: family)
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

    /// How many times each adult takes or brings someone this week.
    private var weekDrives: [NSManagedObjectID: Int] {
        var counts: [NSManagedObjectID: Int] = [:]
        let familyActivities = activities.filter { $0.family == family }
        for day in ActivitySchedule.week(containing: .now) {
            for occurrence in ActivitySchedule.occurrences(of: familyActivities, on: day) where !occurrence.isCancelled {
                for driver in [occurrence.dropOff, occurrence.pickUp].compactMap({ $0 }) {
                    counts[driver.objectID, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// The child's activities as their icons, each once.
    private func symbols(for child: Member) -> [String] {
        activities.filter { $0.child == child }.map(\.symbol).uniqued()
    }

    @MainActor
    private func presentShare(for role: Role) async {
        if let share = try? await persistence.share(family) {
            presentedShare = SharePresentation(share: share, role: role)
        }
    }
}

/// A child as a small card: their colour circle, name and age, and a rose ring with "Doente" while ill.
private struct ChildCard: View {
    @ObservedObject var member: Member
    let symbols: [String]

    var body: some View {
        let isIll = member.activeEpisode != nil
        VStack(spacing: 6) {
            MemberAvatar(member: member, size: 52)
                .padding(isIll ? 3 : 0)
                .overlay {
                    if isIll { Circle().strokeBorder(Color.hcWarning, lineWidth: 2) }
                }
            Text(member.name ?? "")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Color.hcInk)
                .lineLimit(1)
            Group {
                if isIll {
                    Text("Doente").foregroundStyle(Color.hcWarning)
                } else if let age = member.age(on: .now) {
                    Text("\(age) anos").foregroundStyle(Color.hcSecondaryInk)
                }
            }
            .font(Theme.Typography.caption)
            if !symbols.isEmpty {
                HStack(spacing: 4) {
                    ForEach(symbols.prefix(3), id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(member.palette.foreground))
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: 104)
        .padding(.vertical, 14)
        .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Color.hcSeparator, lineWidth: 1) }
        .shadow(color: Color(UIColor(hex: 0x18231F)).opacity(0.06), radius: 10, y: 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// An adult as a row: their circle, name, role and how many times they drive this week.
private struct AdultRow: View {
    @ObservedObject var member: Member
    let drives: Int

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name ?? "")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                Text(member.role.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
            }
            Spacer()
            if drives > 0 {
                Label {
                    Text(verbatim: "\(drives)")
                } icon: {
                    Image(systemName: "car")
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Color.hcSecondaryInk)
                .accessibilityLabel(Text("\(drives) boleias esta semana"))
            }
            Chevron()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// This week's drives split between two adults, as one bar in their colours.
private struct DrivesBalance: View {
    let adults: [Member]
    let drives: [NSManagedObjectID: Int]

    var body: some View {
        let first = adults[0]
        let second = adults[1]
        let a = drives[first.objectID, default: 0]
        let b = drives[second.objectID, default: 0]
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Boleias esta semana")
            HStack(spacing: 10) {
                MemberAvatar(member: first, size: 32)
                GeometryReader { proxy in
                    let total = max(a + b, 1)
                    let width = proxy.size.width - 4
                    HStack(spacing: 4) {
                        Color(first.palette.foreground).opacity(0.7).frame(width: width * CGFloat(a) / CGFloat(total))
                        Color(second.palette.foreground).opacity(0.7)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                MemberAvatar(member: second, size: 32)
            }
            .card()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Boleias esta semana: \(first.name ?? "") \(a), \(second.name ?? "") \(b)"))
    }
}

#Preview {
    FamilyView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
