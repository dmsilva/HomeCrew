import CoreData
import XCTest
@testable import HomeCrew

final class RecurrenceTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    private func day(_ d: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: 15))!
    }

    // 4 Oct 2026 is a Sunday.
    private let sunday = 1, monday = 2, wednesday = 4

    func testOnceHappensOnlyOnItsDay() {
        let recurrence = Recurrence.once
        XCTAssertTrue(recurrence.occurs(on: day(6), startingFrom: day(6), calendar: calendar))
        XCTAssertFalse(recurrence.occurs(on: day(7), startingFrom: day(6), calendar: calendar))
        XCTAssertFalse(recurrence.occurs(on: day(5), startingFrom: day(6), calendar: calendar))
    }

    func testDailyHappensEveryDayFromItsStart() {
        let days = Recurrence.daily.occurrences(
            in: DateInterval(start: day(4), end: day(10)),
            startingFrom: day(6),
            calendar: calendar
        )
        XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, [6, 7, 8, 9, 10])
    }

    func testWeeklyHappensOnTheChosenWeekdays() {
        let days = Recurrence.weekly([monday, wednesday]).occurrences(
            in: DateInterval(start: day(4), end: day(18)),
            startingFrom: day(4),
            calendar: calendar
        )
        XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, [5, 7, 12, 14])
    }

    func testWeeklyIgnoresWeekdaysBeforeTheStart() {
        let days = Recurrence.weekly([sunday]).occurrences(
            in: DateInterval(start: day(1), end: day(18)),
            startingFrom: day(5),
            calendar: calendar
        )
        XCTAssertEqual(days.map { calendar.component(.day, from: $0) }, [11, 18])
    }

    func testWeekdayMaskRoundTrips() {
        let weekdays: Set<Int> = [1, 4, 7]
        XCTAssertEqual(WeekdayMask.decode(WeekdayMask.encode(weekdays)), weekdays)
        XCTAssertEqual(WeekdayMask.encode([0, 8]), 0, "Out-of-range weekdays are dropped")
    }
}

final class ChoreTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        family = persistence.createFamily(named: "Silva")
        var member = MemberDraft()
        member.name = "Rita"
        rita = persistence.addMember(member, to: family)
    }

    private func draft(_ title: String, _ recurrence: Recurrence = .daily) -> ChoreDraft {
        var draft = ChoreDraft()
        draft.title = title
        draft.assignee = rita
        draft.recurrence = recurrence
        draft.startDate = .now
        return draft
    }

    func testCreatedChoreKeepsItsRecurrenceAndAssignee() {
        let chore = persistence.addChore(draft(" Fazer a cama ", .weekly([2, 4])), to: family)

        XCTAssertEqual(chore.title, "Fazer a cama")
        XCTAssertEqual(chore.recurrence, .weekly([2, 4]))
        XCTAssertEqual(chore.assignee, rita)
        XCTAssertEqual(chore.family, family)
        XCTAssertEqual(chore.points, 0)
    }

    func testEditingAChoreIsSaved() {
        let chore = persistence.addChore(draft("Cama"), to: family)

        var edit = ChoreDraft(chore)
        edit.title = "Arrumar quarto"
        edit.recurrence = .once
        persistence.update(chore, with: edit)

        XCTAssertEqual(chore.title, "Arrumar quarto")
        XCTAssertEqual(chore.recurrence, .once)
        XCTAssertFalse(persistence.viewContext.hasChanges)
    }

    func testDeletingAChoreRemovesItsCompletions() throws {
        let chore = persistence.addChore(draft("Cama"), to: family)
        persistence.toggleDone(chore, on: .now)

        persistence.delete(chore)

        let completions = NSFetchRequest<ChoreCompletion>(entityName: "ChoreCompletion")
        XCTAssertEqual(try persistence.viewContext.count(for: completions), 0)
        XCTAssertEqual(try persistence.viewContext.count(for: Chore.all()), 0)
    }

    func testMarkingDoneRecordsWhoAndWhen() throws {
        let chore = persistence.addChore(draft("Cama"), to: family)
        let before = Date.now

        persistence.toggleDone(chore, on: .now)

        let completion = try XCTUnwrap(chore.completion(on: .now))
        XCTAssertEqual(completion.completedBy, rita)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(completion.completedAt), before)
        XCTAssertEqual(completion.occurrenceDate, Calendar.current.startOfDay(for: .now))
    }

    func testMarkingDoneTwiceUndoesIt() {
        let chore = persistence.addChore(draft("Cama"), to: family)

        persistence.toggleDone(chore, on: .now)
        persistence.toggleDone(chore, on: .now)

        XCTAssertNil(chore.completion(on: .now))
    }

    func testCompletionsAreKeptPerDay() throws {
        let chore = persistence.addChore(draft("Cama"), to: family)
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))

        persistence.toggleDone(chore, on: .now)

        XCTAssertNotNil(chore.completion(on: .now))
        XCTAssertNil(chore.completion(on: tomorrow))
    }

    func testCompletionCopiesThePointsOfTheChore() throws {
        let chore = persistence.addChore(draft("Cama"), to: family)
        chore.points = 5

        persistence.toggleDone(chore, on: .now)
        chore.points = 10

        XCTAssertEqual(try XCTUnwrap(chore.completion(on: .now)).pointsAwarded, 5)
    }

    func testRemovingTheAssigneeKeepsTheChore() {
        let chore = persistence.addChore(draft("Cama"), to: family)

        persistence.delete(rita)

        XCTAssertNil(chore.assignee)
        XCTAssertFalse(chore.isDeleted)
    }

    func testWeeklyDraftNeedsAtLeastOneWeekday() {
        XCTAssertFalse(draft("Cama", .weekly([])).isValid)
        XCTAssertTrue(draft("Cama", .weekly([2])).isValid)
        XCTAssertFalse(draft("  ").isValid)
    }
}
