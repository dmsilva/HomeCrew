import Charts
import SwiftUI

/// One illness episode: the temperature curve against the fever line, symptoms as icons, and notes.
struct EpisodeView: View {
    @ObservedObject var episode: IllnessEpisode

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingTemperature = false
    @State private var isConfirmingEnd = false
    @State private var notes = ""

    private let persistence = PersistenceController.shared

    var body: some View {
        List {
            Section {
                TemperatureChart(readings: episode.sortedReadings)
                    .frame(height: 180)
                    .padding(.vertical, Theme.Spacing.s)
                if episode.isActive {
                    Button {
                        isAddingTemperature = true
                    } label: {
                        Label("Registar temperatura", systemImage: "thermometer.medium")
                            .font(Theme.Typography.cardTitle)
                            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.hcAccent)
                }
            }
            .listRowBackground(Color.hcCard)

            if !episode.sortedReadings.isEmpty {
                Section {
                    ForEach(episode.sortedReadings.reversed(), id: \.objectID) { reading in
                        ReadingRow(reading: reading)
                            .deleteDisabled(!episode.isActive)
                    }
                    .onDelete(perform: deleteReadings)
                }
                .listRowBackground(Color.hcCard)
            }

            if episode.isActive || !episode.sortedMedications.isEmpty {
                MedicationSection(episode: episode)
            }

            Section {
                SymptomGrid(selected: episode.symptoms, isEditable: episode.isActive) { symptom, present in
                    persistence.setSymptom(symptom, present: present, in: episode)
                }
                .padding(.vertical, Theme.Spacing.s)
            }
            .listRowBackground(Color.hcCard)

            Section {
                TextField("Notas", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                    .disabled(!episode.isActive)
                    .onChange(of: notes) { _, newValue in
                        if newValue != (episode.notes ?? "") {
                            persistence.setNotes(newValue, in: episode)
                        }
                    }
            }
            .listRowBackground(Color.hcCard)

            if episode.isActive {
                Section {
                    Button(role: .destructive) {
                        isConfirmingEnd = true
                    } label: {
                        Label("Terminar episódio", systemImage: "checkmark.circle")
                    }
                }
                .listRowBackground(Color.hcCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.hcBackground.ignoresSafeArea())
        .navigationTitle(Text(episode.startedAt ?? .now, format: .dateTime.day().month()))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { notes = episode.notes ?? "" }
        .sheet(isPresented: $isAddingTemperature) {
            TemperatureEntry(initial: episode.latestReading?.celsius ?? 37.0) { celsius, takenAt in
                persistence.recordTemperature(celsius, in: episode, at: takenAt)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Terminar episódio?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("Terminar") {
                persistence.end(episode)
                dismiss()
            }
        }
    }

    private func deleteReadings(at offsets: IndexSet) {
        let shown = Array(episode.sortedReadings.reversed())
        for offset in offsets { persistence.delete(shown[offset]) }
    }
}

/// Temperatures over time, with the 38° line so a fever is visible at a glance.
struct TemperatureChart: View {
    let readings: [TemperatureReading]

    var body: some View {
        if readings.isEmpty {
            EmptyHint(systemImage: "thermometer.medium", message: "Sem temperaturas")
        } else {
            Chart {
                RuleMark(y: .value("Febre", IllnessEpisode.feverCelsius))
                    .foregroundStyle(Color.hcWarning.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(readings, id: \.objectID) { reading in
                    LineMark(
                        x: .value("Hora", reading.takenAt ?? .now),
                        y: .value("Temperatura", reading.celsius)
                    )
                    .foregroundStyle(Color.hcAccent)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Hora", reading.takenAt ?? .now),
                        y: .value("Temperatura", reading.celsius)
                    )
                    .foregroundStyle(reading.isFever ? Color.hcWarning : Color.hcAccent)
                }
            }
            .chartYScale(domain: yDomain)
            .accessibilityLabel(Text("Gráfico de temperaturas"))
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = readings.map(\.celsius)
        let low = min(values.min() ?? 36, 36)
        let high = max(values.max() ?? 39, 39)
        return low.rounded(.down)...high.rounded(.up)
    }
}

struct ReadingRow: View {
    @ObservedObject var reading: TemperatureReading

    var body: some View {
        HStack {
            Text(verbatim: reading.celsius.formatted(.number.precision(.fractionLength(1))) + "°")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(reading.isFever ? Color.hcWarning : Color.hcInk)
            Spacer()
            Text(reading.takenAt ?? .now, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(Theme.Typography.caption)
                .foregroundStyle(Color.hcSecondaryInk)
        }
    }
}

/// Symptoms as a grid of icons: tap to mark, tap again to clear.
struct SymptomGrid: View {
    let selected: Set<Symptom>
    var isEditable = true
    let onChange: (Symptom, Bool) -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: Theme.Spacing.m)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(Symptom.allCases) { symptom in
                let isOn = selected.contains(symptom)
                Button {
                    onChange(symptom, !isOn)
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: symptom.systemImage)
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(isOn ? Color.hcWarningSoft : Color.hcBackground, in: Circle())
                            .foregroundStyle(isOn ? Color.hcWarning : Color.hcSecondaryInk)
                        Text(symptom.title)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(isOn ? Color.hcInk : Color.hcSecondaryInk)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isEditable)
                .accessibilityIdentifier("symptom-\(symptom.rawValue)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Pick a temperature with a wheel (35–42 °C, steps of 0.1) and when it was taken.
struct TemperatureEntry: View {
    let initial: Double
    let onSave: (Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tenths = 370
    @State private var takenAt = Date.now

    static let range = 350...420

    var body: some View {
        NavigationStack {
            Form {
                Picker("Temperatura", selection: $tenths) {
                    ForEach(Self.range, id: \.self) { value in
                        Text(verbatim: (Double(value) / 10).formatted(.number.precision(.fractionLength(1))) + "°")
                    }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("temperature")
                DatePicker("Hora", selection: $takenAt, in: ...Date.now)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(Double(tenths) / 10, takenAt)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            tenths = min(max(Int((initial * 10).rounded()), Self.range.lowerBound), Self.range.upperBound)
        }
    }
}
