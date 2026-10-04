import SwiftUI

struct TodayView: View {
    var body: some View {
        EmptyStateScreen(
            title: AppTab.today.title,
            systemImage: AppTab.today.systemImage,
            message: "Nada para hoje"
        )
    }
}

#Preview {
    TodayView()
}
