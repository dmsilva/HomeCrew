import CoreData
import XCTest
@testable import HomeCrew

final class TodayDigestTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var mum: Member!
    private var dad: Member!
    private var rita: Member!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    /// Tuesday 6 Oct 2026, midday.
    private var tuesday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))! }

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        family = persistence.createFamily(named: "Silva")
        mum = member("Ana", .adult)
        dad = member("Daniel", .adult)
        rita = member("Rita", .child)
    }

    private func member(_ name: String, _ kind: Member.Kind) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    private func activity(_ title: String, at hour: Int, weekdays: Set<Int> = [3], dropOff: Member? = nil, pickUp: Member? = nil) -> Activity {
        var draft = ActivityDraft()
        draft.title = title
        draft.child = rita
        draft.weekdays = weekdays
        draft.startMinutes = hour * 60
        draft.startDate = calendar.date(byAdding: .day, value: -7, to: tuesday)!
        draft.dropOff = dropOff
        draft.pickUp = pickUp
        return persistence.addActivity(draft, to: family)
    }

    private func chore(_ title: String, for assignee: Member?, _ recurrence: Recurrence = .daily) -> Chore {
        var draft = ChoreDraft()
        draft.title = title
        draft.assignee = assignee
        draft.recurrence = recurrence
        draft.startDate = calendar.date(byAdding: .day, value: -7, to: tuesday)!
        return persistence.addChore(draft, to: family)
    }

    func testShowsTodaysActivitiesInTimeOrderAndSkipsOtherDays() {
        let late = activity("Natação", at: 19)
        let early = activity("Futebol", at: 17)
        let wednesday = activity("Música", at: 18, weekdays: [4])

        let digest = TodayDigest.build(day: tuesday, activities: [late, wednesday, early], chores: [], calendar: calendar)

        XCTAssertEqual(digest.activities.map(\.activity), [early, late])
    }

    func testShowsOnlyChoresDueTodayWithDoneOnesLast() {
        let bed = chore("Cama", for: rita)
        let bins = chore("Lixo", for: dad)
        let mondays = chore("Plantas", for: mum, .weekly([2]))
        persistence.toggleDone(bed, on: tuesday, calendar: calendar)

        let digest = TodayDigest.build(day: tuesday, activities: [], chores: [bed, bins, mondays], calendar: calendar)

        XCTAssertEqual(digest.chores, [bins, bed])
    }

    func testOnlyMineKeepsWhatIDriveAndMyChores() {
        let football = activity("Futebol", at: 17, dropOff: dad, pickUp: mum)
        let swimming = activity("Natação", at: 19, dropOff: mum, pickUp: mum)
        let dadsChore = chore("Lixo", for: dad)
        let mumsChore = chore("Roupa", for: mum)

        let digest = TodayDigest.build(
            day: tuesday,
            activities: [football, swimming],
            chores: [dadsChore, mumsChore],
            me: dad,
            calendar: calendar
        )

        XCTAssertEqual(digest.activities.map(\.activity), [football])
        XCTAssertEqual(digest.chores, [dadsChore])
    }

    func testOnlyMineFollowsTheDaysChangeNotTheRule() {
        let football = activity("Futebol", at: 17, dropOff: mum, pickUp: mum)
        persistence.overrideDrivers(football, on: tuesday, dropOff: dad, pickUp: nil, calendar: calendar)

        let digest = TodayDigest.build(day: tuesday, activities: [football], chores: [], me: dad, calendar: calendar)

        XCTAssertEqual(digest.activities.map(\.activity), [football])
    }

    func testAlertsComeThroughAndAreFilteredByPerson() {
        let forRita = TodayAlert(id: "a", systemImage: "thermometer.medium", title: "38,5°", member: rita)
        let forEveryone = TodayAlert(id: "b", systemImage: "bell", title: "Aviso", member: nil)

        let all = TodayDigest.build(day: tuesday, activities: [], chores: [], alerts: [forRita, forEveryone], calendar: calendar)
        let mine = TodayDigest.build(day: tuesday, activities: [], chores: [], alerts: [forRita, forEveryone], me: dad, calendar: calendar)

        XCTAssertEqual(all.alerts, [forRita, forEveryone])
        XCTAssertEqual(mine.alerts, [forEveryone])
        XCTAssertFalse(all.isEmpty)
    }

    func testCalendarEventsMixWithActivitiesByTimeAllDayFirst() {
        let football = activity("Futebol", at: 17)
        let dentist = ExternalEvent(
            id: "d", title: "Dentista", start: at(hour: 9), end: at(hour: 10), isAllDay: false, color: nil
        )
        let dinner = ExternalEvent(
            id: "j", title: "Jantar", start: at(hour: 20), end: at(hour: 22), isAllDay: false, color: nil
        )
        let holiday = ExternalEvent(
            id: "h", title: "Feriado", start: at(hour: 0), end: at(hour: 23), isAllDay: true, color: nil
        )

        let digest = TodayDigest.build(
            day: tuesday, activities: [football], chores: [], externalEvents: [dinner, dentist, holiday], calendar: calendar
        )

        XCTAssertEqual(digest.agenda.map(\.id), ["external-h", "external-d", "activity-\(digest.activities[0].id)", "external-j"])
    }

    func testOnlyMineKeepsCalendarEvents() {
        let event = ExternalEvent(id: "d", title: "Dentista", start: at(hour: 9), end: at(hour: 10), isAllDay: false, color: nil)

        let digest = TodayDigest.build(day: tuesday, activities: [], chores: [], externalEvents: [event], me: dad, calendar: calendar)

        XCTAssertEqual(digest.externalEvents, [event])
        XCTAssertFalse(digest.isEmpty)
    }

    private func at(hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tuesday)!
    }

    func testEmptyDay() {
        XCTAssertTrue(TodayDigest.build(day: tuesday, activities: [], chores: [], calendar: calendar).isEmpty)
    }
}
