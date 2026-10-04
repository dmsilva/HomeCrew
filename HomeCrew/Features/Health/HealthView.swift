import SwiftUI

struct HealthView: View {
    var body: some View {
        EmptyStateScreen(
            title: AppTab.health.title,
            systemImage: AppTab.health.systemImage,
            message: "Todos bem"
        )
    }
}

#Preview {
    HealthView()
}
