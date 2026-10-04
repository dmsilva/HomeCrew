import SwiftUI

/// The two houses, the pattern and the day it starts; a custom pattern is tapped in over two weeks.
struct CustodyPlanEditor: View {
    let child: Member
    let family: Family

    @Environment(\.dismiss) private var dismiss
    @State private var draft = CustodyDraft()

    private let persistence = PersistenceController.shared

    /// Only a custom pattern can be tapped.
    private var toggleDay: ((Int) -> Void)? {
        guard draft.pattern == .custom else { return nil }
        return { index in draft.customDays[index].toggle() }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DriverPicker(title: "Casa 1", systemImage: "house.fill", adults: family.adults, selection: $draft.parentA)
                    DriverPicker(title: "Casa 2", systemImage: "house", adults: family.adults, selection: $draft.parentB)
                }
                Section {
                    Picker("Padrão", selection: $draft.pattern) {
                        Text("Semanas alternadas").tag(CustodyPattern.alternateWeeks)
                        Text(verbatim: "2-2-3").tag(CustodyPattern.twoTwoThree)
                        Text("Personalizado").tag(CustodyPattern.custom)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Começa em", selection: $draft.startDate, displayedComponents: .date)
                }
                Section {
                    CyclePreview(
                        cycle: draft.pattern.cycle(custom: draft.customDays),
                        start: draft.startDate,
                        parentA: draft.parentA,
                        parentB: draft.parentB,
                        onToggle: toggleDay
                    )
                } footer: {
                    if draft.pattern == .custom {
                        Text("Toca num dia para mudar de casa.")
                    }
                }
                if child.custodyPlan != nil {
                    Section {
                        Button("Remover guarda", role: .destructive) {
                            persistence.removeCustody(of: child)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(Text(child.name ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        persistence.setCustody(draft, for: child)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .onAppear {
            if let plan = child.custodyPlan {
                draft = CustodyDraft(plan)
            } else {
                draft = CustodyDraft()
                let adults = family.adults
                draft.parentA = adults.first
                draft.parentB = adults.dropFirst().first
            }
        }
    }
}

/// The 14-day cycle as two rows of seven, each day in its house's colour.
private struct CyclePreview: View {
    let cycle: [Bool]
    let start: Date
    let parentA: Member?
    let parentB: Member?
    let onToggle: ((Int) -> Void)?

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { week in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = week * 7 + column
                        let isA = cycle[index]
                        let parent = isA ? parentA : parentB
                        let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
                        Button {
                            onToggle?(index)
                        } label: {
                            VStack(spacing: 2) {
                                Text(day, format: .dateTime.weekday(.narrow))
                                    .font(Theme.Typography.caption)
                                Text(parent?.initial ?? (isA ? "1" : "2"))
                                    .font(Theme.Typography.body.weight(.semibold))
                            }
                            .foregroundStyle(parent.map { Color($0.palette.foreground) } ?? Color.hcInk)
                            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                            .background(parent.map { Color($0.palette.soft) } ?? Color.hcBackground,
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(onToggle == nil)
                        .accessibilityIdentifier("cycle-\(index)")
                    }
                }
            }
        }
    }
}
