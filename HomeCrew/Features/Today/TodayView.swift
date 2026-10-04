import SwiftUI

struct TodayView: View {
    var body: some View {
        EmptyStateScreen(
            tab: .today,
            message: "Nada para hoje"
        )
    }
}

#Preview {
    TodayView()
}
