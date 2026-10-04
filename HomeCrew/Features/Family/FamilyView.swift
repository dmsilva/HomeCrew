import CoreData
import SwiftUI

/// The family as big colour circles on night (Direção E): drives this week on each adult, activity icons
/// on each child, a coral ring and the latest temperature on whoever is ill, and the week's drives split
/// between the adults at the bottom.
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
                            .foregroundStyle(Color.hcLime)
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
            .background(Color.hcNight.ignoresSafeArea())
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

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let drives = weekDrives
        VStack(alignment: .leading, spacing: 22) {
            HStack {
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
                    if family.sortedMembers.contains(where: { $0.kind == .child }) {
                        Button {
                            isShowingCustody = true
                        } label: {
                            Label("Guarda", systemImage: "calendar")
                        }
                    }
                } label: {
                    Text("Família")
                        .font(Theme.Typography.display(34))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(Text("Opções da família"))
                .accessibilityIdentifier("family-header")

                Spacer()

                Button { editing = .new } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.hcAccent, in: Circle())
                }
                .accessibilityLabel(Text("Adicionar membro"))
            }

            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(family.sortedMembers, id: \.objectID) { member in
                    Button { editing = .existing(member) } label: {
                        MemberBubble(
                            member: member,
                            drives: member.kind == .adult ? drives[member.objectID, default: 0] : nil,
                            symbols: member.kind == .child ? symbols(for: member) : []
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            let adults = family.adults.filter { drives[$0.objectID, default: 0] > 0 }
            if adults.count >= 2 {
                DrivesBalance(adults: Array(adults.prefix(2)), drives: drives)
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

/// A member as a big circle of their colour with their initial.
/// Adults carry a count of this week's drives; children their activity icons; whoever is ill a coral ring
/// and their latest temperature.
private struct MemberBubble: View {
    @ObservedObject var member: Member
    let drives: Int?
    let symbols: [String]

    private let size: CGFloat = 132

    var body: some View {
        let episode = member.activeEpisode
        VStack(spacing: 10) {
            Text(member.initial)
                .font(Theme.Typography.display(52))
                .foregroundStyle(Color.hcNight)
                .frame(width: size, height: size)
                .background(Color(member.palette.soft), in: Circle())
                .padding(episode == nil ? 0 : 5)
                .overlay {
                    if episode != nil { Circle().strokeBorder(Color.hcWarning, lineWidth: 4) }
                }
                .overlay(alignment: .bottomLeading) {
                    if let drives, drives > 0 {
                        Text(verbatim: "\(drives)")
                            .font(Theme.Typography.text(15, weight: .heavy))
                            .foregroundStyle(Color.hcNight)
                            .frame(minWidth: 38, minHeight: 38)
                            .background(Color.white, in: Circle())
                            .overlay { Circle().strokeBorder(Color.hcNight, lineWidth: 3) }
                            .offset(x: -4, y: -2)
                            .accessibilityLabel(Text("\(drives) boleias esta semana"))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let episode {
                        fever(episode)
                    } else if !symbols.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(symbols.prefix(3), id: \.self) { symbol in
                                Image(systemName: symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.hcNight)
                                    .frame(width: 34, height: 34)
                                    .background(Color.white, in: Circle())
                                    .overlay { Circle().strokeBorder(Color.hcNight, lineWidth: 2) }
                            }
                        }
                        .offset(x: 6, y: 4)
                        .accessibilityHidden(true)
                    }
                }
            Text(nameLine)
                .font(Theme.Typography.text(17, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var nameLine: String {
        let name = member.name ?? ""
        if member.kind == .child, let age = member.age(on: .now) {
            return "\(name) · \(age)"
        }
        return name
    }

    private func fever(_ episode: IllnessEpisode) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 14, weight: .bold))
            if let reading = episode.latestReading {
                Text(verbatim: "\(Int(reading.celsius.rounded(.down)))°")
                    .font(Theme.Typography.text(15, weight: .heavy))
            }
        }
        .foregroundStyle(Color.hcNight)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.hcWarning, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.hcNight, lineWidth: 3) }
        .offset(x: 10, y: -4)
        .accessibilityLabel(Text("Doente"))
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
        HStack(spacing: 10) {
            MemberAvatar(member: first, size: 40)
            GeometryReader { proxy in
                let total = max(a + b, 1)
                let width = proxy.size.width - 4
                HStack(spacing: 4) {
                    Color(first.palette.soft).frame(width: width * CGFloat(a) / CGFloat(total))
                    Color(second.palette.soft)
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)
            MemberAvatar(member: second, size: 40)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Boleias esta semana: \(first.name ?? "") \(a), \(second.name ?? "") \(b)"))
    }
}

#Preview {
    FamilyView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
