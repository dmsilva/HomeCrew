import CloudKit
import CoreData
import XCTest
@testable import HomeCrew

final class PersistenceTests: XCTestCase {
    private var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    func testCreatedFamilyCanBeFetched() throws {
        persistence.createFamily(named: "Silva")

        let families = try persistence.viewContext.fetch(Family.all())

        XCTAssertEqual(families.map(\.name), ["Silva"])
        XCTAssertNotNil(families.first?.identifier)
        XCTAssertNotNil(families.first?.createdAt)
    }

    func testRenamingAFamilyIsSaved() throws {
        let family = persistence.createFamily(named: "Silva")
        family.name = "Silva Martins"
        persistence.save()

        let other = persistence.container.newBackgroundContext()
        let names = try other.performAndWait { try other.fetch(Family.all()).map(\.name) }

        XCTAssertEqual(names, ["Silva Martins"])
    }

    func testFamiliesAreListedOldestFirst() throws {
        let first = persistence.createFamily(named: "A")
        let second = persistence.createFamily(named: "B")
        first.createdAt = Date(timeIntervalSince1970: 200)
        second.createdAt = Date(timeIntervalSince1970: 100)
        persistence.save()

        let names = try persistence.viewContext.fetch(Family.all()).map(\.name)

        XCTAssertEqual(names, ["B", "A"])
    }

    /// CloudKit refuses to mirror a model with required attributes, unique constraints
    /// or one-way relationships; catching that here is cheaper than on a device.
    func testModelIsCompatibleWithCloudKit() {
        for entity in HomeCrewModel.shared.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") has unique constraints")
            for attribute in entity.attributesByName.values {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name ?? "?").\(attribute.name) must be optional or have a default"
                )
            }
            for relationship in entity.relationshipsByName.values {
                XCTAssertTrue(relationship.isOptional, "\(entity.name ?? "?").\(relationship.name) must be optional")
                XCTAssertNotNil(relationship.inverseRelationship, "\(entity.name ?? "?").\(relationship.name) needs an inverse")
            }
        }
    }

    func testCloudKitStoresArePrivateAndSharedWithHistoryTracking() {
        let descriptions = PersistenceController.cloudKitStoreDescriptions(in: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(descriptions.compactMap { $0.cloudKitContainerOptions?.databaseScope }, [.private, .shared])
        XCTAssertEqual(Set(descriptions.compactMap(\.url)).count, 2, "Each scope needs its own file")
        for description in descriptions {
            XCTAssertEqual(description.cloudKitContainerOptions?.containerIdentifier, "iCloud.com.dmsilva.homecrew")
            XCTAssertEqual(description.options[NSPersistentHistoryTrackingKey] as? Bool, true)
            XCTAssertEqual(description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? Bool, true)
        }
    }
}

final class FamilyMembersTests: XCTestCase {
    private var persistence: PersistenceController!
    private var family: Family!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        family = persistence.createFamily(named: "Silva")
    }

    private func draft(_ name: String, _ kind: Member.Kind = .child, color: Int16 = 0) -> MemberDraft {
        var draft = MemberDraft()
        draft.name = name
        draft.kind = kind
        draft.colorIndex = color
        return draft
    }

    func testAddedMemberBelongsToTheFamily() {
        let member = persistence.addMember(draft("  Rita ", .child, color: 2), to: family)

        XCTAssertEqual(member.name, "Rita")
        XCTAssertEqual(member.kind, .child)
        XCTAssertEqual(member.colorIndex, 2)
        XCTAssertNotNil(member.identifier)
        XCTAssertEqual(family.sortedMembers, [member])
    }

    func testAdultsAreListedBeforeChildren() {
        let child = persistence.addMember(draft("Rita", .child), to: family)
        let adult = persistence.addMember(draft("Daniel", .adult), to: family)

        XCTAssertEqual(family.sortedMembers, [adult, child])
    }

    func testEditingAMemberIsSaved() {
        let member = persistence.addMember(draft("Rita"), to: family)

        persistence.update(member, with: draft("Rita Silva", .child, color: 3))

        XCTAssertEqual(member.name, "Rita Silva")
        XCTAssertEqual(member.colorIndex, 3)
        XCTAssertFalse(persistence.viewContext.hasChanges)
    }

    func testRemovingAMemberDeletesIt() throws {
        let member = persistence.addMember(draft("Rita"), to: family)

        persistence.delete(member)

        XCTAssertTrue(family.sortedMembers.isEmpty)
        let request = NSFetchRequest<Member>(entityName: "Member")
        XCTAssertEqual(try persistence.viewContext.count(for: request), 0)
    }

    func testDeletingAFamilyRemovesItsMembers() throws {
        persistence.addMember(draft("Rita"), to: family)

        persistence.viewContext.delete(family)
        persistence.save()

        let request = NSFetchRequest<Member>(entityName: "Member")
        XCTAssertEqual(try persistence.viewContext.count(for: request), 0)
    }

    func testNewMembersGetTheFirstUnusedColour() {
        persistence.addMember(draft("A", color: 0), to: family)
        persistence.addMember(draft("B", color: 2), to: family)

        XCTAssertEqual(family.nextColorIndex, 1)
    }

    func testColoursCycleOnceAllAreTaken() {
        for index in 0..<Theme.Palette.members.count {
            persistence.addMember(draft("M\(index)", color: Int16(index)), to: family)
        }

        XCTAssertEqual(family.nextColorIndex, 0)
    }

    func testAgeCountsWholeYears() {
        let member = persistence.addMember(draft("Rita"), to: family)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        member.birthDate = calendar.date(from: DateComponents(year: 2018, month: 10, day: 5))

        let dayBefore = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let birthday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!

        XCTAssertEqual(member.age(on: dayBefore, calendar: calendar), 7)
        XCTAssertEqual(member.age(on: birthday, calendar: calendar), 8)
    }

    func testRenamingIgnoresBlankNames() {
        persistence.rename(family, to: "   ")
        XCTAssertEqual(family.name, "Silva")

        persistence.rename(family, to: " Silva Martins ")
        XCTAssertEqual(family.name, "Silva Martins")
    }

    func testMemberDraftNeedsAName() {
        XCTAssertFalse(draft("  ").isValid)
        XCTAssertTrue(draft("Rita").isValid)
    }
}
