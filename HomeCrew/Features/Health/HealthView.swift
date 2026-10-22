import CoreData
import SwiftUI

/// Everyone as a card: whoever is ill says so with their latest temperature, allergies show as a small
/// rose mark. Tap a person for their record.
struct HealthView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var isMakingReport = false
    @Environment(\.access) private var access

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            let members = families.flatMap(access.visibleMembers)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Saúde")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Color.hcInk)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("health-header")
                        Spacer()
                        if access.canManageFamily, !members.isEmpty {
                            Button { isMakingReport = true } label: {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.hcInk)
                                    .frame(width: 38, height: 38)
                                    .background(Color.hcCard, in: Circle())
                                    .overlay { Circle().strokeBorder(Color.hcSeparator, lineWidth: 1) }
                                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                            }
                            .accessibilityLabel(Text("PDF para o médico"))
                        }
                    }
                    .padding(.top, Theme.Spacing.l)

                    if members.isEmpty {
                        EmptyHint(systemImage: AppTab.health.systemImage, message: "Ainda sem membros")
                    } else {
                        SectionHeader(title: "Escolhe uma pessoa")
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(members, id: \.objectID) { member in
                                NavigationLink {
                                    PersonHealthView(member: member)
                                } label: {
                                    HealthBubble(member: member)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.hcBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isMakingReport) {
                DoctorReportSheet(members: families.flatMap(\.sortedMembers))
            }
        }
    }
}

private struct HealthBubble: View {
    @ObservedObject var member: Member

    var body: some View {
        let episode = member.activeEpisode
        HStack(spacing: 10) {
            MemberAvatar(member: member, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name ?? "")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                    .lineLimit(1)
                Group {
                    if let episode {
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.medium")
                            if let reading = episode.latestReading {
                                Text(verbatim: reading.celsius.formatted(.number.precision(.fractionLength(1))) + "°")
                            } else {
                                Text("Doente")
                            }
                        }
                        .foregroundStyle(Color.hcWarning)
                    } else if let age = member.age(on: .now) {
                        Text("\(age) anos")
                            .foregroundStyle(Color.hcSecondaryInk)
                    }
                }
                .font(Theme.Typography.caption)
            }
            Spacer(minLength: 0)
            if member.hasAllergies {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hcWarning)
                    .accessibilityLabel(Text("Alergias"))
            }
            Chevron()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(episode == nil ? Color.hcCard : Color.hcWarningSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(episode == nil ? Color.hcSeparator : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HealthView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
