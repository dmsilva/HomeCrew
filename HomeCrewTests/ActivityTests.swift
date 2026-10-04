import CoreData
import UIKit
import XCTest
@testable import HomeCrew

final class ActivityTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        family = persistence.createFamily(named: "Silva")
        var member = MemberDraft()
        member.name = "Rita"
        rita = persistence.addMember(member, to: family)
    }

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))!
    }

    private func draft(_ title: String, weekdays: Set<Int>, at minutes: Int) -> ActivityDraft {
        var draft = ActivityDraft()
        draft.title = title
        draft.child = rita
        draft.weekdays = weekdays
        draft.startMinutes = minutes
        draft.startDate = day(1)
        return draft
    }

    func testCreatedActivityKeepsItsDetails() {
        var football = draft(" Futebol ", weekdays: [3, 5], at: 18 * 60 + 30)
        football.location = "Estádio"
        football.equipment = "Chuteiras, garrafa"
        football.symbolName = "soccerball"

        let activity = persistence.addActivity(football, to: family)

        XCTAssertEqual(activity.title, "Futebol")
        XCTAssertEqual(activity.weekdays, [3, 5])
        XCTAssertEqual(activity.startMinutes, 18 * 60 + 30)
        XCTAssertEqual(activity.location, "Estádio")
        XCTAssertEqual(activity.equipment, "Chuteiras, garrafa")
        XCTAssertEqual(activity.symbol, "soccerball")
        XCTAssertEqual(activity.child, rita)
    }

    func testOccurrencesFollowTheWeekdaysAndAreSortedByTime() {
        // 6 Oct 2026 is a Tuesday (weekday 3).
        let swim = persistence.addActivity(draft("Natação", weekdays: [3], at: 19 * 60), to: family)
        let football = persistence.addActivity(draft("Futebol", weekdays: [3, 5], at: 18 * 60), to: family)
        let music = persistence.addActivity(draft("Música", weekdays: [4], at: 17 * 60), to: family)

        let tuesday = ActivitySchedule.occurrences(of: [swim, football, music], on: day(6), calendar: calendar)

        XCTAssertEqual(tuesday.map(\.activity), [football, swim])
        XCTAssertEqual(tuesday.first.map { calendar.component(.hour, from: $0.start) }, 18)
    }

    func testWeekStartsOnMonday() {
        let week = ActivitySchedule.week(containing: day(4), calendar: calendar) // Sunday 4 Oct

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map { calendar.component(.day, from: $0) }, [28, 29, 30, 1, 2, 3, 4])
        XCTAssertEqual(calendar.component(.weekday, from: week[0]), 2)
    }

    func testEditingAndDeletingAnActivity() throws {
        let activity = persistence.addActivity(draft("Futebol", weekdays: [3], at: 18 * 60), to: family)

        var edit = ActivityDraft(activity)
        edit.weekdays = [2, 4]
        edit.equipment = "Caneleiras"
        persistence.update(activity, with: edit)
        XCTAssertEqual(activity.weekdays, [2, 4])
        XCTAssertEqual(activity.equipment, "Caneleiras")

        persistence.delete(activity)
        XCTAssertEqual(try persistence.viewContext.count(for: Activity.all()), 0)
    }

    func testRemovingTheChildKeepsTheActivity() {
        let activity = persistence.addActivity(draft("Futebol", weekdays: [3], at: 18 * 60), to: family)

        persistence.delete(rita)

        XCTAssertNil(activity.child)
        XCTAssertFalse(activity.isDeleted)
    }

    func testDraftNeedsATitleAndAWeekday() {
        XCTAssertFalse(draft("Futebol", weekdays: [], at: 0).isValid)
        XCTAssertFalse(draft(" ", weekdays: [2], at: 0).isValid)
        XCTAssertTrue(draft("Futebol", weekdays: [2], at: 0).isValid)
    }

    func testEveryOfferedSymbolExists() {
        for symbol in Activity.symbols {
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing SF Symbol \(symbol)")
        }
    }
}

