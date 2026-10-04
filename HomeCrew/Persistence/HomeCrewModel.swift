import CoreData

/// A family: the unit that is shared between iCloud accounts.
@objc(Family)
final class Family: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?

    static func all() -> NSFetchRequest<Family> {
        let request = NSFetchRequest<Family>(entityName: "Family")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }
}

/// The Core Data model, built in code so it stays reviewable in diffs.
/// CloudKit mirroring requires every attribute to be optional or defaulted,
/// no unique constraints, and every relationship to be optional with an inverse.
enum HomeCrewModel {
    /// One instance for the whole process: Core Data warns when two models claim the same classes.
    static let shared: NSManagedObjectModel = make()

    private static func make() -> NSManagedObjectModel {
        let family = NSEntityDescription()
        family.name = "Family"
        family.managedObjectClassName = NSStringFromClass(Family.self)
        family.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]

        let model = NSManagedObjectModel()
        model.entities = [family]
        return model
    }

    private static func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }
}
