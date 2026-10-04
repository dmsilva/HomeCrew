import CoreData
import XCTest
@testable import HomeCrew

final class IllnessAgendaTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!
    private var tomas: Member!
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
        rita = member("Rita", .child)
        tomas = member("Tomás", .child)
        mum = member("Ana", .adult)
    }

    private func member(_ name: String, _ kind: Member.Kind) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    /// 6 Oct 2026 is a Tuesday (weekday 3).
    private func october(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @discardableResult
    private func activity(_ title: String, for child: Member, weekdays: Set<Int>, at hour: Int) -> Activity {
        var draft = ActivityDraft()
        draft.title = title
        draft.child = child
        draft.weekdays = weekdays
        draft.startMinutes = hour * 60
        draft.startDate = october(1)
        return persistence.addActivity(draft, to: family)
    }

    func testAffectedAreTheComingActivitiesOfThatPersonInTheNextThreeDays() {
        let football = activity("Futebol", for: rita, weekdays: [3, 5], at: 18)
        let music = activity("Música", for: rita, weekdays: [4], at: 17)
        activity("Escola cedo", for: rita, weekdays: [3], at: 9)
        activity("Natação", for: rita, weekdays: [7], at: 10)
        activity("Futebol do Tomás", for: tomas, weekdays: [3], at: 18)

        let affected = IllnessAgenda.affected(for: rita, from: october(6), calendar: calendar)

        XCTAssertEqual(affected.map(\.activity), [football, music, football])
        XCTAssertEqual(affected.map(\.start), [october(6, 18), october(7, 17), october(8, 18)])
    }

    func testAlreadyCancelledDaysAreLeftOut() {
        let music = activity("Música", for: rita, weekdays: [4], at: 17)
        persistence.setCancelled(true, music, on: october(7), calendar: calendar)

        XCTAssertEqual(IllnessAgenda.affected(for: rita, from: october(6), calendar: calendar), [])
    }

    func testOnlyConfirmedOccurrencesAreCancelled() {
        activity("Futebol", for: rita, weekdays: [3, 5], at: 18)
        let affected = IllnessAgenda.affected(for: rita, from: october(6), calendar: calendar)

        persistence.cancelForIllness([affected[0]], addWarningTasks: false, assignee: mum, calendar: calendar)

        let after = IllnessAgenda.affected(for: rita, from: october(6), calendar: calendar)
        XCTAssertEqual(after.map(\.start), [october(8, 18)])
        XCTAssertTrue(affected[0].activity.isCancelled(on: october(6), calendar: calendar))
        XCTAssertFalse(affected[0].activity.isCancelled(on: october(8), calendar: calendar))
    }

    func testOneWarningTaskPerActivityForToday() throws {
        activity("Futebol", for: rita, weekdays: [3, 5], at: 18)
        activity("Música", for: rita, weekdays: [4], at: 17)
        let affected = IllnessAgenda.affected(for: rita, from: october(6), calendar: calendar)

        let tasks = persistence.cancelForIllness(affected, addWarningTasks: true, assignee: mum, on: october(6), calendar: calendar)

        XCTAssertEqual(tasks.map(\.title), ["Avisar Futebol · Rita", "Avisar Música · Rita"])
        XCTAssertEqual(tasks.map(\.assignee), [mum, mum])
        XCTAssertTrue(tasks.allSatisfy { $0.recurrence == .once })
        XCTAssertTrue(tasks.allSatisfy { $0.occurs(on: october(6), calendar: calendar) })
        XCTAssertTrue(tasks.allSatisfy { !$0.occurs(on: october(7), calendar: calendar) })
    }

    func testNoTaskWhenNotAsked() throws {
        activity("Futebol", for: rita, weekdays: [3], at: 18)
        let affected = IllnessAgenda.affected(for: rita, from: october(6), calendar: calendar)

        persistence.cancelForIllness(affected, addWarningTasks: false, assignee: nil, calendar: calendar)

        XCTAssertEqual(try persistence.viewContext.count(for: Chore.all()), 0)
    }
}
