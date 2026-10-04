import SwiftUI

/// The four top-level sections of the app, in tab-bar order.
enum AppTab: String, CaseIterable, Identifiable {
    case today
    case agenda
    case family
    case health

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Hoje"
        case .agenda: "Agenda"
        case .family: "Família"
        case .health: "Saúde"
        }
    }

    /// SF Symbol shown in the tab bar.
    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .agenda: "calendar"
        case .family: "person.2"
        case .health: "thermometer.medium"
        }
    }
}
