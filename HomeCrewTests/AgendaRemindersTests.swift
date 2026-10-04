import CoreData
import XCTest
@testable import HomeCrew

final class AgendaRemindersTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!
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
        mum = member("Ana", .adult)
        dad = member("João", .adult)
    }

    private func member(_ name: String, _ kind: Member.Kind) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    /// 6 Oct 2026 is a Tuesday (weekday 3).
    private func october(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func football(dropOff: Member?, pickUp: Member? = nil) -> Activity {
        var draft = ActivityDraft()
        draft.title = "Futebol"
        draft.child = rita
        draft.weekdays = [3]
        draft.startMinutes = 18 * 60
        draft.location = "Estádio"
        draft.dropOff = dropOff
        draft.pickUp = pickUp
        draft.startDate = october(1)
        return persistence.addActivity(draft, to: family)
    }

    private func plan(_ activities: [Activity], chores: [Chore] = [], me: Member?, settings: AgendaNotificationSettings = .init(),
                      now: Date) -> [PlannedAgendaNotice] {
        AgendaReminders.plan(activities: activities, chores: chores, me: me, access: .full, settings: settings, now: now, calendar: calendar)
    }

    func testReminderThirtyMinutesBeforeOnlyForWhoeverTakes() {
        let activity = football(dropOff: mum, pickUp: dad)
        var settings = AgendaNotificationSettings()
        settings.dailySummary = false

        let forMum = plan([activity], me: mum, settings: settings, now: october(6, 9))
        let forDad = plan([activity], me: dad, settings: settings, now: october(6, 9))

        XCTAssertEqual(forMum.count, 1)
        XCTAssertEqual(forMum.first?.fireAt, october(6, 17, 30))
        XCTAssertEqual(forMum.first?.title, "Futebol · Rita")
        XCTAssertTrue(forMum.first?.body.contains("Estádio") ?? false)
        XCTAssertEqual(forDad, [])
    }

    func testTheReminderFollowsTheDaysChangeAndCancellations() {
        let activity = football(dropOff: mum)
        persistence.overrideDrivers(activity, on: october(6), dropOff: dad, pickUp: nil, calendar: calendar)
        var settings = AgendaNotificationSettings()
        settings.dailySummary = false

        XCTAssertEqual(plan([activity], me: mum, settings: settings, now: october(6, 9)), [])
        XCTAssertEqual(plan([activity], me: dad, settings: settings, now: october(6, 9)).count, 1)

        persistence.setCancelled(true, activity, on: october(6), calendar: calendar)
        XCTAssertEqual(plan([activity], me: dad, settings: settings, now: october(6, 9)), [])
    }

    func testNoReminderOncePassed() {
        let activity = football(dropOff: mum)
        var settings = AgendaNotificationSettings()
        settings.dailySummary = false
        XCTAssertEqual(plan([activity], me: mum, settings: settings, now: october(6, 17, 45)), [])
    }

    func testMorningSummaryAtTheChosenTime() {
        let activity = football(dropOff: mum)
        var settings = AgendaNotificationSettings()
        settings.beforeActivity = false
        settings.summaryMinutes = 8 * 60

        let notices = plan([activity], me: mum, settings: settings, now: october(6, 6))

        XCTAssertEqual(notices.count, 1, "Only Tuesday has something on")
        XCTAssertEqual(notices.first?.fireAt, october(6, 8))
        XCTAssertTrue(notices.first?.body.contains("Futebol") ?? false)
    }

    func testTurningEverythingOffPlansNothing() {
        let activity = football(dropOff: mum)
        var settings = AgendaNotificationSettings()
        settings.beforeActivity = false
        settings.dailySummary = false
        XCTAssertEqual(plan([activity], me: mum, settings: settings, now: october(6, 6)), [])
    }

    func testNothingBeforeThisIPhoneKnowsWhoUsesIt() {
        XCTAssertEqual(plan([football(dropOff: mum)], me: nil, now: october(6, 6)), [])
    }

    func testSettingsDefaultsAndReading() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AgendaRemindersTests"))
        defaults.removePersistentDomain(forName: "AgendaRemindersTests")
        XCTAssertEqual(AgendaNotificationSettings(defaults), AgendaNotificationSettings())
        XCTAssertEqual(AgendaNotificationSettings().summaryMinutes, 7 * 60 + 30)

        defaults.set(false, forKey: AgendaNotificationSettings.changesKey)
        defaults.set(9 * 60, forKey: AgendaNotificationSettings.summaryMinutesKey)
        let read = AgendaNotificationSettings(defaults)
        XCTAssertFalse(read.changes)
        XCTAssertEqual(read.summaryMinutes, 9 * 60)
        defaults.removePersistentDomain(forName: "AgendaRemindersTests")
    }

    func testChangesThatTouchMeAreAnnouncedOnce() {
        let activity = football(dropOff: mum)
        persistence.overrideDrivers(activity, on: october(6), dropOff: dad, pickUp: nil, calendar: calendar)
        let exception = activity.exception(on: october(6), calendar: calendar)!
        var choreDraft = ChoreDraft()
        choreDraft.title = "Mochila"
        choreDraft.assignee = mum
        let chore = persistence.addChore(choreDraft, to: family)

        let notice = AgendaReminders.changeNotice(changed: [exception, activity, chore], me: mum, now: october(6, 9))

        XCTAssertEqual(notice?.body, "Futebol, Mochila")
        XCTAssertEqual(notice?.fireAt, october(6, 9))
    }

    func testChangesForOthersAreNotAnnounced() {
        var choreDraft = ChoreDraft()
        choreDraft.title = "Loiça"
        choreDraft.assignee = dad
        let chore = persistence.addChore(choreDraft, to: family)

        XCTAssertNil(AgendaReminders.changeNotice(changed: [chore], me: mum, now: october(6, 9)))
        XCTAssertNil(AgendaReminders.changeNotice(changed: [chore], me: nil, now: october(6, 9)))
    }
}
