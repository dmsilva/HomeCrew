import SwiftUI

/// A person's health page: allergies first and in the warning colour, then the record,
/// with a button to call the pediatrician.
struct PersonHealthView: View {
    @ObservedObject var member: Member
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.l) {
                    MemberAvatar(member: member, size: 64)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(member.name ?? "")
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Color.hcInk)
                        if let age = member.age(on: .now), member.kind == .child {
                            Text("\(age) anos")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Color.hcSecondaryInk)
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)

            if member.hasAllergies {
                Section {
                    ForEach(member.allergyList, id: \.self) { allergy in
                        Label(allergy, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Color.hcWarning)
                    }
                }
                .listRowBackground(Color.hcWarningSoft)
            }

            Section {
                if member.weightKg > 0 {
                    row("scalemass", Text(member.weightKg, format: .number.precision(.fractionLength(0...1))) + Text(verbatim: " kg"))
                }
                if let conditions = member.chronicConditions, !conditions.isEmpty {
                    row("heart.text.square", Text(conditions))
                }
                if let medication = member.usualMedication, !medication.isEmpty {
                    row("pills", Text(medication))
                }
            }
            .listRowBackground(Color.hcCard)

            if member.pediatricianCallURL != nil || !(member.pediatricianName ?? "").isEmpty {
                Section {
                    HStack {
                        row("stethoscope", Text(member.pediatricianName ?? ""))
                        Spacer()
                        if let url = member.pediatricianCallURL {
                            Link(destination: url) {
                                Image(systemName: "phone.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                                    .background(Color.hcAccent, in: Circle())
                            }
                            .accessibilityLabel(Text("Ligar ao pediatra"))
                        }
                    }
                }
                .listRowBackground(Color.hcCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.hcBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Editar") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            HealthRecordEditor(member: member)
        }
    }

    private func row(_ systemImage: String, _ text: Text) -> some View {
        Label { text.foregroundStyle(Color.hcInk) } icon: {
            Image(systemName: systemImage).foregroundStyle(Color.hcAccent)
        }
        .font(Theme.Typography.body)
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
                    field("exclamationmark.triangle", "Alergias", text: $draft.allergies)
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

    private func field(_ systemImage: String, _ title: LocalizedStringKey, text: Binding<String>) -> some View {
        Label {
            TextField(title, text: text, axis: .vertical)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
