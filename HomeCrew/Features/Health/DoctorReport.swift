import Charts
import CoreGraphics
import SwiftUI

/// What goes into the PDF for the doctor: one person's health record and their episodes in a period.
struct DoctorReport {
    /// Quick choices for the period; "Personalizado" lets the parents pick both dates.
    enum Period: Int, CaseIterable, Identifiable {
        case week, month, threeMonths, year, custom

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .week: "7 dias"
            case .month: "30 dias"
            case .threeMonths: "3 meses"
            case .year: "1 ano"
            case .custom: "Personalizado"
            }
        }

        func interval(endingAt end: Date, calendar: Calendar = .current) -> DateInterval? {
            let start: Date?
            switch self {
            case .week: start = calendar.date(byAdding: .day, value: -7, to: end)
            case .month: start = calendar.date(byAdding: .day, value: -30, to: end)
            case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: end)
            case .year: start = calendar.date(byAdding: .year, value: -1, to: end)
            case .custom: start = nil
            }
            return start.map { DateInterval(start: $0, end: end) }
        }
    }

    let member: Member
    let period: DateInterval
    let createdAt: Date

    /// Episodes that overlap the period, oldest first, so the PDF reads as a story.
    var episodes: [IllnessEpisode] {
        member.episodeHistory
            .filter { episode in
                guard let start = episode.startedAt else { return false }
                return start <= period.end && (episode.endedAt ?? .distantFuture) >= period.start
            }
            .reversed()
    }

    var fileName: String {
        let name = (member.name ?? "HomeCrew").replacingOccurrences(of: "/", with: "-")
        let day = createdAt.formatted(.iso8601.year().month().day())
        return "\(name) \(day).pdf"
    }
}

enum DoctorReportRenderer {
    /// A4 in points.
    static let pageSize = CGSize(width: 595, height: 842)

    /// Writes the report as an A4 PDF in the temporary folder: the health record first, then one page per episode.
    @MainActor
    static func render(_ report: DoctorReport, to directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let url = directory.appendingPathComponent(report.fileName)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var pages: [AnyView] = [AnyView(RecordPage(report: report))]
        pages += report.episodes.map { AnyView(EpisodePage(report: report, episode: $0)) }

        for page in pages {
            let renderer = ImageRenderer(
                content: page
                    .frame(width: pageSize.width, height: pageSize.height, alignment: .top)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }
}

// MARK: - Pages

private enum ReportStyle {
    static let margin: CGFloat = 40
    static let title = Font.system(size: 20, weight: .bold)
    static let heading = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 10.5)
    static let small = Font.system(size: 9)
    static let ink = Color.black
    static let secondary = Color(white: 0.35)
    static let rule = Color(white: 0.8)
}

private struct PageHeader: View {
    let report: DoctorReport
    let title: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                title.font(ReportStyle.title)
                Spacer()
                Text(verbatim: "HomeCrew").font(ReportStyle.small).foregroundStyle(ReportStyle.secondary)
            }
            HStack {
                Text(report.member.name ?? "").font(ReportStyle.heading)
                if let birth = report.member.birthDate {
                    Text(birth, format: .dateTime.day().month().year())
                        .font(ReportStyle.body)
                        .foregroundStyle(ReportStyle.secondary)
                }
                Spacer()
                Text(report.period.start, format: .dateTime.day().month().year())
                    + Text(verbatim: " – ")
                    + Text(report.period.end, format: .dateTime.day().month().year())
            }
            .font(ReportStyle.body)
            Rectangle().fill(ReportStyle.rule).frame(height: 1)
        }
    }
}