final class DropOffPickUpTests: XCTestCase {
    private var persistence: PersistenceController!
    private var activity: Activity!
    private var mum: Member!
    private var dad: Member!
    private var grandma: Member!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))!
    }

    private func adult(_ name: String, in family: Family) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = .adult
        return persistence.addMember(draft, to: family)
    }

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let family = persistence.createFamily(named: "Silva")
        mum = adult("Ana", in: family)
        dad = adult("Daniel", in: family)
        grandma = adult("Avó", in: family)

        var draft = ActivityDraft()
        draft.title = "Futebol"
        draft.weekdays = [3] // Tuesdays
        draft.startDate = day(1)
        draft.dropOff = mum
        draft.pickUp = dad
        activity = persistence.addActivity(draft, to: family)
    }

    func testTheRuleAppliesEveryWeek() {
        XCTAssertEqual(activity.dropOff(on: day(6), calendar: calendar), mum)
        XCTAssertEqual(activity.pickUp(on: day(13), calendar: calendar), dad)
    }

    func testChangingOneDayLeavesTheRuleAlone() {
        persistence.overrideDrivers(activity, on: day(6), dropOff: grandma, pickUp: nil, calendar: calendar)

        XCTAssertEqual(activity.dropOff(on: day(6), calendar: calendar), grandma)
        XCTAssertEqual(activity.pickUp(on: day(6), calendar: calendar), dad, "Unchanged side keeps the rule")
        XCTAssertEqual(activity.dropOff(on: day(13), calendar: calendar), mum)
        XCTAssertEqual(activity.dropOff, mum)
    }

    func testClearingTheChangeReturnsTheDayToTheRule() throws {
        persistence.overrideDrivers(activity, on: day(6), dropOff: grandma, pickUp: nil, calendar: calendar)
        persistence.overrideDrivers(activity, on: day(6), dropOff: nil, pickUp: nil, calendar: calendar)

        XCTAssertNil(activity.exception(on: day(6), calendar: calendar))
        let request = NSFetchRequest<ActivityException>(entityName: "ActivityException")
        XCTAssertEqual(try persistence.viewContext.count(for: request), 0)
    }

    func testCancellingOneDayShowsInTheSchedule() {
        persistence.setCancelled(true, activity, on: day(6), calendar: calendar)

        let tuesday = ActivitySchedule.occurrences(of: [activity], on: day(6), calendar: calendar)
        let nextTuesday = ActivitySchedule.occurrences(of: [activity], on: day(13), calendar: calendar)

        XCTAssertEqual(tuesday.first?.isCancelled, true)
        XCTAssertEqual(nextTuesday.first?.isCancelled, false)
    }

    func testRestoringACancelledDayKeepsItsDriverChange() {
        persistence.overrideDrivers(activity, on: day(6), dropOff: grandma, pickUp: nil, calendar: calendar)
        persistence.setCancelled(true, activity, on: day(6), calendar: calendar)
        persistence.setCancelled(false, activity, on: day(6), calendar: calendar)

        XCTAssertFalse(activity.isCancelled(on: day(6), calendar: calendar))
        XCTAssertEqual(activity.dropOff(on: day(6), calendar: calendar), grandma)
    }

    func testScheduleCarriesTheRightPeopleForEachDay() {
        persistence.overrideDrivers(activity, on: day(6), dropOff: grandma, pickUp: grandma, calendar: calendar)

        let tuesday = ActivitySchedule.occurrences(of: [activity], on: day(6), calendar: calendar).first
        let nextTuesday = ActivitySchedule.occurrences(of: [activity], on: day(13), calendar: calendar).first

        XCTAssertEqual(tuesday?.dropOff, grandma)
        XCTAssertEqual(tuesday?.pickUp, grandma)
        XCTAssertEqual(nextTuesday?.dropOff, mum)
        XCTAssertEqual(nextTuesday?.pickUp, dad)
    }

    func testRemovingADriverFallsBackToNobody() {
        persistence.delete(mum)
        XCTAssertNil(activity.dropOff(on: day(6), calendar: calendar))
    }

    func testFamilyAdultsExcludeChildren() {
        var child = MemberDraft()
        child.name = "Rita"
        child.kind = .child
        let family = try! XCTUnwrap(activity.family)
        persistence.addMember(child, to: family)

        XCTAssertEqual(Set(family.adults), [mum, dad, grandma])
    }
}
