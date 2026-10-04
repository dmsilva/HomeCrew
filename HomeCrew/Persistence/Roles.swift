import CloudKit
import CoreData
import os
import SwiftUI

/// What an adult can do in the family. Children have no account, so no role.
enum Role: String, CaseIterable, Identifiable {
    /// Sees and edits everything about their children.
    case parent
    /// Grandparents or a nanny: only the children and days they are given.
    case carer
    /// Sees the agenda, nothing else, and cannot change it.
    case guest

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .parent: "Pai/Mãe"
        case .carer: "Cuidador"
        case .guest: "Convidado"
        }
    }

    var systemImage: String {
        switch self {
        case .parent: "figure.and.child.holdinghands"
        case .carer: "heart.circle"
        case .guest: "eye"
        }
    }

    /// The iCloud permission that matches the role: guests can only read.
    var sharePermission: CKShare.ParticipantPermission {
        self == .guest ? .readOnly : .readWrite
    }
}

extension Member {
    /// Adults without a stored role are parents: that is who created the family before roles existed.
    var role: Role {
        get { Role(rawValue: roleValue ?? "") ?? .parent }
        set { roleValue = newValue.rawValue }
    }

    /// Weekdays (1 = Sunday) a carer looks after the children; empty means every day.
    var careWeekdays: Set<Int> {
        get { WeekdayMask.decode(careWeekdayMask) }
        set { careWeekdayMask = WeekdayMask.encode(newValue) }
    }

