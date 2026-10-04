import CloudKit
import CoreData

extension PersistenceController {
    var cloudKitContainer: CKContainer { CKContainer(identifier: Self.cloudKitContainerIdentifier) }

    @discardableResult
    func createFamily(named name: String) -> Family {
        let family = Family(context: viewContext)
        family.identifier = UUID()
        family.name = name
        family.createdAt = .now
        save()
        return family
    }

    func existingShare(for family: Family) -> CKShare? {
        (try? container.fetchShares(matching: [family.objectID]))?[family.objectID]
    }

    /// Returns the family's share, creating it the first time.
    func share(_ family: Family) async throws -> CKShare {
        if let share = existingShare(for: family) { return share }
        let (_, share, _) = try await container.share([family], to: nil)
        return share
    }

    /// Called when this account taps an invitation link: the family lands in the shared store.
    func accept(_ metadata: CKShare.Metadata) async throws {
        guard let sharedStore else { return }
        _ = try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
    }
}
