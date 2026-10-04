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
