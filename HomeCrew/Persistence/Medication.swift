import CoreData

/// A medicine given during an episode. The dose and interval are what the parents were told:
/// the app stores them as written and never works out a dose itself.
@objc(Medication)
final class Medication: NSManagedObject {
    /// Common names offered while typing; anything else can be typed freely.
    static let suggestions = [
        "Ben-u-ron", "Brufen", "Paracetamol", "Ibuprofeno", "Amoxicilina", "Clamoxyl",
        "Aerius", "Ventilan", "Zyrtec", "Fenistil", "Bisolvon", "Soro fisiológico",
    ]

    /// Suggestions starting with what was typed, ignoring case and accents; all of them for an empty field.
    static func suggestions(for text: String) -> [String] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return suggestions }
        return suggestions.filter {
            $0.range(of: typed, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
                && $0.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
    }

    @NSManaged var identifier: UUID?
    @NSManaged var name: String?
    @NSManaged var dose: String?
    @NSManaged var intervalHours: Double
    @NSManaged var createdAt: Date?
    @NSManaged var stoppedAt: Date?
    @NSManaged var episode: IllnessEpisode?
    @NSManaged var responsible: Member?
    @NSManaged var doses: NSSet?

    static func all() -> NSFetchRequest<Medication> {
        let request = NSFetchRequest<Medication>(entityName: "Medication")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return request
    }

    /// Still being given: not stopped, and its episode is still open.
    var isActive: Bool { stoppedAt == nil && episode?.isActive == true }

    var interval: TimeInterval { max(intervalHours, 0) * 3600 }

    /// Doses newest first.
    var sortedDoses: [DoseGiven] {
        ((doses as? Set<DoseGiven>) ?? []).sorted { ($0.givenAt ?? .distantPast) > ($1.givenAt ?? .distantPast) }
    }

    var lastDose: DoseGiven? { sortedDoses.first }

    /// When the next dose is due; nil before the first dose, which is given whenever the parents decide.
    var nextDoseAt: Date? {
        guard isActive, interval > 0, let last = lastDose?.givenAt else { return nil }
        return last.addingTimeInterval(interval)
    }

    func isDue(at date: Date) -> Bool {
        guard isActive else { return false }
        guard let next = nextDoseAt else { return true }
        return next <= date
    }
}

@objc(DoseGiven)
final class DoseGiven: NSManagedObject {
    @NSManaged var identifier: UUID?
    @NSManaged var givenAt: Date?
    @NSManaged var medication: Medication?
    @NSManaged var givenBy: Member?
}

extension IllnessEpisode {
    var sortedMedications: [Medication] {
        ((medications as? Set<Medication>) ?? []).sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    var activeMedications: [Medication] { sortedMedications.filter(\.isActive) }
}

/// What the parents typed in the medication form; nothing is saved until "Guardar".
struct MedicationDraft: Equatable {
    var name = ""
    var dose = ""
    var intervalHours = 8.0
    var responsible: Member?
    var givenNow = false

    init() {}

    init(_ medication: Medication) {
        name = medication.name ?? ""
        dose = medication.dose ?? ""
        intervalHours = medication.intervalHours
        responsible = medication.responsible
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && intervalHours > 0
    }
}

extension PersistenceController {
    @discardableResult
    func addMedication(_ draft: MedicationDraft, to episode: IllnessEpisode, by member: Member?, at date: Date = .now) -> Medication {
        let medication = Medication(context: viewContext)
        if let store = episode.objectID.persistentStore {
            viewContext.assign(medication, to: store)
        }
        medication.identifier = UUID()
        medication.createdAt = date
        medication.episode = episode
        apply(draft, to: medication)
        if draft.givenNow {
            giveDose(of: medication, by: member, at: date)
        } else {
            save()
        }
        return medication
    }

    func update(_ medication: Medication, with draft: MedicationDraft) {
        apply(draft, to: medication)
        save()
    }

    private func apply(_ draft: MedicationDraft, to medication: Medication) {
        medication.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.dose = draft.dose.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.intervalHours = draft.intervalHours
        medication.responsible = draft.responsible
    }

    /// Records "dei agora": the next dose is then due one interval later.
    @discardableResult
    func giveDose(of medication: Medication, by member: Member?, at date: Date = .now) -> DoseGiven {
        let dose = DoseGiven(context: viewContext)
        if let store = medication.objectID.persistentStore {
            viewContext.assign(dose, to: store)
        }
        dose.identifier = UUID()
        dose.givenAt = date
        dose.givenBy = member
        dose.medication = medication
        save()
        return dose
    }

    func delete(_ dose: DoseGiven) {
        viewContext.delete(dose)
        save()
    }

    func stop(_ medication: Medication, at date: Date = .now) {
        medication.stoppedAt = date
        save()
    }

    func medication(withIdentifier identifier: UUID) -> Medication? {
        let request = Medication.all()
        request.predicate = NSPredicate(format: "identifier == %@", identifier as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
}
