import CoreData
import XCTest
@testable import HomeCrew

final class CustodyTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!
    private var tomas: Member!
    private var mum: Member!
    private var dad: Member!
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
        dad = member("João", .adult)
    }

    private func member(_ name: String, _ kind: Member.Kind) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    /// 5 Oct 2026 is a Monday.
    private func october(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func plan(_ pattern: CustodyPattern, custom: [Bool]? = nil) -> CustodyPlan {
        var draft = CustodyDraft()
        draft.parentA = mum
        draft.parentB = dad
        draft.pattern = pattern
        draft.startDate = calendar.startOfDay(for: october(5))
        if let custom { draft.customDays = custom }
        return persistence.setCustody(draft, for: rita)
    }

    private func houses(_ plan: CustodyPlan, from day: Int, count: Int) -> String {
        (day..<day + count).map { plan.house(on: october($0), calendar: calendar) == .a ? "A" : "B" }.joined()
    }

    func testAlternateWeeks() {
        let plan = plan(.alternateWeeks)
        XCTAssertEqual(houses(plan, from: 5, count: 21), "AAAAAAABBBBBBBAAAAAAA")
    }

    func testTwoTwoThree() {
        let plan = plan(.twoTwoThree)
        XCTAssertEqual(houses(plan, from: 5, count: 14), "AABBAAABBAABBB")
        XCTAssertEqual(houses(plan, from: 19, count: 2), "AA")
    }

    func testCustomCycle() {
        let custom = Array("ABABABABABABAB").map { $0 == "A" }
        let plan = plan(.custom, custom: custom)
        XCTAssertEqual(houses(plan, from: 5, count: 16), "ABABABABABABABAB")
    }

    func testDaysBeforeTheStartFollowTheSameCycle() {
        let plan = plan(.alternateWeeks)
        XCTAssertEqual(houses(plan, from: 1, count: 4), "BBBB")
    }

    func testCustodianIsTheParentOfThatHouse() {
        let plan = plan(.alternateWeeks)
        XCTAssertEqual(plan.custodian(on: october(6), calendar: calendar), mum)
        XCTAssertEqual(plan.custodian(on: october(13), calendar: calendar), dad)
    }

    func testIsWithFollowsThePlanAndDefaultsToTrue() {
        _ = plan(.alternateWeeks)
        XCTAssertTrue(rita.isWith(mum, on: october(6), calendar: calendar))
        XCTAssertFalse(rita.isWith(dad, on: october(6), calendar: calendar))
        XCTAssertTrue(tomas.isWith(dad, on: october(6), calendar: calendar), "No plan: always with you")
        XCTAssertTrue(rita.isWith(nil, on: october(6), calendar: calendar), "Unknown viewer sees everyone")
    }

    func testSavingAgainReplacesThePlan() {
        _ = plan(.alternateWeeks)
        let replaced = plan(.twoTwoThree)

        XCTAssertEqual(rita.custodyPlans?.count, 1)
        XCTAssertEqual(rita.custodyPlan, replaced)
        XCTAssertEqual(replaced.pattern, .twoTwoThree)
    }

    func testRemovingTheCustody() {
        _ = plan(.alternateWeeks)
        persistence.removeCustody(of: rita)
        XCTAssertNil(rita.custodyPlan)
    }

    func testTheSameParentTwiceIsInvalid() {
        var draft = CustodyDraft()
        draft.parentA = mum
        draft.parentB = mum
        XCTAssertFalse(draft.isValid)
        draft.parentB = dad
        XCTAssertTrue(draft.isValid)
    }

    func testTodayShowsOnlyTheChildrenWithYou() {
        _ = plan(.alternateWeeks)
        let football = activity("Futebol", for: rita)
        let swim = activity("Natação", for: tomas)

        let mumsMonday = TodayDigest.build(day: october(12), activities: [football, swim], chores: [], viewer: mum, calendar: calendar)
        let dadsMonday = TodayDigest.build(day: october(12), activities: [football, swim], chores: [], viewer: dad, calendar: calendar)

        XCTAssertEqual(mumsMonday.activities.map(\.activity), [swim])
        XCTAssertEqual(Set(dadsMonday.activities.map(\.activity)), [football, swim])
    }

    func testDoseRemindersGoToWhoeverHasTheChild() {
        _ = plan(.alternateWeeks)
        let episode = persistence.openEpisode(for: rita, at: october(12, 8))
        var draft = MedicationDraft()
        draft.name = "Brufen"
        draft.intervalHours = 8
        draft.givenNow = true
        let medication = persistence.addMedication(draft, to: episode, by: dad, at: october(12, 8))

        XCTAssertEqual(DoseReminders.plan(medications: [medication], me: dad, now: october(12, 9)).count, 1)
        XCTAssertEqual(DoseReminders.plan(medications: [medication], me: mum, now: october(12, 9)).count, 0)
    }

    func testMonthGridStartsOnMonday() {
        // October 2026 starts on a Thursday: three blanks before the 1st.
        let days = CustodyMonthGrid.days(in: october(15), calendar: calendar)
        XCTAssertEqual(days.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertNotNil(days[3])
        XCTAssertEqual(days.compactMap { $0 }.count, 31)
    }

    private func activity(_ title: String, for child: Member) -> Activity {
        var draft = ActivityDraft()
        draft.title = title
        draft.child = child
        draft.weekdays = Set(1...7)
        draft.startMinutes = 17 * 60
        draft.startDate = october(1)
        return persistence.addActivity(draft, to: family)
    }
}
