import CloudKit
import CoreData
import XCTest
@testable import HomeCrew

final class RolesTests: XCTestCase {
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

    private func invite(_ name: String, as role: Role, children: [Member] = [], weekdays: Set<Int> = []) -> Member {
        var draft = InviteDraft()
        draft.name = name
        draft.role = role
        draft.children = Set(children.map(\.objectID))
        draft.weekdays = weekdays
        return persistence.addInvitee(draft, to: family)
    }

    @discardableResult
    private func activity(_ title: String, for child: Member, weekdays: Set<Int>) -> Activity {
        var draft = ActivityDraft()
        draft.title = title
        draft.child = child
        draft.weekdays = weekdays
        draft.startMinutes = 17 * 60
        draft.startDate = october(1)
        return persistence.addActivity(draft, to: family)
    }

    func testAdultsWithoutARoleAreParents() {
        XCTAssertEqual(mum.role, .parent)
        XCTAssertEqual(AccessPolicy(for: mum), AccessPolicy(role: .parent, children: nil, weekdays: nil, me: mum.objectID))
    }

    func testInvitingAddsAnAdultWithTheRole() {
        let granny = invite("Avó", as: .carer, children: [rita], weekdays: [3])

        XCTAssertEqual(granny.kind, .adult)
        XCTAssertEqual(granny.role, .carer)
        XCTAssertEqual(granny.caredChildrenList, [rita])
        XCTAssertEqual(granny.careWeekdays, [3])
        XCTAssertEqual(rita.carers?.count, 1)
    }

    func testChangingRoleLaterClearsCarerOnlySettings() {
        let granny = invite("Avó", as: .carer, children: [rita], weekdays: [3])

        persistence.setRole(.guest, children: [rita.objectID], weekdays: [3], for: granny)

        XCTAssertEqual(granny.role, .guest)
        XCTAssertEqual(granny.caredChildrenList, [])
        XCTAssertEqual(granny.careWeekdays, [])
    }

    func testOnlyChildrenCanBeCaredFor() {
        let granny = invite("Avó", as: .carer, children: [rita, mum])
        XCTAssertEqual(granny.caredChildrenList, [rita])
    }

    func testTabsPerRole() {
        XCTAssertEqual(AccessPolicy(for: mum).tabs, AppTab.allCases)
        XCTAssertEqual(AccessPolicy(for: invite("Avó", as: .carer)).tabs, [.today, .agenda, .health])
        XCTAssertEqual(AccessPolicy(for: invite("Vizinha", as: .guest)).tabs, [.agenda])
        XCTAssertEqual(AccessPolicy.unidentified.tabs, [.agenda])
    }

    func testOnlyGuestsCannotEdit() {
        XCTAssertTrue(AccessPolicy(for: mum).canEdit)
        XCTAssertTrue(AccessPolicy(for: invite("Avó", as: .carer)).canEdit)
        XCTAssertFalse(AccessPolicy(for: invite("Vizinha", as: .guest)).canEdit)
        XCTAssertTrue(AccessPolicy(for: mum).canManageFamily)
        XCTAssertFalse(AccessPolicy(for: invite("Ama", as: .carer)).canManageFamily)
    }

    func testCarerSeesOnlyTheirChildrenOnTheirDays() {
        let football = activity("Futebol", for: rita, weekdays: [3, 4])
        activity("Natação", for: tomas, weekdays: [3])
        let granny = invite("Avó", as: .carer, children: [rita], weekdays: [3])
        let access = AccessPolicy(for: granny)

        let tuesday = TodayDigest.build(day: october(6), activities: [football] + Array(tomas.activities as! Set<Activity>),
                                        chores: [], access: access, calendar: calendar)
        let wednesday = TodayDigest.build(day: october(7), activities: [football], chores: [], access: access, calendar: calendar)

        XCTAssertEqual(tuesday.activities.map(\.activity), [football])
        XCTAssertEqual(wednesday.activities, [])
    }

    func testCarerWithNoDaysSeesEveryDay() {
        let football = activity("Futebol", for: rita, weekdays: [4])
        let access = AccessPolicy(for: invite("Ama", as: .carer, children: [rita]))

        XCTAssertEqual(TodayDigest.build(day: october(7), activities: [football], chores: [], access: access, calendar: calendar)
            .activities.map(\.activity), [football])
    }

    func testCarerSeesChoresOfTheirChildrenAndAdultsButNotOtherChildren() {
        let granny = invite("Avó", as: .carer, children: [rita])
        let chores = [("Mochila", rita), ("Quarto", tomas), ("Loiça", mum), ("Regar", nil)].map { title, assignee -> Chore in
            var draft = ChoreDraft()
            draft.title = title
            draft.assignee = assignee
            draft.startDate = october(1)
            return persistence.addChore(draft, to: family)
        }

        let shown = AccessPolicy(for: granny).filter(chores, on: october(6), calendar: calendar)

        XCTAssertEqual(shown.map(\.title), ["Mochila", "Loiça", "Regar"])
    }

    func testCarerHealthTabShowsTheirChildrenAndThemselves() {
        let granny = invite("Avó", as: .carer, children: [tomas])

        XCTAssertEqual(AccessPolicy(for: granny).visibleMembers(of: family), [tomas, granny].sorted {
            family.sortedMembers.firstIndex(of: $0)! < family.sortedMembers.firstIndex(of: $1)!
        })
        XCTAssertEqual(AccessPolicy(for: mum).visibleMembers(of: family), family.sortedMembers)
    }

    func testIllnessAlertsFollowTheCarersChildren() {
        let granny = invite("Avó", as: .carer, children: [rita])
        let forRita = TodayAlert(id: "a", systemImage: "thermometer.medium", title: "38°", member: rita)
        let forTomas = TodayAlert(id: "b", systemImage: "thermometer.medium", title: "39°", member: tomas)

        let digest = TodayDigest.build(day: october(6), activities: [], chores: [], alerts: [forRita, forTomas],
                                       access: AccessPolicy(for: granny), calendar: calendar)

        XCTAssertEqual(digest.alerts, [forRita])
    }

    func testGuestsAreReadOnlyOnTheShare() {
        XCTAssertEqual(Role.guest.sharePermission, .readOnly)
        XCTAssertEqual(Role.carer.sharePermission, .readWrite)
        XCTAssertEqual(Role.parent.sharePermission, .readWrite)
    }

    func testLinkingAnAccountAndFindingTheMemberById() throws {
        persistence.link(mum, toAccount: "_abc123")

        XCTAssertEqual(mum.accountID, "_abc123")
        XCTAssertEqual(family.member(withID: try XCTUnwrap(mum.identifier).uuidString), mum)
        XCTAssertNil(family.member(withID: ""))
    }

    func testAFamilyCreatedHereIsNotJoined() {
        XCTAssertFalse(persistence.isJoined(family))
    }
}
