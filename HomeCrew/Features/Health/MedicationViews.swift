import SwiftUI

/// The medication section of an episode: each medicine with a countdown to its next dose and "Dei agora".
struct MedicationSection: View {
    @ObservedObject var episode: IllnessEpisode
    @AppStorage("meMemberID") private var meMemberID = ""
    @State private var editorTarget: MedicationEditorTarget?

    private let persistence = PersistenceController.shared

    var body: some View {
        Section {
            ForEach(episode.isActive ? episode.activeMedications : episode.sortedMedications, id: \.objectID) { medication in
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    MedicationRow(medication: medication) {
                        persistence.giveDose(of: medication, by: me)
                    }
                }
            }
            if episode.isActive {
                Button {
                    editorTarget = .new
                } label: {
                    Label("Adicionar medicamento", systemImage: "plus")
                }
            }
        } header: {
            Label("Medicação", systemImage: "pills")
        }
        .listRowBackground(Color.hcCard)
        .sheet(item: $editorTarget) { target in
            MedicationEditor(episode: episode, target: target, me: me)
        }
    }

    private var me: Member? {
        episode.member?.family?.sortedMembers.first { $0.identifier?.uuidString == meMemberID }
    }
}

struct MedicationRow: View {
    @ObservedObject var medication: Medication
    let onGive: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let isDue = medication.isDue(at: context.date)
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "pills.fill")
                    .font(.title3)
                    .foregroundStyle(isDue ? Color.hcWarning : Color.hcAccent)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(medication.name ?? "")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Color.hcInk)
                    HStack(spacing: Theme.Spacing.s) {
                        if let dose = medication.dose, !dose.isEmpty {
                            Text(dose)
                        }
                        if let responsible = medication.responsible {
                            MemberAvatar(member: responsible, size: 20)
                        }
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.hcSecondaryInk)
                }
                Spacer()
                if medication.isActive {
                    if let next = medication.nextDoseAt, !isDue {
                        Label {
                            Text(next, style: .timer).monospacedDigit()
                        } icon: {
                            Image(systemName: "hourglass")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.hcSecondaryInk)
                        .accessibilityLabel(Text("Próxima dose \(next, style: .relative)"))
                    }
                    Button("Dei agora", action: onGive)
                        .buttonStyle(.borderedProminent)
                        .tint(isDue ? Color.hcWarning : Color.hcAccent)
                        .font(Theme.Typography.caption)
                }
            }
        }
    }
}

enum MedicationEditorTarget: Identifiable {
    case new
    case existing(Medication)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let medication): medication.objectID.uriRepresentation().absoluteString
        }
    }
}

/// Name with suggestions, the dose as the doctor gave it, the interval, and who gives it.
struct MedicationEditor: View {
    let episode: IllnessEpisode
    let target: MedicationEditorTarget
    let me: Member?

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MedicationDraft()

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        TextField("Medicamento", text: $draft.name)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("medication-name")
                    } icon: {
                        Image(systemName: "pills")
                    }
                    let suggestions = Medication.suggestions(for: draft.name)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.s) {
                                ForEach(suggestions, id: \.self) { name in
                                    Button(name) { draft.name = name }
                                        .buttonStyle(.bordered)
                                        .tint(Color.hcAccent)
                                }
                            }
                        }
                    }
                }
                Section {
                    Label {
                        TextField("Dose (ex.: 5 ml)", text: $draft.dose)
                    } icon: {
                        Image(systemName: "eyedropper")
                    }
                    Stepper(value: $draft.intervalHours, in: 1...48, step: 1) {
                        Label {
                            Text("De \(Int(draft.intervalHours)) em \(Int(draft.intervalHours)) h")
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                } footer: {
                    Text("A dose e o intervalo são os indicados pelo médico.")
                }
                Section {
                    DriverPicker(
                        title: "Responsável",
                        systemImage: "bell",
                        adults: episode.member?.family?.adults ?? [],
                        selection: $draft.responsible
                    )
                }
                if case .new = target {
                    Section {
                        Toggle(isOn: $draft.givenNow) {
                            Label("Dei agora a primeira", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(Text(episode.member?.name ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        switch target {
                        case .new: persistence.addMedication(draft, to: episode, by: me)
                        case .existing(let medication): persistence.update(medication, with: draft)
                        }
                        DoseReminderCenter.shared.requestAuthorization()
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .onAppear {
            switch target {
            case .new:
                draft = MedicationDraft()
                draft.responsible = me
            case .existing(let medication):
                draft = MedicationDraft(medication)
            }
        }
    }
}

/// Every dose given, who gave it, and the controls to edit or stop the medicine.
struct MedicationDetailView: View {
    @ObservedObject var medication: Medication
    @AppStorage("meMemberID") private var meMemberID = ""
    @Environment(\.dismiss) private var dismiss
    @State private var editorTarget: MedicationEditorTarget?

    private let persistence = PersistenceController.shared

    var body: some View {
        List {
            Section {
                MedicationRow(medication: medication) {
                    persistence.giveDose(of: medication, by: me)
                }
            }
            .listRowBackground(Color.hcCard)

            if !medication.sortedDoses.isEmpty {
                Section {
                    ForEach(medication.sortedDoses, id: \.objectID) { dose in
                        DoseRow(dose: dose)
                            .deleteDisabled(!medication.isActive)
                    }
                    .onDelete { offsets in
                        let doses = medication.sortedDoses
                        for offset in offsets { persistence.delete(doses[offset]) }
                    }
                } header: {
                    Label("Doses dadas", systemImage: "checklist")
                }
                .listRowBackground(Color.hcCard)
            }

            if medication.isActive {
                Section {
                    Button(role: .destructive) {
                        persistence.stop(medication)
                        dismiss()
                    } label: {
                        Label("Parar medicamento", systemImage: "stop.circle")
                    }
                }
                .listRowBackground(Color.hcCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.hcBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if medication.isActive {
                Button("Editar") { editorTarget = .existing(medication) }
            }
        }
        .sheet(item: $editorTarget) { target in
            if let episode = medication.episode {
                MedicationEditor(episode: episode, target: target, me: me)
            }
        }
    }

    private var me: Member? {
        medication.episode?.member?.family?.sortedMembers.first { $0.identifier?.uuidString == meMemberID }
    }
}

struct DoseRow: View {
    @ObservedObject var dose: DoseGiven

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hcAccent)
            Text(dose.givenAt ?? .now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(Theme.Typography.body)
                .foregroundStyle(Color.hcInk)
            Spacer()
            if let member = dose.givenBy {
                MemberAvatar(member: member, size: 28)
            }
        }
    }
}
