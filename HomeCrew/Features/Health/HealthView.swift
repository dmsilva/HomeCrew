import CoreData
import SwiftUI

/// Everyone as a colour circle (Direção E): whoever is ill gets a coral ring and their latest temperature,
/// allergies a small coral badge. Tap a person for their record; the ill go straight to care mode.
struct HealthView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var isMakingReport = false
    @Environment(\.access) private var access

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            let members = families.flatMap(access.visibleMembers)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Saúde")
                            .font(Theme.Typography.display(34))
                            .foregroundStyle(Color.hcInk)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("health-header")
                        Spacer()
                        if access.canManageFamily, !members.isEmpty {
                            Button { isMakingReport = true } label: {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Color.hcInk)
                                    .frame(width: 48, height: 48)
                                    .overlay { Circle().strokeBorder(Color.hcInk, lineWidth: 2) }
                            }
                            .accessibilityLabel(Text("PDF para o médico"))
                        }
                    }
                    .padding(.top, Theme.Spacing.l)

                    if members.isEmpty {
                        EmptyHint(systemImage: AppTab.health.systemImage, message: "Ainda sem membros")
                    } else {
                        LazyVGrid(columns: columns, spacing: 24) {
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

    private let size: CGFloat = 116

    var body: some View {
        let episode = member.activeEpisode
        VStack(spacing: 10) {
            Text(member.initial)
                .font(Theme.Typography.display(46))
                .foregroundStyle(Color.hcNight)
                .frame(width: size, height: size)
                .background(Color(member.palette.soft), in: Circle())
                .padding(episode == nil ? 0 : 5)
                .overlay {
                    if episode != nil { Circle().strokeBorder(Color.hcWarning, lineWidth: 4) }
                }
                .overlay(alignment: .topTrailing) {
                    if let episode {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 13, weight: .bold))
                            if let reading = episode.latestReading {
                                Text(verbatim: reading.celsius.formatted(.number.precision(.fractionLength(1))) + "°")
                                    .font(Theme.Typography.text(14, weight: .heavy))
                            }
                        }
                        .foregroundStyle(Color.hcNight)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(Color.hcWarning, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.hcBackground, lineWidth: 3) }
                        .offset(x: 12, y: -4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if member.hasAllergies {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.hcWarning)
                            .frame(width: 36, height: 36)
                            .background(Color.white, in: Circle())
                            .overlay { Circle().strokeBorder(Color.hcBackground, lineWidth: 3) }
                            .offset(x: -2, y: 0)
                            .accessibilityLabel(Text("Alergias"))
                    }
                }
            Text(member.name ?? "")
                .font(Theme.Typography.text(17, weight: .heavy))
                .foregroundStyle(Color.hcInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HealthView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
