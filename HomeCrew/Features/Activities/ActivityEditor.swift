import SwiftUI

enum ActivityEditorTarget: Identifiable {
    case new
    case existing(Activity)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let activity): activity.objectID.uriRepresentation().absoluteString
        }
    }
}

struct ActivityEditor: View {
    let target: ActivityEditorTarget
    let family: Family
    let persistence: PersistenceController

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ActivityDraft()
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Atividade", text: $draft.title)
                        .font(Theme.Typography.cardTitle)
                    symbolPicker
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(children, id: \.objectID) { child in
                                childButton(child)
                            }
                        }
                    }
                }

                Section {
                    WeekdayPicker(selection: $draft.weekdays)
                    DatePicker("Hora", selection: startTime, displayedComponents: .hourAndMinute)
                    Stepper(value: $draft.durationMinutes, in: 15...480, step: 15) {
                        Label("\(draft.durationMinutes) min", systemImage: "timer")
                    }
                }

                Section {
                    Label {
                        TextField("Local", text: $draft.location)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    Label {
                        TextField("Material a levar", text: $draft.equipment)
                    } icon: {
                        Image(systemName: "bag")
                    }
                    Label {
                        TextField("Notas", text: $draft.notes, axis: .vertical)
                    } icon: {
                        Image(systemName: "note.text")
                    }
                }

                if case .existing = target {
                    Section {
                        Button("Apagar", role: .destructive) { isConfirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isNew ? Text("Nova atividade") : Text("Editar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save).disabled(!draft.isValid)
                }
            }
            .confirmationDialog("Apagar atividade?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Apagar", role: .destructive) {
                    if case .existing(let activity) = target { persistence.delete(activity) }
                    dismiss()
                }
            }
        }
        .onAppear(perform: loadDraft)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    /// Activities are for children; adults only appear when the family has no children yet.
    private var children: [Member] {
        let kids = family.sortedMembers.filter { $0.kind == .child }
        return kids.isEmpty ? family.sortedMembers : kids
    }

    /// The draft keeps minutes after midnight; the picker works on a Date for today.
    private var startTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: draft.startMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.startMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var symbolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Activity.symbols, id: \.self) { symbol in
                    let isSelected = draft.symbolName == symbol
                    Button {
                        draft.symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.white : Color.hcAccent)
                            .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                            .background(
                                isSelected ? Color.hcAccent : Color.hcAccentSoft,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func childButton(_ member: Member) -> some View {
        let isSelected = draft.child == member
        return Button {
            draft.child = isSelected ? nil : member
        } label: {
            MemberAvatar(member: member, size: 44)
                .overlay {
                    Circle().strokeBorder(Color.hcAccent, lineWidth: isSelected ? 3 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(member.name ?? ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func loadDraft() {
        switch target {
        case .new:
            draft = ActivityDraft()
            draft.child = children.first
        case .existing(let activity):
            draft = ActivityDraft(activity)
        }
    }

    private func save() {
        switch target {
        case .new: persistence.addActivity(draft, to: family)
        case .existing(let activity): persistence.update(activity, with: draft)
        }
        dismiss()
    }
}
