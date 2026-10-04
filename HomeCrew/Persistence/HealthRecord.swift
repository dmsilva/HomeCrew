import Foundation

/// What the health record editor collects for one person.
struct HealthRecordDraft: Equatable {
    var allergies = ""
    var weightKg: Double?
    var chronicConditions = ""
    var usualMedication = ""
    var pediatricianName = ""
    var pediatricianPhone = ""

    init() {}

    init(_ member: Member) {
        allergies = member.allergies ?? ""
        weightKg = member.weightKg > 0 ? member.weightKg : nil
        chronicConditions = member.chronicConditions ?? ""
        usualMedication = member.usualMedication ?? ""
        pediatricianName = member.pediatricianName ?? ""
        pediatricianPhone = member.pediatricianPhone ?? ""
    }
}

extension Member {
    /// Allergies as separate items, from a comma, semicolon or line separated text.
    var allergyList: [String] {
        (allergies ?? "")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var hasAllergies: Bool { !allergyList.isEmpty }

    /// A `tel:` link for the pediatrician, keeping only what a dialler understands.
    var pediatricianCallURL: URL? {
        let digits = (pediatricianPhone ?? "").filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:\(digits)")
    }
}

extension PersistenceController {
    func updateHealthRecord(of member: Member, with draft: HealthRecordDraft) {
        member.allergies = draft.allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        let newWeight = draft.weightKg ?? 0
        if newWeight != member.weightKg {
            member.weightKg = newWeight
            member.weightUpdatedAt = newWeight > 0 ? .now : nil
        }
        member.chronicConditions = draft.chronicConditions.trimmingCharacters(in: .whitespacesAndNewlines)
        member.usualMedication = draft.usualMedication.trimmingCharacters(in: .whitespacesAndNewlines)
        member.pediatricianName = draft.pediatricianName.trimmingCharacters(in: .whitespaces)
        member.pediatricianPhone = draft.pediatricianPhone.trimmingCharacters(in: .whitespaces)
        save()
    }
}
