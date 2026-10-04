import CoreData
import XCTest
@testable import HomeCrew

final class CustodySwapTests: XCTestCase {
    private var persistence: PersistenceController!
    private var rita: Member!
    private var mum: Member!
    private var dad: Member!
    private var plan: CustodyPlan!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let family = persistence.createFamily(named: "Silva")
        rita = member("Rita", .child, in: family)
        mum = member("Ana", .adult, in: family)
        dad = member("João", .adult, in: family)
        var draft = CustodyDraft()
        draft.parentA = mum
        draft.parentB = dad
        draft.pattern = .alternateWeeks
        draft.startDate = calendar.startOfDay(for: october(5))
        plan = persistence.setCustody(draft, for: rita)
    }

    private func member(_ name: String, _ kind: Member.Kind, in family: Family) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    /// 5 Oct 2026 is a Monday; mum has the first week, dad the second.
    private func october(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func custodians(from day: Int, count: Int) -> [String] {
        (day..<day + count).map { plan.custodian(on: october($0), calendar: calendar)?.name ?? "" }
    }

    func testARequestChangesNothingUntilAccepted() {
        let swap = persistence.requestSwap(in: plan, from: october(9), to: october(10), by: mum, at: october(1))

        XCTAssertEqual(swap.status, .pending)
        XCTAssertEqual(swap.responder, dad)
        XCTAssertEqual(custodians(from: 8, count: 4), ["Ana", "Ana", "Ana", "Ana"])
    }

    func testAcceptingHandsTheDaysToTheOtherHouse() {
        let swap = persistence.requestSwap(in: plan, from: october(9), to: october(10), by: mum, at: october(1))
        persistence.respond(to: swap, accept: true, at: october(2))

        XCTAssertEqual(swap.status, .accepted)
        XCTAssertEqual(custodians(from: 8, count: 4), ["Ana", "João", "João", "Ana"])
        XCTAssertTrue(rita.isWith(dad, on: october(9), calendar: calendar))
    }

    func testDecliningKeepsTheCalendar() {
        let swap = persistence.requestSwap(in: plan, from: october(9), to: october(9), by: mum, at: october(1))
        persistence.respond(to: swap, accept: false, at: october(2))

        XCTAssertEqual(swap.status, .declined)
        XCTAssertEqual(custodians(from: 9, count: 1), ["Ana"])
    }

    func testAnAnswerIsFinal() {
        let swap = persistence.requestSwap(in: plan, from: october(9), to: october(9), by: mum, at: october(1))
        persistence.respond(to: swap, accept: false, at: october(2))
        persistence.respond(to: swap, accept: true, at: october(3))

        XCTAssertEqual(swap.status, .declined)
    }

    func testDaysAreOrderedAndCounted() {
        let swap = persistence.requestSwap(in: plan, from: october(16), to: october(14), by: dad, at: october(1))

        XCTAssertEqual(swap.firstDay, october(14))
        XCTAssertEqual(swap.dayCount, 3)
        XCTAssertEqual(swap.responder, mum)
    }

    func testHistoryIsNewestFirstAndWithdrawingRemovesAPendingRequest() {
        let older = persistence.requestSwap(in: plan, from: october(9), to: october(9), by: mum, at: october(1))
        persistence.respond(to: older, accept: true, at: october(2))
        let newer = persistence.requestSwap(in: plan, from: october(16), to: october(16), by: dad, at: october(3))

        XCTAssertEqual(plan.sortedSwaps, [newer, older])

        persistence.withdraw(newer)
        persistence.withdraw(older)
        XCTAssertEqual(plan.sortedSwaps, [older], "Answered swaps stay in the history")
    }

    func testTheOtherParentIsNotifiedOfARequestOnce() {
        persistence.requestSwap(in: plan, from: october(9), to: october(10), by: mum, at: october(1, 9))

        let forDad = SwapNotifications.notices(swaps: plan.sortedSwaps, me: dad, now: october(1, 10), alreadySent: [])
        let forMum = SwapNotifications.notices(swaps: plan.sortedSwaps, me: mum, now: october(1, 10), alreadySent: [])

        XCTAssertEqual(forDad.count, 1)
        XCTAssertTrue(forDad[0].title.contains("Rita"))
        XCTAssertTrue(forDad[0].body.hasPrefix("Ana"))
        XCTAssertEqual(forMum, [])
        XCTAssertEqual(SwapNotifications.notices(swaps: plan.sortedSwaps, me: dad, now: october(1, 10),
                                                 alreadySent: [forDad[0].key]), [])
    }

    func testTheRequesterIsNotifiedOfTheAnswer() {
        let swap = persistence.requestSwap(in: plan, from: october(9), to: october(10), by: mum, at: october(1, 9))
        persistence.respond(to: swap, accept: true, at: october(1, 11))

        let forMum = SwapNotifications.notices(swaps: plan.sortedSwaps, me: mum, now: october(1, 12), alreadySent: [])

        XCTAssertEqual(forMum.count, 1)
        XCTAssertTrue(forMum[0].key.hasSuffix("-accepted"))
    }

    func testOldChangesAreNotAnnounced() {
        persistence.requestSwap(in: plan, from: october(9), to: october(10), by: mum, at: october(1))

        XCTAssertEqual(SwapNotifications.notices(swaps: plan.sortedSwaps, me: dad, now: october(4), alreadySent: []), [])
    }

    func testNotifierRemembersWhatItSent() throws {
        persistence.requestSwap(in: plan, from: october(9), to: october(10), by: mum, at: .now)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CustodySwapTests"))
        defaults.removePersistentDomain(forName: "CustodySwapTests")
        defaults.set(dad.identifier?.uuidString, forKey: "meMemberID")
        let notifier = SwapNotifier(persistence: persistence, defaults: defaults)

        XCTAssertEqual(notifier.post(center: nil).count, 1)
        XCTAssertEqual(notifier.post(center: nil).count, 0)
        defaults.removePersistentDomain(forName: "CustodySwapTests")
    }
}
