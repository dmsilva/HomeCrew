import CoreData
import SwiftUI

/// One card per person; allergies show on the card so nobody has to open it to see them.
struct HealthView: View {
    @FetchRequest(fetchRequest: Family.all()) private var families: FetchedResults<Family>
    @State private var isMakingReport = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)]

    var body: some View {
        NavigationStack {
            Group {
                let members = families.flatMap(\.sortedMembers)
                if members.isEmpty {
                    EmptyHint(systemImage: AppTab.health.systemImage, message: "Ainda sem membros")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                            ForEach(members, id: \.objectID) { member in
                                NavigationLink {
                                    PersonHealthView(member: member)
                                } label: {
                                    HealthCard(member: member)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.l)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hcBackground.ignoresSafeArea())
            .navigationTitle(AppTab.health.title)
            .toolbar {
                if !families.flatMap(\.sortedMembers).isEmpty {
                    Button {
                        isMakingReport = true
                    } label: {
                        Label("PDF para o médico", systemImage: "doc.richtext")
                    }
                }
            }
            .sheet(isPresented: $isMakingReport) {
                DoctorReportSheet(members: families.flatMap(\.sortedMembers))
            }
        }
    }
}

private struct HealthCard: View {
    @ObservedObject var member: Member

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            MemberAvatar(member: member)
            Text(member.name ?? "")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Color.hcInk)
                .lineLimit(1)
            if member.hasAllergies {
                Label("\(member.allergyList.count)", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.hcWarning)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Color.hcWarningSoft, in: Capsule())
                    .accessibilityLabel(Text("Alergias"))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

#Preview {
    HealthView()
        .environment(\.managedObjectContext, PersistenceController(inMemory: true).viewContext)
}
