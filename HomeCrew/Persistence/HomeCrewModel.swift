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
    @NSManaged var activities: NSSet?

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

    var adults: [Member] { sortedMembers.filter { $0.kind == .adult } }

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
    @NSManaged var allergies: String?
    @NSManaged var weightKg: Double
    @NSManaged var weightUpdatedAt: Date?
    @NSManaged var chronicConditions: String?
    @NSManaged var usualMedication: String?
    @NSManaged var pediatricianName: String?
    @NSManaged var pediatricianPhone: String?
    @NSManaged var assignedChores: NSSet?
    @NSManaged var completions: NSSet?
    @NSManaged var activities: NSSet?
    @NSManaged var dropOffActivities: NSSet?
    @NSManaged var pickUpActivities: NSSet?
    @NSManaged var dropOffExceptions: NSSet?
    @NSManaged var pickUpExceptions: NSSet?
    @NSManaged var episodes: NSSet?
    @NSManaged var responsibleMedications: NSSet?
    @NSManaged var givenDoses: NSSet?
    @NSManaged var roleValue: String?
    @NSManaged var accountID: String?
    @NSManaged var careWeekdayMask: Int16
    @NSManaged var caredChildren: NSSet?
    @NSManaged var carers: NSSet?
    @NSManaged var custodyPlans: NSSet?
    @NSManaged var custodyPlansAsA: NSSet?
    @NSManaged var custodyPlansAsB: NSSet?
    @NSManaged var requestedSwaps: NSSet?

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
        let activity = entity("Activity", Activity.self)
        let exception = entity("ActivityException", ActivityException.self)
        let episode = entity("IllnessEpisode", IllnessEpisode.self)
        let reading = entity("TemperatureReading", TemperatureReading.self)
        let medication = entity("Medication", Medication.self)
        let dose = entity("DoseGiven", DoseGiven.self)
        let custody = entity("CustodyPlan", CustodyPlan.self)
        let swap = entity("CustodySwap", CustodySwap.self)

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
            // Health record (one per person, so it lives on the member).
            attribute("allergies", .stringAttributeType),
            attribute("weightKg", .doubleAttributeType, default: 0),
            attribute("weightUpdatedAt", .dateAttributeType),
            attribute("chronicConditions", .stringAttributeType),
            attribute("usualMedication", .stringAttributeType),
            attribute("pediatricianName", .stringAttributeType),
            attribute("pediatricianPhone", .stringAttributeType),
            attribute("roleValue", .stringAttributeType),
            attribute("accountID", .stringAttributeType),
            attribute("careWeekdayMask", .integer16AttributeType, default: 0),
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

        activity.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("symbolName", .stringAttributeType),
            attribute("weekdayMask", .integer16AttributeType, default: 0),
            attribute("startMinutes", .integer16AttributeType, default: 0),
            attribute("durationMinutes", .integer16AttributeType, default: 60),
            attribute("location", .stringAttributeType),
            attribute("equipment", .stringAttributeType),
            attribute("notes", .stringAttributeType),
            attribute("startDate", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]

        exception.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("occurrenceDate", .dateAttributeType),
            attribute("isCancelled", .booleanAttributeType, default: false),
        ]

        episode.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("startedAt", .dateAttributeType),
            attribute("endedAt", .dateAttributeType),
            attribute("symptomMask", .integer64AttributeType, default: 0),
            attribute("notes", .stringAttributeType),
        ]
        reading.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("takenAt", .dateAttributeType),
            attribute("celsius", .doubleAttributeType, default: 0),
        ]
        medication.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("dose", .stringAttributeType),
            attribute("intervalHours", .doubleAttributeType, default: 8),
            attribute("createdAt", .dateAttributeType),
            attribute("stoppedAt", .dateAttributeType),
        ]
        custody.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("patternValue", .stringAttributeType),
            attribute("startDate", .dateAttributeType),
            // One letter per day of the 14-day cycle: "A" for the first house, "B" for the second.
            attribute("customCycle", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]
        swap.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("firstDay", .dateAttributeType),
            attribute("lastDay", .dateAttributeType),
            attribute("statusValue", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("respondedAt", .dateAttributeType),
        ]
        dose.properties = [
            attribute("identifier", .UUIDAttributeType),
            attribute("givenAt", .dateAttributeType),
        ]

        link(family, "members", .cascadeDeleteRule, many: member, "family")
        link(family, "chores", .cascadeDeleteRule, many: chore, "family")
        link(member, "assignedChores", .nullifyDeleteRule, many: chore, "assignee")
        link(chore, "completions", .cascadeDeleteRule, many: completion, "chore")
        link(member, "completions", .nullifyDeleteRule, many: completion, "completedBy")
        link(family, "activities", .cascadeDeleteRule, many: activity, "family")
        link(member, "activities", .nullifyDeleteRule, many: activity, "child")
        link(member, "dropOffActivities", .nullifyDeleteRule, many: activity, "dropOff")
        link(member, "pickUpActivities", .nullifyDeleteRule, many: activity, "pickUp")
        link(activity, "exceptions", .cascadeDeleteRule, many: exception, "activity")
        link(member, "dropOffExceptions", .nullifyDeleteRule, many: exception, "dropOff")
        link(member, "pickUpExceptions", .nullifyDeleteRule, many: exception, "pickUp")
        link(member, "episodes", .cascadeDeleteRule, many: episode, "member")
        link(episode, "readings", .cascadeDeleteRule, many: reading, "episode")
        link(episode, "medications", .cascadeDeleteRule, many: medication, "episode")
        link(medication, "doses", .cascadeDeleteRule, many: dose, "medication")
        link(member, "responsibleMedications", .nullifyDeleteRule, many: medication, "responsible")
        link(member, "givenDoses", .nullifyDeleteRule, many: dose, "givenBy")
        manyToMany(member, "caredChildren", member, "carers")
        link(member, "custodyPlans", .cascadeDeleteRule, many: custody, "child")
        link(member, "custodyPlansAsA", .nullifyDeleteRule, many: custody, "parentA")
        link(member, "custodyPlansAsB", .nullifyDeleteRule, many: custody, "parentB")
        link(custody, "swaps", .cascadeDeleteRule, many: swap, "plan")
        link(member, "requestedSwaps", .nullifyDeleteRule, many: swap, "requester")

        let model = NSManagedObjectModel()
        model.entities = [family, member, chore, completion, activity, exception, episode, reading, medication, dose, custody, swap]
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

    /// A many-to-many relationship and its inverse, nullified on both sides.
    private static func manyToMany(_ a: NSEntityDescription, _ aToB: String, _ b: NSEntityDescription, _ bToA: String) {
        let forward = relationship(aToB, to: b, toMany: true, deleteRule: .nullifyDeleteRule)
        let backward = relationship(bToA, to: a, toMany: true, deleteRule: .nullifyDeleteRule)
        forward.inverseRelationship = backward
        backward.inverseRelationship = forward
        a.properties.append(forward)
        b.properties.append(backward)
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