    var caredChildrenList: [Member] {
        ((caredChildren as? Set<Member>) ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
}

extension Family {
    func member(withID id: String) -> Member? {
        guard !id.isEmpty else { return nil }
        return sortedMembers.first { $0.identifier?.uuidString == id }
    }
}

/// What the person using this iPhone may see and change, worked out from their member and role.
struct AccessPolicy: Equatable {
    let role: Role
    /// Children this person may see; nil means all of them.
    let children: Set<NSManagedObjectID>?
    /// Weekdays this person may see; nil means every day.
    let weekdays: Set<Int>?
    let me: NSManagedObjectID?

    static let full = AccessPolicy(role: .parent, children: nil, weekdays: nil, me: nil)

    /// Nothing but the agenda, read only: used until someone who joined a shared family says who they are.
    static let unidentified = AccessPolicy(role: .guest, children: nil, weekdays: nil, me: nil)

    init(role: Role, children: Set<NSManagedObjectID>?, weekdays: Set<Int>?, me: NSManagedObjectID?) {
        self.role = role
        self.children = children
        self.weekdays = weekdays
        self.me = me
    }

    init(for me: Member) {
        let role = me.kind == .adult ? me.role : .guest
        self.init(
            role: role,
            children: role == .carer ? Set(me.caredChildrenList.map(\.objectID)) : nil,
            weekdays: role == .carer && !me.careWeekdays.isEmpty ? me.careWeekdays : nil,
            me: me.objectID
        )
    }

    var tabs: [AppTab] {
        switch role {
        case .parent: AppTab.allCases
        case .carer: [.today, .agenda, .health]
        case .guest: [.agenda]
        }
    }

    var canEdit: Bool { role != .guest }
    var canManageFamily: Bool { role == .parent }

    func canSee(_ member: Member?) -> Bool {
        guard let children, let member else { return true }
        if member.objectID == me { return true }
        if member.kind == .adult { return true }
        return children.contains(member.objectID)
    }

    func canSee(day: Date, calendar: Calendar = .current) -> Bool {
        guard let weekdays else { return true }
        return weekdays.contains(calendar.component(.weekday, from: day))
    }

    func filter(_ occurrences: [ActivityOccurrence], calendar: Calendar = .current) -> [ActivityOccurrence] {
        occurrences.filter { canSee(day: $0.start, calendar: calendar) && canSee($0.activity.child) }
    }

    func filter(_ chores: [Chore], on day: Date, calendar: Calendar = .current) -> [Chore] {
        guard canSee(day: day, calendar: calendar) else { return [] }
        return chores.filter { canSee($0.assignee) }
    }

    /// People shown on the health tab: a carer sees their children and themselves.
    func visibleMembers(of family: Family) -> [Member] {
        guard children != nil else { return family.sortedMembers }
        return family.sortedMembers.filter { $0.objectID == me || ($0.kind == .child && canSee($0)) }
    }
}

private struct AccessPolicyKey: EnvironmentKey {
    static let defaultValue = AccessPolicy.full
}

extension EnvironmentValues {
    var access: AccessPolicy {
        get { self[AccessPolicyKey.self] }
        set { self[AccessPolicyKey.self] = newValue }
    }
}

/// What the invite form collects: the new person's name, role, and for a carer their children and days.
struct InviteDraft: Equatable {
    var name = ""
    var role: Role = .parent
    var children: Set<NSManagedObjectID> = []
    var weekdays: Set<Int> = []

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

extension PersistenceController {
    private static let sharingLog = Logger(subsystem: "com.dmsilva.homecrew", category: "sharing")

    /// True when this family was shared with this account by someone else.
    func isJoined(_ family: Family) -> Bool {
        guard let sharedStore else { return false }
        return family.objectID.persistentStore == sharedStore
    }

    /// Adds the invited adult to the family with their role, before the link goes out.
    @discardableResult
    func addInvitee(_ draft: InviteDraft, to family: Family) -> Member {
        var member = MemberDraft()
        member.name = draft.name
        member.kind = .adult
        member.colorIndex = family.nextColorIndex
        let invitee = addMember(member, to: family)
        setRole(draft.role, children: draft.children, weekdays: draft.weekdays, for: invitee)
        return invitee
    }

    /// Changes what an adult may see. A carer keeps only the children chosen; other roles see all.
    func setRole(_ role: Role, children: Set<NSManagedObjectID>, weekdays: Set<Int>, for member: Member) {
        member.role = role
        let chosen = role == .carer
            ? (member.family?.sortedMembers ?? []).filter { $0.kind == .child && children.contains($0.objectID) }
            : []
        member.caredChildren = NSSet(array: chosen)
        member.careWeekdays = role == .carer ? weekdays : []
        save()
        Task { await updateSharePermission(for: member) }
    }

    /// Remembers which iCloud account uses this member, so the family owner can match them to the share.
    func link(_ member: Member, toAccount recordName: String) {
        guard member.accountID != recordName else { return }
        member.accountID = recordName
        save()
    }

    func currentAccountRecordName() async -> String? {
        try? await cloudKitContainer.userRecordID().recordName
    }

    /// Mirrors a role change onto the iCloud share, so a guest really is read-only.
    @MainActor
    func updateSharePermission(for member: Member) async {
        guard let family = member.family, let share = existingShare(for: family),
              let participant = participant(for: member, in: share),
              participant.role != .owner,
              participant.permission != member.role.sharePermission
        else { return }
        participant.permission = member.role.sharePermission
        await persist(share, of: family)
    }

    /// Takes the person out of the iCloud share; they keep their member card, without access.
    @MainActor
    func removeAccess(of member: Member) async {
        if let family = member.family, let share = existingShare(for: family),
           let participant = participant(for: member, in: share), participant.role != .owner {
            share.removeParticipant(participant)
            await persist(share, of: family)
        }
        member.accountID = nil
        save()
    }

    func hasAccess(_ member: Member) -> Bool {
        guard let family = member.family, let share = existingShare(for: family) else { return false }
        return participant(for: member, in: share) != nil
    }

    private func participant(for member: Member, in share: CKShare) -> CKShare.Participant? {
        guard let account = member.accountID, !account.isEmpty else { return nil }
        return share.participants.first { $0.userIdentity.userRecordID?.recordName == account }
    }

    @MainActor
    private func persist(_ share: CKShare, of family: Family) async {
        guard let store = family.objectID.persistentStore else { return }
        do {
            _ = try await container.persistUpdatedShare(share, in: store)
        } catch {
            Self.sharingLog.error("Could not update the share: \(error.localizedDescription)")
        }
    }
}
