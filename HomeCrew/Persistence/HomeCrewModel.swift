import CoreData
import UIKit

/// A family: the unit that is shared between iCloud accounts.
@objc(Family)
final class Family: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var members: NSSet?

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
        let family = NSEntityDescription()
        family.name = "Family"
        family.managedObjectClassName = NSStringFromClass(Family.self)

        let member = NSEntityDescription()
        member.name = "Member"
        member.managedObjectClassName = NSStringFromClass(Member.self)

        let familyMembers = relationship("members", to: member, toMany: true, deleteRule: .cascadeDeleteRule)
        let memberFamily = relationship("family", to: family, toMany: false, deleteRule: .nullifyDeleteRule)
        familyMembers.inverseRelationship = memberFamily
        memberFamily.inverseRelationship = familyMembers

        family.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            familyMembers,
        ]
        member.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("kindValue", .stringAttributeType),
            attribute("colorIndex", .integer16AttributeType, default: 0),
            attribute("birthDate", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
            memberFamily,
        ]

        let model = NSManagedObjectModel()
        model.entities = [family, member]
        return model
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