private struct Field: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(ReportStyle.body.weight(.semibold))
                    .frame(width: 130, alignment: .leading)
                Text(value).font(ReportStyle.body)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct RecordPage: View {
    let report: DoctorReport

    var body: some View {
        let member = report.member
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(report: report, title: Text("Ficha de saúde"))
            VStack(alignment: .leading, spacing: 6) {
                Field(title: "Alergias", value: member.allergyList.joined(separator: ", "))
                Field(title: "Peso", value: member.weightKg > 0
                      ? member.weightKg.formatted(.number.precision(.fractionLength(0...1))) + " kg" : "")
                Field(title: "Doenças crónicas", value: member.chronicConditions ?? "")
                Field(title: "Medicação habitual", value: member.usualMedication ?? "")
                Field(title: "Pediatra", value: [member.pediatricianName, member.pediatricianPhone]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            }
            Text("Episódios").font(ReportStyle.heading).padding(.top, 8)
            if report.episodes.isEmpty {
                Text("Sem episódios neste período.").font(ReportStyle.body).foregroundStyle(ReportStyle.secondary)
            } else {
                ForEach(report.episodes, id: \.objectID) { episode in
                    HStack {
                        EpisodeDates(episode: episode)
                        Spacer()
                        if let highest = episode.highestCelsius {
                            Text("Máx. \(highest.formatted(.number.precision(.fractionLength(1))))°")
                        }
                    }
                    .font(ReportStyle.body)
                }
            }
            Spacer(minLength: 0)
            Footer(report: report)
        }
        .foregroundStyle(ReportStyle.ink)
        .padding(ReportStyle.margin)
    }
}

private struct EpisodeDates: View {
    let episode: IllnessEpisode

    var body: some View {
        let start = Text(episode.startedAt ?? .now, format: .dateTime.day().month().year())
        if let end = episode.endedAt {
            start + Text(verbatim: " – ") + Text(end, format: .dateTime.day().month().year())
        } else {
            start + Text(verbatim: " – ") + Text("em curso")
        }
    }
}

private struct EpisodePage: View {
    let report: DoctorReport
    let episode: IllnessEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(report: report, title: Text("Episódio de doença"))
            EpisodeDates(episode: episode).font(ReportStyle.heading)

            Text("Temperatura").font(ReportStyle.heading)
            if episode.sortedReadings.isEmpty {
                Text("Sem temperaturas").font(ReportStyle.body).foregroundStyle(ReportStyle.secondary)
            } else {
                TemperatureChart(readings: episode.sortedReadings)
                    .frame(height: 170)
                Text(readingsLine)
                    .font(ReportStyle.small)
                    .foregroundStyle(ReportStyle.secondary)
                    .lineLimit(4)
            }

            Text("Sintomas").font(ReportStyle.heading)
            Text(Symptom.allCases.filter(episode.symptoms.contains).map(\.title).joined(separator: ", ").ifEmpty("—"))
                .font(ReportStyle.body)

            Text("Medicação").font(ReportStyle.heading)
            if episode.sortedMedications.isEmpty {
                Text(verbatim: "—").font(ReportStyle.body)
            } else {
                ForEach(episode.sortedMedications, id: \.objectID) { medication in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medicationLine(medication)).font(ReportStyle.body.weight(.semibold))
                        Text(dosesLine(medication))
                            .font(ReportStyle.small)
                            .foregroundStyle(ReportStyle.secondary)
                            .lineLimit(4)
                    }
                }
            }

            if let notes = episode.notes, !notes.isEmpty {
                Text("Notas").font(ReportStyle.heading)
                Text(notes).font(ReportStyle.body).lineLimit(12)
            }
            Spacer(minLength: 0)
            Footer(report: report)
        }
        .foregroundStyle(ReportStyle.ink)
        .padding(ReportStyle.margin)
    }

    private var readingsLine: String {
        episode.sortedReadings.map { reading in
            let time = (reading.takenAt ?? .now).formatted(.dateTime.day().month().hour().minute())
            return "\(time) \(reading.celsius.formatted(.number.precision(.fractionLength(1))))°"
        }
        .joined(separator: " · ")
    }

    private func medicationLine(_ medication: Medication) -> String {
        let interval = String(localized: "de \(Int(medication.intervalHours)) em \(Int(medication.intervalHours)) h")
        return [medication.name, medication.dose, interval]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func dosesLine(_ medication: Medication) -> String {
        let doses = medication.sortedDoses.reversed().map {
            ($0.givenAt ?? .now).formatted(.dateTime.day().month().hour().minute())
        }
        return doses.isEmpty
            ? String(localized: "Sem doses registadas")
            : String(localized: "\(doses.count) doses: \(doses.joined(separator: ", "))")
    }
}

private struct Footer: View {
    let report: DoctorReport

    var body: some View {
        HStack {
            Text("Registado pela família na app HomeCrew. Não substitui a avaliação médica.")
            Spacer()
            Text(report.createdAt, format: .dateTime.day().month().year())
        }
        .font(ReportStyle.small)
        .foregroundStyle(ReportStyle.secondary)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
