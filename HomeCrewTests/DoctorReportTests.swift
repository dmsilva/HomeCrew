import CoreGraphics
import XCTest
@testable import HomeCrew

final class DoctorReportTests: XCTestCase {
    private var persistence: PersistenceController!
    private var rita: Member!
    private var mum: Member!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let family = persistence.createFamily(named: "Silva")
        var draft = MemberDraft()
        draft.name = "Rita"
        draft.kind = .child
        rita = persistence.addMember(draft, to: family)
        draft.name = "Ana"
        draft.kind = .adult
        mum = persistence.addMember(draft, to: family)
    }

    private func days(_ value: Double) -> Date { now.addingTimeInterval(value * 86_400) }

    @discardableResult
    private func episode(from start: Double, to end: Double?) -> IllnessEpisode {
        let episode = persistence.openEpisode(for: rita, at: days(start))
        if let end { persistence.end(episode, at: days(end)) }
        return episode
    }

    /// The example episode: fever, symptoms, Ben-u-ron with two doses and a note.
    private func exampleEpisode() -> IllnessEpisode {
        var record = HealthRecordDraft(rita)
        record.allergies = "Amendoim"
        record.weightKg = 18
        record.pediatricianName = "Dra. Costa"
        persistence.updateHealthRecord(of: rita, with: record)

        let episode = persistence.openEpisode(for: rita, at: days(-3))
        for (hour, celsius) in [(0.0, 37.8), (4, 38.6), (8, 39.1), (14, 38.2), (24, 37.4)] {
            persistence.recordTemperature(celsius, in: episode, at: days(-3).addingTimeInterval(hour * 3600))
        }
        persistence.setSymptom(.cough, present: true, in: episode)
        persistence.setSymptom(.earache, present: true, in: episode)
        persistence.setNotes("Dormiu mal na primeira noite.", in: episode)
        var medication = MedicationDraft()
        medication.name = "Ben-u-ron"
        medication.dose = "7,5 ml"
        medication.intervalHours = 6
        medication.givenNow = true
        let benuron = persistence.addMedication(medication, to: episode, by: mum, at: days(-3))
        persistence.giveDose(of: benuron, by: mum, at: days(-3).addingTimeInterval(6 * 3600))
        persistence.end(episode, at: days(-1))
        return episode
    }

    func testOnlyEpisodesOverlappingThePeriodOldestFirst() {
        episode(from: -60, to: -55)
        let older = episode(from: -20, to: -15)
        let spanning = episode(from: -8, to: -5)
        let open = episode(from: -1, to: nil)

        let report = DoctorReport(member: rita, period: DateInterval(start: days(-18), end: now), createdAt: now)

        XCTAssertEqual(report.episodes, [older, spanning, open])
    }

    func testPresetPeriodsEndNow() {
        let calendar = Calendar(identifier: .gregorian)
        let week = DoctorReport.Period.week.interval(endingAt: now, calendar: calendar)

        XCTAssertEqual(week?.end, now)
        XCTAssertEqual(week?.duration, 7 * 86_400)
        XCTAssertNil(DoctorReport.Period.custom.interval(endingAt: now, calendar: calendar))
    }

    func testFileNameHasThePersonAndTheDay() {
        let report = DoctorReport(member: rita, period: DateInterval(start: days(-7), end: now), createdAt: now)
        XCTAssertTrue(report.fileName.hasPrefix("Rita "))
        XCTAssertTrue(report.fileName.hasSuffix(".pdf"))
    }

    @MainActor
    func testExampleEpisodeRendersAnA4PDFWithOnePagePerEpisode() throws {
        exampleEpisode()
        let report = DoctorReport(member: rita, period: DateInterval(start: days(-30), end: now), createdAt: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try DoctorReportRenderer.render(report, to: directory)

        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
        let box = try XCTUnwrap(pdf.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 595, accuracy: 1)
        XCTAssertEqual(box.height, 842, accuracy: 1)
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 5_000, "The pages should have drawn content")
    }

    @MainActor
    func testAPeriodWithoutEpisodesStillHasTheRecordPage() throws {
        let report = DoctorReport(member: rita, period: DateInterval(start: days(-7), end: now), createdAt: now)

        let url = try DoctorReportRenderer.render(report)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 1)
    }
}
