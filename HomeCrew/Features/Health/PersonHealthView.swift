import SwiftUI

/// A person's health page (Direção E): their big colour circle, allergies as coral chips, then one big
/// block for illness (coral with the temperature when ill, a dark "open episode" button otherwise),
/// the record as tiles, a lime call button for the pediatrician, and past episodes as small cards.
struct PersonHealthView: View {
    @ObservedObject var member: Member
    @State private var isEditing = false
    @State private var isMakingReport = false
    @Environment(\.access) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var affectedActivities: AffectedActivities?
    @AppStorage("meMemberID") private var meMemberID = ""

    private let persistence = PersistenceController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                identity
                if member.hasAllergies { allergies }
                illness
                if access.canSeeFullHealthRecord { record }
                pediatrician
                history
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.hcBackground.ignoresSafeArea())
        .foregroundStyle(Color.hcInk)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            HealthRecordEditor(member: member)
        }
        .sheet(isPresented: $isMakingReport) {
            DoctorReportSheet(members: member.family?.sortedMembers ?? [member], selected: member)
        }
        .sheet(item: $affectedActivities) { affected in
            IllnessAgendaSheet(
                occurrences: affected.occurrences,
                assignee: member.family?.sortedMembers.first { $0.identifier?.uuidString == meMemberID }
            )
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            circleButton("chevron.left", label: "Voltar") { dismiss() }
            Spacer()
            if access.canManageFamily {
                circleButton("doc.text.fill", label: "PDF para o médico") { isMakingReport = true }
            }
            if access.canSeeFullHealthRecord {
                circleButton("pencil", label: "Editar") { isEditing = true }
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private func circleButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(Color.hcInk, lineWidth: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var identity: some View {
        HStack(spacing: Theme.Spacing.l) {
            Text(member.initial)
                .font(Theme.Typography.display(40))
                .foregroundStyle(Color.hcNight)
                .frame(width: 88, height: 88)
                .background(Color(member.palette.soft), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name ?? "")
                    .font(Theme.Typography.display(30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if member.kind == .child, let age = member.age(on: .now) {
                    Text(verbatim: "\(age)")
                        .font(Theme.Typography.text(17, weight: .heavy))
                        .foregroundStyle(Color.hcSecondaryInk)
                        .accessibilityLabel(Text("\(age) anos"))
                }
            }
        }
    }

    private var allergies: some View {
        FlowChips(items: member.allergyList) { allergy in
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text(allergy)
                    .font(Theme.Typography.text(16, weight: .heavy))
            }
            .foregroundStyle(Color.hcNight)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.hcWarning, in: Capsule())
        }
    }

    @ViewBuilder
    private var illness: some View {
        if let episode = member.activeEpisode {
            NavigationLink {
                EpisodeView(episode: episode)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    if let reading = episode.latestReading {
                        Text(verbatim: reading.celsius.formatted(.number.precision(.fractionLength(1))) + "°")
                            .font(Theme.Typography.display(56))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 40, weight: .bold))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .bold))
                }
                .foregroundStyle(Color.hcNight)
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.hcWarning, in: RoundedRectangle(cornerRadius: 30))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("active-episode")
        } else if access.canManageEpisode {
            Button {
                persistence.openEpisode(for: member)
                let affected = IllnessAgenda.affected(for: member, from: .now)
                if !affected.isEmpty {
                    affectedActivities = AffectedActivities(occurrences: affected)
                }
            } label: {
                Label("Abrir episódio", systemImage: "thermometer.medium")
                    .font(Theme.Typography.text(17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.hcNight, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Weight, chronic conditions and usual medicines as tiles: an icon and the shortest text.
    @ViewBuilder
    private var record: some View {
        let candidates: [(symbol: String, text: String)?] = [
            member.weightKg > 0 ? ("scalemass.fill", member.weightKg.formatted(.number.precision(.fractionLength(0...1))) + " kg") : nil,
            (member.chronicConditions ?? "").isEmpty ? nil : ("heart.text.square.fill", member.chronicConditions ?? ""),
            (member.usualMedication ?? "").isEmpty ? nil : ("pills.fill", member.usualMedication ?? ""),
        ]
        let tiles = candidates.compactMap { $0 }
        if !tiles.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(tiles, id: \.symbol) { tile in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: tile.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.hcAccent)
                            .accessibilityHidden(true)
                        Text(tile.text)
                            .font(Theme.Typography.text(17, weight: .heavy))
                            .lineLimit(2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                    .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
            }
        }
    }

    @ViewBuilder
    private var pediatrician: some View {
        let name = member.pediatricianName ?? ""
        if member.pediatricianCallURL != nil || !name.isEmpty {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.hcNight)
                    .frame(width: 52, height: 52)
                    .background(Color.hcMuted, in: Circle())
                    .accessibilityHidden(true)
                Text(name)
                    .font(Theme.Typography.text(17, weight: .heavy))
                    .lineLimit(1)
                Spacer()
                if let url = member.pediatricianCallURL {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.hcNight)
                            .frame(width: 56, height: 56)
                            .background(Color.hcLime, in: Circle())
                    }
                    .accessibilityLabel(Text("Ligar ao pediatra"))
                }
            }
            .padding(12)
            .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    /// Past episodes as small cards: the date and the highest temperature.
    @ViewBuilder
    private var history: some View {
        let past = access.canSeeFullHealthRecord ? member.episodeHistory.filter { !$0.isActive } : []
        if !past.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(past, id: \.objectID) { episode in
                        NavigationLink {
                            EpisodeView(episode: episode)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(episode.startedAt ?? .now, format: .dateTime.day().month(.abbreviated))
                                    .font(Theme.Typography.text(13, weight: .heavy))
                                    .foregroundStyle(Color.hcSecondaryInk)
                                if let highest = episode.highestCelsius {
                                    Text(verbatim: highest.formatted(.number.precision(.fractionLength(1))) + "°")
                                        .font(Theme.Typography.display(24))
                                        .foregroundStyle(highest >= IllnessEpisode.feverCelsius ? Color.hcWarning : Color.hcInk)
                                }
                            }
                            .padding(14)
                            .frame(width: 104, height: 88, alignment: .topLeading)
                            .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct AffectedActivities: Identifiable {
        let id = UUID()
        let occurrences: [ActivityOccurrence]
    }
}

struct HealthRecordEditor: View {
    let member: Member

    @Environment(\.dismiss) private var dismiss
    @State private var draft = HealthRecordDraft()

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("exclamationmark.triangle", "Alergias", text: $draft.allergies, identifier: "allergies")
                } footer: {
                    Text("Separa com vírgulas.")
                }
                Section {
                    Label {
                        TextField("Peso (kg)", value: $draft.weightKg, format: .number)
                            .keyboardType(.decimalPad)
                    } icon: {
                        Image(systemName: "scalemass")
                    }
                    field("heart.text.square", "Doenças crónicas", text: $draft.chronicConditions)
                    field("pills", "Medicação habitual", text: $draft.usualMedication)
                }
                Section {
                    field("stethoscope", "Pediatra", text: $draft.pediatricianName)
                    Label {
                        TextField("Telefone", text: $draft.pediatricianPhone)
                            .keyboardType(.phonePad)
                    } icon: {
                        Image(systemName: "phone")
                    }
                }
            }
            .navigationTitle(Text(member.name ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        persistence.updateHealthRecord(of: member, with: draft)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = HealthRecordDraft(member) }
    }

    private func field(
        _ systemImage: String, _ title: LocalizedStringKey, text: Binding<String>, identifier: String = ""
    ) -> some View {
        Label {
            // On the field itself: on the Label it would also tag the icon, which UI tests then find first.
            TextField(title, text: text, axis: .vertical)
                .accessibilityIdentifier(identifier)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

/// One line per episode: when it started, how long, highest temperature, symptom icons.
struct EpisodeSummary: View {
    @ObservedObject var episode: IllnessEpisode

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "thermometer.medium")
                .font(.title3)
                .foregroundStyle(episode.isActive ? Color.hcWarning : Color.hcSecondaryInk)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(episode.startedAt ?? .now, format: .dateTime.day().month())
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Color.hcInk)
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(Symptom.allCases.filter(episode.symptoms.contains)) { symptom in
                        Image(systemName: symptom.systemImage)
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Color.hcSecondaryInk)
            }
            Spacer()
            if let highest = episode.highestCelsius {
                Text(verbatim: highest.formatted(.number.precision(.fractionLength(1))) + "°")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(highest >= IllnessEpisode.feverCelsius ? Color.hcWarning : Color.hcInk)
            }
        }
    }
}

/// Chips that wrap onto as many lines as they need.
struct FlowChips<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

/// Lays children left to right and starts a new line when one does not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
