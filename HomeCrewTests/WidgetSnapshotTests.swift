import CoreData
import XCTest
@testable import HomeCrew

final class WidgetSnapshotTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!
    private var mum: Member!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        family = persistence.createFamily(named: "Silva")
        var draft = MemberDraft()
        draft.name = "Rita"
        draft.kind = .child
        rita = persistence.addMember(draft, to: family)
        draft.name = "Ana"
        draft.kind = .adult
        mum = persistence.addMember(draft, to: family)
    }

    /// 6 Oct 2026 is a Tuesday (weekday 3).
    private func october(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func snapshot(now: Date) -> WidgetSnapshot {
        WidgetSnapshot.build(
            day: now,
            activities: (try? persistence.viewContext.fetch(Activity.all())) ?? [],
            chores: (try? persistence.viewContext.fetch(Chore.all())) ?? [],
            medications: (try? persistence.viewContext.fetch(Medication.all())) ?? [],
            me: mum,
            access: .full,
            now: now,
            calendar: calendar
        )
    }

    private func addActivities() {
        for (title, hour) in [("Natação", 9), ("Futebol", 18)] {
            var draft = ActivityDraft()
            draft.title = title
            draft.child = rita
            draft.weekdays = [3]
            draft.startMinutes = hour * 60
            draft.startDate = october(1)
            persistence.addActivity(draft, to: family)
        }
        var chore = ChoreDraft()
        chore.title = "Mochila"
        chore.assignee = rita
        chore.startDate = october(1)
        persistence.addChore(chore, to: family)
    }

    func testTodayItemsAreTheDaysActivitiesThenChores() {
        addActivities()
        let snapshot = snapshot(now: october(6, 8))

        XCTAssertEqual(snapshot.items.map(\.title), ["Natação", "Futebol", "Mochila"])
        XCTAssertEqual(snapshot.items.first?.person, "Rita")
        XCTAssertEqual(snapshot.items.last?.symbol, "checklist")
    }

    func testFinishedActivitiesDropOffAndOnlyTodayCounts() {
        addActivities()
        let snapshot = snapshot(now: october(6, 8))

        XCTAssertEqual(snapshot.upcoming(after: october(6, 10), calendar: calendar).map(\.title), ["Futebol", "Mochila"])
        XCTAssertEqual(snapshot.upcoming(after: october(7, 8), calendar: calendar), [])
    }

    func testDoneChoresAreNotUpcoming() {
        addActivities()
        let chore = try! persistence.viewContext.fetch(Chore.all()).first!
        persistence.toggleDone(chore, on: october(6), by: mum, calendar: calendar)

        let snapshot = snapshot(now: october(6, 8))
        XCTAssertEqual(snapshot.upcoming(after: october(6, 8), calendar: calendar).map(\.title), ["Natação", "Futebol"])
    }

    func testNextDoseIsTheSoonest() {
        let episode = persistence.openEpisode(for: rita, at: october(6, 8))
        var later = MedicationDraft()
        later.name = "Brufen"
        later.intervalHours = 8
        later.givenNow = true
        persistence.addMedication(later, to: episode, by: mum, at: october(6, 8))
        var sooner = MedicationDraft()
        sooner.name = "Ben-u-ron"
        sooner.dose = "7,5 ml"
        sooner.intervalHours = 6
        sooner.givenNow = true
        persistence.addMedication(sooner, to: episode, by: mum, at: october(6, 8))

        let next = snapshot(now: october(6, 9)).nextDose(after: october(6, 9))

        XCTAssertEqual(next?.medicine, "Ben-u-ron")
        XCTAssertEqual(next?.nextAt, october(6, 14))
        XCTAssertEqual(next?.amount, "7,5 ml")
    }

    func testEndedEpisodesLeaveNoDoses() {
        let episode = persistence.openEpisode(for: rita, at: october(6, 8))
        var draft = MedicationDraft()
        draft.name = "Brufen"
        persistence.addMedication(draft, to: episode, by: mum, at: october(6, 8))
        persistence.end(episode, at: october(6, 9))

        XCTAssertEqual(snapshot(now: october(6, 10)).doses, [])
    }

    func testRoundTripsThroughAFile() throws {
        addActivities()
        let snapshot = snapshot(now: october(6, 8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        try snapshot.save(to: url)

        XCTAssertEqual(WidgetSnapshot.load(from: url), snapshot)
    }
}
