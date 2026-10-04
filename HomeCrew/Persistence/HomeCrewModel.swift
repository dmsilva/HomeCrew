import CoreData
import UIKit

/// A family: the unit that is shared between iCloud accounts.
@objc(Family)
final class Family: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var members: NSSet?
    @NSManaged var chores: NSSet?

    static func all() -> NSFetchRequest<Family> {
        let request = NSFetchRequest<Family>(entityName: "Family")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    /// Adults first, then children, each in the order they were added.
    var sortedMembers: [Member] {
        let all = (members as? Set<Member>) ?? []
        return all.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .adult }
            return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }
    }

    /// The first palette colour nobody in the family uses yet, cycling once all are taken.
    var nextColorIndex: Int16 {
        let used = Set(sortedMembers.map(\.colorIndex))
        let paletteSize = Int16(Theme.Palette.members.count)
        return (0..<paletteSize).first { !used.contains($0) } ?? Int16(sortedMembers.count) % paletteSize
    }
}

/// An adult (who will have their own account) or a child (a profile managed by the parents).
@objc(Member)
final class Member: NSManagedObject {
    enum Kind: String, CaseIterable {
        case adult, child
    }

    @NSManaged var identifier: UUID?
    @NSManaged var name: String?
    @NSManaged var kindValue: String?
    @NSManaged var colorIndex: Int16
    @NSManaged var birthDate: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var family: Family?
    @NSManaged var assignedChores: NSSet?
    @NSManaged var completions: NSSet?

    var kind: Kind {
        get { Kind(rawValue: kindValue ?? "") ?? .adult }
        set { kindValue = newValue.rawValue }
    }

    /// The member's colour pair, used wherever the app marks something as theirs.
    var palette: (foreground: UIColor, soft: UIColor) {
        let colors = Theme.Palette.members
        return colors[Int(colorIndex).clamped(to: 0...(colors.count - 1))]
    }

    var initial: String {
        name?.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    func age(on date: Date, calendar: Calendar = .current) -> Int? {
        guard let birthDate else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: date).year
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// The Core Data model, built in code so it stays reviewable in diffs.
/// CloudKit mirroring requires every attribute to be optional or defaulted,
/// no unique constraints, and every relationship to be optional with an inverse.
enum HomeCrewModel {
    /// One instance for the whole process: Core Data warns when two models claim the same classes.
    static let shared: NSManagedObjectModel = make()

    private static func make() -> NSManagedObjectModel {
        let family = entity("Family", Family.self)
        let member = entity("Member", Member.self)
        let chore = entity("Chore", Chore.self)
        let completion = entity("ChoreCompletion", ChoreCompletion.self)

        family.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]
        member.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("kindValue", .stringAttributeType),
            attribute("colorIndex", .integer16AttributeType, default: 0),
            attribute("birthDate", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]
        chore.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("recurrenceValue", .stringAttributeType),
            attribute("weekdayMask", .integer16AttributeType, default: 0),
            attribute("startDate", .dateAttributeType),
            // Phase 2 (kids' points): stored now so no migration is needed later.
            attribute("points", .integer16AttributeType, default: 0),
            attribute("createdAt", .dateAttributeType),
        ]
        completion.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("occurrenceDate", .dateAttributeType),
            attribute("completedAt", .dateAttributeType),
            attribute("pointsAwarded", .integer16AttributeType, default: 0),
        ]

        link(family, "members", .cascadeDeleteRule, many: member, "family")
        link(family, "chores", .cascadeDeleteRule, many: chore, "family")
        link(member, "assignedChores", .nullifyDeleteRule, many: chore, "assignee")
        link(chore, "completions", .cascadeDeleteRule, many: completion, "chore")
        link(member, "completions", .nullifyDeleteRule, many: completion, "completedBy")

        let model = NSManagedObjectModel()
        model.entities = [family, member, chore, completion]
        return model
    }

    private static func entity(_ name: String, _ type: NSManagedObject.Type) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(type)
        return entity
    }

    /// A one-to-many relationship and its inverse: `parent.<toMany>` ↔ `child.<toOne>`.
    /// The child side always nullifies, so deleting a child never touches its parent.
    private static func link(
        _ parent: NSEntityDescription,
        _ toMany: String,
        _ deleteRule: NSDeleteRule,
        many child: NSEntityDescription,
        _ toOne: String
    ) {
        let children = relationship(toMany, to: child, toMany: true, deleteRule: deleteRule)
        let owner = relationship(toOne, to: parent, toMany: false, deleteRule: .nullifyDeleteRule)
        children.inverseRelationship = owner
        owner.inverseRelationship = children
        parent.properties.append(children)
        child.properties.append(owner)
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = value
        return attribute
    }

    private static func relationship(
        _ name: String,
        to destination: NSEntityDescription,
        toMany: Bool,
        deleteRule: NSDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = 0
        relationship.maxCount = toMany ? 0 : 1
        relationship.deleteRule = deleteRule
        relationship.isOptional = true
        return relationship
    }
}
