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
