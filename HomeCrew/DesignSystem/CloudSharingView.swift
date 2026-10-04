import CloudKit
import SwiftUI
import UIKit

/// Apple's sharing sheet (invite, see participants, stop sharing) wrapped for SwiftUI.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}

/// Lets a CKShare drive `.sheet(item:)`.
struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
}
