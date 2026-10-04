import CoreData

/// What the member editor collects; kept apart from Member so a cancelled edit changes nothing.
struct MemberDraft: Equatable {
    var name = ""
    var kind: Member.Kind = .child
    var birthDate = Calendar.current.date(byAdding: .year, value: -6, to: .now) ?? .now
    var colorIndex: Int16 = 0

    init() {}

    init(_ member: Member) {
        name = member.name ?? ""
        kind = member.kind
        birthDate = member.birthDate ?? birthDate
        colorIndex = member.colorIndex
    }

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

extension PersistenceController {
    @discardableResult
    func addMember(_ draft: MemberDraft, to family: Family) -> Member {
        let member = Member(context: viewContext)
        // A family shared by someone else lives in the shared store; its members must too,
        // or CloudKit would put them in this account's private database where nobody else sees them.
        if let store = family.objectID.persistentStore {
            viewContext.assign(member, to: store)
        }
        member.identifier = UUID()
        member.createdAt = .now
        member.family = family
        apply(draft, to: member)
        save()
        return member
    }

    func update(_ member: Member, with draft: MemberDraft) {
        apply(draft, to: member)
        save()
    }

    func delete(_ member: Member) {
        viewContext.delete(member)
        save()
    }

    func rename(_ family: Family, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        family.name = trimmed
        save()
    }

    private func apply(_ draft: MemberDraft, to member: Member) {
        member.name = draft.name.trimmingCharacters(in: .whitespaces)
        member.kind = draft.kind
        member.birthDate = draft.birthDate
        member.colorIndex = draft.colorIndex
    }
}
