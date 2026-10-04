import CloudKit
import os
import UIKit

/// Only here to route iCloud share invitations into the app; SwiftUI has no hook for them.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    private let logger = Logger(subsystem: "com.dmsilva.homecrew", category: "sharing")

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            do {
                try await PersistenceController.shared.accept(metadata)
            } catch {
                logger.error("Could not accept share: \(error.localizedDescription)")
            }
        }
    }
}
