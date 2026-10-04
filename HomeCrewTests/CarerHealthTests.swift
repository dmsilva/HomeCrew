import CoreData
import XCTest
@testable import HomeCrew

final class CarerHealthTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!
    private var rita: Member!
    private var tomas: Member!
    private var mum: Member!
    private var granny: Member!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        family = persistence.createFamily(named: "Silva")
        rita = member("Rita", .child)
        tomas = member("Tomás", .child)
        mum = member("Ana", .adult)
        var invite = InviteDraft()
        invite.name = "Avó"
        invite.role = .carer
        invite.children = [rita.objectID]
        granny = persistence.addInvitee(invite, to: family)
    }

    private func member(_ name: String, _ kind: Member.Kind) -> Member {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        return persistence.addMember(draft, to: family)
    }

    func testCarersRecordButDoNotManageEpisodesOrSeeTheFullRecord() {
        let carer = AccessPolicy(for: granny)
        XCTAssertTrue(carer.canEdit)
        XCTAssertFalse(carer.canManageEpisode)
        XCTAssertFalse(carer.canSeeFullHealthRecord)

        let parent = AccessPolicy(for: mum)
        XCTAssertTrue(parent.canManageEpisode)
        XCTAssertTrue(parent.canSeeFullHealthRecord)
    }

    func testCarerOnlySeesTheirChildrenOnTheHealthTab() {
        let visible = AccessPolicy(for: granny).visibleMembers(of: family)
        XCTAssertTrue(visible.contains(rita))
        XCTAssertFalse(visible.contains(tomas))
    }

    func testEachTemperatureKeepsWhoRecordedIt() {
        let episode = persistence.openEpisode(for: rita)
        let byGranny = persistence.recordTemperature(38.4, in: episode, by: granny)
        let byMum = persistence.recordTemperature(37.9, in: episode, by: mum)

        XCTAssertEqual(byGranny.recordedBy, granny)
        XCTAssertEqual(byMum.recordedBy, mum)
    }

    func testEachDoseKeepsWhoGaveIt() {
        let episode = persistence.openEpisode(for: rita)
        var draft = MedicationDraft()
        draft.name = "Ben-u-ron"
        let medication = persistence.addMedication(draft, to: episode, by: mum)
        persistence.giveDose(of: medication, by: granny)

        XCTAssertEqual(medication.lastDose?.givenBy, granny)
    }

    func testRemovingTheCarerKeepsTheirRecordsWithoutAName() {
        let episode = persistence.openEpisode(for: rita)
        let reading = persistence.recordTemperature(38.4, in: episode, by: granny)
        persistence.delete(granny)

        XCTAssertNil(reading.recordedBy)
        XCTAssertEqual(episode.sortedReadings.count, 1)
    }
}
