import CloudKit
import CoreData
import os

/// Owns the Core Data stack mirrored to CloudKit.
/// Two stores share one model: the private store holds what this account owns,
/// the shared store holds what other accounts shared with it.
final class PersistenceController {
    static let cloudKitContainerIdentifier = "iCloud.com.dmsilva.homecrew"

    static let shared = PersistenceController(
        inMemory: ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    )

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    private let logger = Logger(subsystem: "com.dmsilva.homecrew", category: "persistence")

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "HomeCrew", managedObjectModel: HomeCrewModel.shared)
        container.persistentStoreDescriptions = inMemory
            ? [NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))]
            : Self.cloudKitStoreDescriptions(in: NSPersistentContainer.defaultDirectoryURL())

        container.loadPersistentStores { [self] description, error in
            if let error {
                logger.error("Could not load store \(description.url?.lastPathComponent ?? "?"): \(error.localizedDescription)")
                return
            }
            guard let url = description.url,
                  let store = container.persistentStoreCoordinator.persistentStore(for: url) else { return }
            if description.cloudKitContainerOptions?.databaseScope == .shared {
                sharedStore = store
            } else {
                privateStore = store
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
    }

    /// One private and one shared store, both mirrored to the same CloudKit container.
    static func cloudKitStoreDescriptions(in directory: URL) -> [NSPersistentStoreDescription] {
        [(CKDatabase.Scope.private, "private.sqlite"), (.shared, "shared.sqlite")].map { scope, file in
            let description = NSPersistentStoreDescription(url: directory.appendingPathComponent(file))
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            options.databaseScope = scope
            description.cloudKitContainerOptions = options
            // History tracking and remote change notifications are what let edits made
            // offline or on another device merge back in once the network returns.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            return description
        }
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
            context.rollback()
        }
    }
}
