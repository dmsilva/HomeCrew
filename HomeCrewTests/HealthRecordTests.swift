import XCTest
@testable import HomeCrew

final class HealthRecordTests: XCTestCase {
    private var persistence: PersistenceController!
    private var rita: Member!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let family = persistence.createFamily(named: "Silva")
        var draft = MemberDraft()
        draft.name = "Rita"
        rita = persistence.addMember(draft, to: family)
    }

    private func record(_ change: (inout HealthRecordDraft) -> Void) {
        var draft = HealthRecordDraft(rita)
        change(&draft)
        persistence.updateHealthRecord(of: rita, with: draft)
    }

    func testAllergiesSplitOnCommasSemicolonsAndLines() {
        record { $0.allergies = " Amendoim, penicilina;\nPó  ,, " }

        XCTAssertEqual(rita.allergyList, ["Amendoim", "penicilina", "Pó"])
        XCTAssertTrue(rita.hasAllergies)
    }

    func testNoAllergiesByDefault() {
        XCTAssertEqual(rita.allergyList, [])
        XCTAssertFalse(rita.hasAllergies)
    }

    func testRecordIsSavedAndReadBack() {
        record {
            $0.weightKg = 24.5
            $0.chronicConditions = "Asma"
            $0.usualMedication = "Ventilan SOS"
            $0.pediatricianName = "Dra. Costa"
            $0.pediatricianPhone = "+351 912 345 678"
        }

        let readBack = HealthRecordDraft(rita)
        XCTAssertEqual(readBack.weightKg, 24.5)
        XCTAssertEqual(readBack.chronicConditions, "Asma")
        XCTAssertEqual(readBack.usualMedication, "Ventilan SOS")
        XCTAssertEqual(readBack.pediatricianName, "Dra. Costa")
        XCTAssertNotNil(rita.weightUpdatedAt)
        XCTAssertFalse(persistence.viewContext.hasChanges)
    }

    func testWeightDateOnlyMovesWhenTheWeightChanges() throws {
        record { $0.weightKg = 24.5 }
        let first = try XCTUnwrap(rita.weightUpdatedAt)

        record { $0.allergies = "Pó" }

        XCTAssertEqual(rita.weightUpdatedAt, first)
    }

    func testCallLinkKeepsOnlyDiallableCharacters() {
        record { $0.pediatricianPhone = "+351 (21) 123-4567" }
        XCTAssertEqual(rita.pediatricianCallURL?.absoluteString, "tel:+351211234567")

        record { $0.pediatricianPhone = "n/a" }
        XCTAssertNil(rita.pediatricianCallURL)
    }
}
