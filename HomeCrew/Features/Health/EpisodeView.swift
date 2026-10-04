import Charts
import SwiftUI

/// One illness episode in care mode (Direção E): the whole screen turns coral, with the latest temperature
/// as one giant number, its curve, the next dose counting down, symptoms as icons, the coming activities,
/// and two buttons: measure, or cured.
struct EpisodeView: View {
    @ObservedObject var episode: IllnessEpisode

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingTemperature = false
    @State private var isConfirmingEnd = false
    @State private var isPickingSymptoms = false
    @State private var isShowingHistory = false
    @Environment(\.access) private var access
    @State private var medicationEditor: MedicationEditorTarget?
    @AppStorage("meMemberID") private var meMemberID = ""

    private let persistence = PersistenceController.shared

    var body: some View {
        let isCare = episode.isActive
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                bigTemperature
                Button { isShowingHistory = true } label: {
                    TemperatureCurve(readings: episode.sortedReadings)
                        .frame(height: 64)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Temperaturas"))
                .accessibilityIdentifier("temperature-history")

                medications
                symptoms
                CareAgenda(member: episode.member)

                if isCare && access.canEdit {
                    actions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background((isCare ? Color.hcWarning : Color.hcBackground).ignoresSafeArea())
        .foregroundStyle(Color.hcNight)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAddingTemperature) {
            TemperatureEntry(initial: episode.latestReading?.celsius ?? 37.0) { celsius, takenAt in
                persistence.recordTemperature(celsius, in: episode, at: takenAt, by: me)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $medicationEditor) { target in
            MedicationEditor(episode: episode, target: target, me: me)
        }
        .sheet(isPresented: $isPickingSymptoms) {
            NavigationStack {
                SymptomGrid(selected: episode.symptoms, isEditable: episode.isActive && access.canManageEpisode) { symptom, present in
                    persistence.setSymptom(symptom, present: present, in: episode)
                }
                .padding(Theme.Spacing.l)
                .frame(maxHeight: .infinity, alignment: .top)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { isPickingSymptoms = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingHistory) {
            EpisodeHistory(episode: episode)
        }
        .confirmationDialog("Curada?", isPresented: $isConfirmingEnd, titleVisibility: .visible) {
            Button("Terminar episódio") {
                persistence.end(episode)
                dismiss()
            }
        }
    }

    private var me: Member? { episode.member?.family?.member(withID: meMemberID) }

    /// Back, which day of the illness this is, and whose.
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .overlay { Circle().strokeBorder(Color.hcNight, lineWidth: 2) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Voltar"))
            Spacer()
            Text("dia \(dayNumber)")
                .font(Theme.Typography.display(22))
            if let member = episode.member {
                MemberAvatar(member: member, size: 40)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var dayNumber: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: episode.startedAt ?? .now)
        let end = calendar.startOfDay(for: episode.endedAt ?? .now)
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    @ViewBuilder
    private var bigTemperature: some View {
        if let reading = episode.latestReading {
            Text(verbatim: reading.celsius.formatted(.number.precision(.fractionLength(1))) + "°")
                .font(Theme.Typography.display(110))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("latest-temperature")
        } else {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 80, weight: .bold))
                .accessibilityLabel(Text("Sem temperaturas"))
        }
    }

    /// A dark card per medicine counting down to the next dose, with a lime button to give it now.
    private var medications: some View {
        VStack(spacing: Theme.Spacing.m) {
            let shown = episode.isActive ? episode.activeMedications : episode.sortedMedications
            ForEach(shown, id: \.objectID) { medication in
                CareMedicationRow(medication: medication, canGive: access.canEdit) {
                    persistence.giveDose(of: medication, by: me)
                }
            }
            if episode.isActive && access.canManageEpisode {
                Button { medicationEditor = .new } label: {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 20, weight: .bold))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .offset(x: 8, y: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .strokeBorder(Color.hcNight, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Adicionar medicamento"))
            }
        }
    }

    /// The symptoms marked so far as dark squares, and a dashed "+" to change them.
    private var symptoms: some View {
        let marked = Symptom.allCases.filter(episode.symptoms.contains)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(marked) { symptom in
                Image(systemName: symptom.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.hcNight, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .accessibilityLabel(Text(symptom.title))
            }
            if episode.isActive && access.canManageEpisode {
                Button { isPickingSymptoms = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .strokeBorder(Color.hcNight, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Sintomas"))
                .accessibilityIdentifier("symptoms-edit")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button { isAddingTemperature = true } label: {
                Label("Medir", systemImage: "thermometer.medium")
                    .font(Theme.Typography.text(17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.hcNight, in: Capsule())
            }
            .buttonStyle(.plain)
            if access.canManageEpisode {
                Button { isConfirmingEnd = true } label: {
                    Label("Curada", systemImage: "checkmark")
                        .font(Theme.Typography.text(17, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay { Capsule().strokeBorder(Color.hcNight, lineWidth: 2) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }
}

/// The temperatures as a bare line over the 38° fever line, ending in a dot: the shape of the illness, no axes.
struct TemperatureCurve: View {
    let readings: [TemperatureReading]

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                Path { path in
                    let y = yPosition(IllnessEpisode.feverCelsius, height: proxy.size.height)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
                .stroke(Color.hcNight.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for index in 1..<points.count {
                            let previous = points[index - 1]
                            let point = points[index]
                            let mid = (previous.x + point.x) / 2
                            path.addCurve(to: point, control1: CGPoint(x: mid, y: previous.y), control2: CGPoint(x: mid, y: point.y))
                        }
                    }
                    .stroke(Color.hcNight, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    Circle()
                        .fill(Color.white)
                        .overlay { Circle().strokeBorder(Color.hcNight, lineWidth: 3) }
                        .frame(width: 14, height: 14)
                        .position(last)
                }
            }
        }
    }

    private var range: ClosedRange<Double> {
        let values = readings.map(\.celsius)
        return min(values.min() ?? 37, 37)...max(values.max() ?? 39.5, 39.5)
    }

    private func yPosition(_ celsius: Double, height: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? (celsius - range.lowerBound) / span : 0.5
        return height - CGFloat(fraction) * (height - 8) - 4
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard let first = readings.first?.takenAt, let last = readings.last?.takenAt else { return [] }
        let span = max(last.timeIntervalSince(first), 1)
        return readings.map { reading in
            let x = CGFloat((reading.takenAt ?? first).timeIntervalSince(first) / span) * (size.width - 8) + 4
            return CGPoint(x: readings.count == 1 ? size.width - 8 : x, y: yPosition(reading.celsius, height: size.height))
        }
    }
}

/// A medicine in care mode: a ring that fills up to the next dose with the time left in big type,
/// and a lime square to say it was just given.
struct CareMedicationRow: View {
    @ObservedObject var medication: Medication
    let canGive: Bool
    let onGive: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let isDue = medication.isDue(at: now)
            HStack(spacing: Theme.Spacing.m) {
                NavigationLink {
                    MedicationDetailView(medication: medication)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: progress(at: now))
                                .stroke(Color.hcLime, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "pills.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.hcLime)
                        }
                        .frame(width: 60, height: 60)
                        if let next = medication.nextDoseAt, !isDue {
                            Text(verbatim: Self.countdown(to: next, from: now))
                                .font(Theme.Typography.display(30))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .accessibilityLabel(Text("Próxima dose \(next, style: .relative)"))
                                .accessibilityIdentifier("next-dose")
                        } else {
                            Text(medication.name ?? "")
                                .font(Theme.Typography.text(20, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .background(Color.hcNight, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(medication.name ?? ""))

                if canGive && medication.isActive {
                    Button(action: onGive) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Color.hcNight)
                            .frame(width: 88, height: 88)
                            .background(isDue ? Color.hcLime : Color.hcLime.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Dei agora"))
                }
            }
        }
    }

    /// How much of the wait since the last dose has passed; full when it is time.
    private func progress(at now: Date) -> CGFloat {
        guard let last = medication.lastDose?.givenAt, medication.interval > 0 else { return 1 }
        return CGFloat(min(max(now.timeIntervalSince(last) / medication.interval, 0), 1))
    }

    /// "1h50" or "25m".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(Int(date.timeIntervalSince(now) / 60), 0)
        let hours = minutes / 60
        return hours > 0 ? String(format: "%dh%02d", hours, minutes % 60) : "\(minutes)m"
    }
}

/// The ill person's activities in the next three days as icons: tap one to call it off for that day
/// (or bring it back); a tick marks the ones already off.
struct CareAgenda: View {
    let member: Member?
    @Environment(\.access) private var access
    private let persistence = PersistenceController.shared

    var body: some View {
        let occurrences = upcoming
        if !occurrences.isEmpty {
            HStack(spacing: 10) {
                ForEach(occurrences.prefix(5)) { occurrence in
                    Button {
                        persistence.setCancelled(!occurrence.isCancelled, occurrence.activity, on: occurrence.start)
                    } label: {
                        Image(systemName: occurrence.activity.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.hcNight)
                            .frame(width: 52, height: 52)
                            .background(occurrence.isCancelled ? Color.hcMuted : Color(occurrence.activity.child?.palette.soft ?? Theme.Palette.muted), in: Circle())
                            .overlay(alignment: .bottomTrailing) {
                                if occurrence.isCancelled {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(Color.hcLime)
                                        .frame(width: 20, height: 20)
                                        .background(Color.hcNight, in: Circle())
                                        .offset(x: 2, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!access.canEdit)
                    .accessibilityLabel(Text("\(occurrence.activity.title ?? ""), \(occurrence.start.formatted(.dateTime.weekday(.wide).hour().minute()))"))
                    .accessibilityValue(occurrence.isCancelled ? Text("Cancelada") : Text(""))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    /// Today and the next two days, cancelled ones included so they can be brought back.
    private var upcoming: [ActivityOccurrence] {
        guard let member else { return [] }
        let activities = Array((member.activities as? Set<Activity>) ?? [])
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<IllnessAgenda.daysAhead)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .flatMap { ActivitySchedule.occurrences(of: activities, on: $0) }
            .filter { $0.start >= .now }
    }
}

/// Every temperature with who took it, and the notes; swipe to delete a mistaken reading.
struct EpisodeHistory: View {
    @ObservedObject var episode: IllnessEpisode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.access) private var access
    @State private var notes = ""
    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TemperatureChart(readings: episode.sortedReadings)
                        .frame(height: 160)
                }
                Section {
                    ForEach(episode.sortedReadings.reversed(), id: \.objectID) { reading in
                        ReadingRow(reading: reading)
                    }
                    .onDelete { offsets in
                        let shown = Array(episode.sortedReadings.reversed())
                        for offset in offsets { persistence.delete(shown[offset]) }
                    }
                    .deleteDisabled(!episode.isActive || !access.canManageEpisode)
                }
                Section {
                    TextField("Notas", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .disabled(!episode.isActive || !access.canManageEpisode)
                        .onChange(of: notes) { _, newValue in
                            if newValue != (episode.notes ?? "") {
                                persistence.setNotes(newValue, in: episode)
                            }
                        }
                }
            }
            .onAppear { notes = episode.notes ?? "" }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
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
            if let recorder = reading.recordedBy {
                MemberAvatar(member: recorder, size: 24)
            }
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
