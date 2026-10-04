import CloudKit
import os
import UIKit
import UserNotifications

/// Routes what SwiftUI has no hook for: iCloud share invitations and taps on dose notifications.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DoseReminderCenter.shared.start()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if response.actionIdentifier == PlannedReminder.giveNowAction,
           let id = (userInfo[PlannedReminder.medicationKey] as? String).flatMap(UUID.init(uuidString:)) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    DoseReminderCenter.shared.giveNow(medicationID: id)
                }
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

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
