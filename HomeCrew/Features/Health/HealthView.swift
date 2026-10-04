import SwiftUI

struct HealthView: View {
    var body: some View {
        EmptyStateScreen(
            tab: .health,
            message: "Sem episódios"
        )
    }
}

#Preview {
    HealthView()
}
