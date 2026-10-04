import CoreData

/// Which of the two houses a child is in on a given day, following a repeating 14-day cycle.
enum CustodyPattern: String, CaseIterable, Identifiable {
    /// One week with each parent.
    case alternateWeeks
    /// Two days, two days, three days, swapping each week.
    case twoTwoThree
    /// Any 14-day cycle the parents tap in.
    case custom

    static let cycleLength = 14

    var id: String { rawValue }

    /// The cycle as true for house A, false for house B, day 0 being the start date.
    func cycle(custom: [Bool]) -> [Bool] {
        switch self {
        case .alternateWeeks: Array(repeating: true, count: 7) + Array(repeating: false, count: 7)
        case .twoTwoThree: Array("AABBAAABBAABBB").map { $0 == "A" }
        case .custom: custom.count == Self.cycleLength ? custom : Self.alternateWeeks.cycle(custom: [])
        }
    }
}

enum CustodyHouse: Equatable {
    case a, b
}

/// One child's custody arrangement between two adults.
@objc(CustodyPlan)
final class CustodyPlan: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var patternValue: String?
    @NSManaged var startDate: Date?
    @NSManaged var customCycle: String?
    @NSManaged var createdAt: Date?
    @NSManaged var child: Member?
    @NSManaged var parentA: Member?
    @NSManaged var parentB: Member?

    static func all() -> NSFetchRequest<CustodyPlan> {
        let request = NSFetchRequest<CustodyPlan>(entityName: "CustodyPlan")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    var pattern: CustodyPattern {
        get { CustodyPattern(rawValue: patternValue ?? "") ?? .alternateWeeks }
        set { patternValue = newValue.rawValue }
    }

    /// The custom cycle as booleans (true = house A).
    var customDays: [Bool] {
        get { Array(customCycle ?? "").map { $0 == "A" } }
        set { customCycle = String(newValue.map { $0 ? "A" : "B" }) }
    }

    func house(on day: Date, calendar: Calendar = .current) -> CustodyHouse {
        let cycle = pattern.cycle(custom: customDays)
        let start = calendar.startOfDay(for: startDate ?? .distantPast)
        let offset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: day)).day ?? 0
        let index = ((offset % cycle.count) + cycle.count) % cycle.count
        return cycle[index] ? .a : .b
    }

    /// Who has the child that day.
    func custodian(on day: Date, calendar: Calendar = .current) -> Member? {
        house(on: day, calendar: calendar) == .a ? parentA : parentB
    }
}

extension Member {
    /// The child's plan, if the parents set one up.
    var custodyPlan: CustodyPlan? {
        ((custodyPlans as? Set<CustodyPlan>) ?? []).min { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Whether this child is with `adult` on `day`. Children without a plan, and adults outside it, always count as "with".
    func isWith(_ adult: Member?, on day: Date, calendar: Calendar = .current) -> Bool {
        guard kind == .child, let adult, let plan = custodyPlan,
              plan.parentA == adult || plan.parentB == adult
        else { return true }
        return plan.custodian(on: day, calendar: calendar) == adult
    }
}

/// What the custody form collects.
struct CustodyDraft: Equatable {
    var parentA: Member?
    var parentB: Member?
    var pattern: CustodyPattern = .alternateWeeks
    var startDate = Calendar.current.startOfDay(for: .now)
    var customDays: [Bool] = CustodyPattern.alternateWeeks.cycle(custom: [])

    init() {}

    init(_ plan: CustodyPlan) {
        parentA = plan.parentA
        parentB = plan.parentB
        pattern = plan.pattern
        startDate = plan.startDate ?? startDate
        if plan.customDays.count == CustodyPattern.cycleLength { customDays = plan.customDays }
    }

    var isValid: Bool { parentA != nil && parentB != nil && parentA != parentB }
}

extension PersistenceController {
    /// Creates or replaces the child's plan.
    @discardableResult
    func setCustody(_ draft: CustodyDraft, for child: Member) -> CustodyPlan {
        let plan: CustodyPlan
        if let existing = child.custodyPlan {
            plan = existing
        } else {
            plan = CustodyPlan(context: viewContext)
            if let store = child.objectID.persistentStore {
                viewContext.assign(plan, to: store)
            }
            plan.identifier = UUID()
            plan.createdAt = .now
            plan.child = child
        }
        plan.parentA = draft.parentA
        plan.parentB = draft.parentB
        plan.pattern = draft.pattern
        plan.startDate = draft.startDate
        plan.customDays = draft.customDays
        save()
        return plan
    }

    func removeCustody(of child: Member) {
        ((child.custodyPlans as? Set<CustodyPlan>) ?? []).forEach(viewContext.delete)
        save()
    }
}
