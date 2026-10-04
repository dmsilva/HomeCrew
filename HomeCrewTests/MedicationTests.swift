import CoreData
import UserNotifications
import XCTest
@testable import HomeCrew

final class MedicationTests: XCTestCase {
    private var persistence: PersistenceController!
    private var rita: Member!
    private var mum: Member!
    private var dad: Member!
    private var episode: IllnessEpisode!
    private let morning = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let family = persistence.createFamily(named: "Silva")
        rita = member("Rita", .child, in: family)
        mum = member("Ana", .adult, in: family)
        dad = member("João", .adult, in: family)
        episode = persistence.openEpisode(for: rita, at: morning)
    }

    private func member(_ name: String, _ kind: Member.Kind, in family: Family) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    private func hours(_ value: Double) -> Date { morning.addingTimeInterval(value * 3600) }

    private func benuron(every interval: Double = 6, responsible: Member? = nil, givenNow: Bool = false) -> Medication {
        var draft = MedicationDraft()
        draft.name = "  Ben-u-ron "
        draft.dose = "7,5 ml"
        draft.intervalHours = interval
        draft.responsible = responsible
        draft.givenNow = givenNow
        return persistence.addMedication(draft, to: episode, by: mum, at: morning)
    }

    // MARK: Suggestions

    func testSuggestionsMatchTheStartIgnoringCaseAndAccents() {
        XCTAssertEqual(Medication.suggestions(for: "bru"), ["Brufen"])
        XCTAssertEqual(Medication.suggestions(for: "BEN"), ["Ben-u-ron"])
        XCTAssertEqual(Medication.suggestions(for: "soro fisio"), ["Soro fisiológico"])
        XCTAssertEqual(Medication.suggestions(for: ""), Medication.suggestions)
    }

    func testSuggestionsDisappearOnceTheNameIsComplete() {
        XCTAssertEqual(Medication.suggestions(for: "brufen"), [])
    }

    // MARK: Dose as given, never calculated

    func testDoseAndIntervalAreStoredExactlyAsTyped() {
        let medication = benuron(every: 6)

        XCTAssertEqual(medication.name, "Ben-u-ron")
        XCTAssertEqual(medication.dose, "7,5 ml")
        XCTAssertEqual(medication.intervalHours, 6)
    }

    func testTheDoseDoesNotDependOnTheChildsWeight() {
        let before = benuron()
        var record = HealthRecordDraft(rita)
        record.weightKg = 30
        persistence.updateHealthRecord(of: rita, with: record)

        XCTAssertEqual(before.dose, "7,5 ml")
    }

    func testANameIsNeeded() {
        var draft = MedicationDraft()
        XCTAssertFalse(draft.isValid)
        draft.name = "Brufen"
        XCTAssertTrue(draft.isValid)
    }

    // MARK: Next dose

    func testBeforeTheFirstDoseItIsDueWithNoCountdown() {
        let medication = benuron()

        XCTAssertNil(medication.nextDoseAt)
        XCTAssertTrue(medication.isDue(at: morning))
    }

    func testGivingNowSetsTheNextDoseOneIntervalLater() {
        let medication = benuron(every: 6)
        persistence.giveDose(of: medication, by: dad, at: hours(1))

        XCTAssertEqual(medication.nextDoseAt, hours(7))
        XCTAssertFalse(medication.isDue(at: hours(6.9)))
        XCTAssertTrue(medication.isDue(at: hours(7)))
        XCTAssertEqual(medication.lastDose?.givenBy, dad)
    }

    func testTheNextDoseFollowsTheLatestDose() {
        let medication = benuron(every: 8)
        persistence.giveDose(of: medication, by: mum, at: hours(0))
        persistence.giveDose(of: medication, by: mum, at: hours(5))

        XCTAssertEqual(medication.nextDoseAt, hours(13))
        XCTAssertEqual(medication.sortedDoses.map(\.givenAt), [hours(5), hours(0)])
    }

    func testDeletingAMistakenDoseRestoresTheCountdown() {
        let medication = benuron(every: 8)
        persistence.giveDose(of: medication, by: mum, at: hours(0))
        let mistake = persistence.giveDose(of: medication, by: mum, at: hours(1))
        persistence.delete(mistake)

        XCTAssertEqual(medication.nextDoseAt, hours(8))
    }

    func testGivenNowWhenAddingRecordsTheFirstDose() {
        let medication = benuron(every: 6, givenNow: true)

        XCTAssertEqual(medication.sortedDoses.count, 1)
        XCTAssertEqual(medication.lastDose?.givenBy, mum)
        XCTAssertEqual(medication.nextDoseAt, hours(6))
    }

    func testStoppedOrEndedMedicationIsNoLongerDue() {
        let stopped = benuron(givenNow: true)
        persistence.stop(stopped, at: hours(2))
        XCTAssertFalse(stopped.isActive)
        XCTAssertNil(stopped.nextDoseAt)

        let other = benuron(givenNow: true)
        persistence.end(episode, at: hours(3))
        XCTAssertFalse(other.isActive)
        XCTAssertFalse(other.isDue(at: hours(100)))
    }

    func testEditingKeepsTheDoses() {
        let medication = benuron(every: 6, givenNow: true)
        var draft = MedicationDraft(medication)
        draft.intervalHours = 8
        persistence.update(medication, with: draft)

        XCTAssertEqual(medication.sortedDoses.count, 1)
        XCTAssertEqual(medication.nextDoseAt, hours(8))
    }

    func testFindsAMedicationByIdentifier() throws {
        let medication = benuron()
        let id = try XCTUnwrap(medication.identifier)

        XCTAssertEqual(persistence.medication(withIdentifier: id), medication)
        XCTAssertNil(persistence.medication(withIdentifier: UUID()))
    }

    func testDeletingThePersonDeletesTheirMedication() throws {
        let medication = benuron(givenNow: true)
        XCTAssertNotNil(medication.lastDose)
        persistence.delete(rita)

        XCTAssertEqual(try persistence.viewContext.count(for: Medication.all()), 0)
        XCTAssertEqual(try persistence.viewContext.count(for: NSFetchRequest<DoseGiven>(entityName: "DoseGiven")), 0)
    }

    // MARK: Reminders

    func testReminderIsPlannedForTheNextDose() throws {
        let medication = benuron(every: 6, givenNow: true)

        let plan = DoseReminders.plan(medications: [medication], me: mum, now: hours(1))

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.fireAt, hours(6))
        XCTAssertEqual(plan.first?.title, "Ben-u-ron · Rita")
        XCTAssertEqual(plan.first?.body, "7,5 ml")
        XCTAssertEqual(plan.first?.identifier, "dose-" + (try XCTUnwrap(medication.identifier)).uuidString)
    }

    func testOnlyTheResponsiblePersonIsReminded() {
        let medication = benuron(every: 6, responsible: dad, givenNow: true)

        XCTAssertEqual(DoseReminders.plan(medications: [medication], me: dad, now: hours(1)).count, 1)
        XCTAssertEqual(DoseReminders.plan(medications: [medication], me: mum, now: hours(1)).count, 0)
        XCTAssertEqual(DoseReminders.plan(medications: [medication], me: nil, now: hours(1)).count, 1)
    }

    func testNoReminderBeforeTheFirstDosePastDueOrWhenStopped() {
        let notGiven = benuron()
        let overdue = benuron(every: 6, givenNow: true)
        let stopped = benuron(every: 6, givenNow: true)
        persistence.stop(stopped, at: hours(1))

        XCTAssertEqual(DoseReminders.plan(medications: [notGiven, overdue, stopped], me: mum, now: hours(7)), [])
    }

    @MainActor
    func testRefreshReplacesStaleRemindersAndKeepsOthers() async throws {
        let medication = benuron(every: 6, givenNow: true)
        let scheduler = FakeScheduler()
        scheduler.pending = ["dose-old", "something-else"]
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MedicationTests"))
        defaults.removePersistentDomain(forName: "MedicationTests")
        let center = DoseReminderCenter(persistence: persistence, scheduler: scheduler, defaults: defaults)

        await center.refresh(now: hours(1))

        XCTAssertEqual(scheduler.removed, ["dose-old"])
        XCTAssertEqual(scheduler.added.map(\.identifier), ["dose-" + (try XCTUnwrap(medication.identifier)).uuidString])
        let trigger = try XCTUnwrap(scheduler.added.first?.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 5 * 3600, accuracy: 1)
        XCTAssertEqual(scheduler.added.first?.content.categoryIdentifier, "dose")
    }

    @MainActor
    func testGiveNowFromTheNotificationRecordsADoseByMe() throws {
        let medication = benuron(every: 6)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MedicationTests"))
        defaults.set(dad.identifier?.uuidString, forKey: "meMemberID")
        let center = DoseReminderCenter(persistence: persistence, scheduler: FakeScheduler(), defaults: defaults)

        center.giveNow(medicationID: try XCTUnwrap(medication.identifier), at: hours(2))

        XCTAssertEqual(medication.lastDose?.givenBy, dad)
        XCTAssertEqual(medication.nextDoseAt, hours(8))
        defaults.removePersistentDomain(forName: "MedicationTests")
    }
}

private final class FakeScheduler: NotificationScheduling {
    var pending: [String] = []
    var added: [UNNotificationRequest] = []
    var removed: [String] = []

    func pendingRequestIdentifiers() async -> [String] { pending }

    func add(_ request: UNNotificationRequest) async throws { added.append(request) }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { removed += identifiers }
}
