import SwiftUI

struct FamilyView: View {
    var body: some View {
        EmptyStateScreen(
            title: AppTab.family.title,
            systemImage: AppTab.family.systemImage,
            message: "Ainda sem membros"
        )
    }
}

#Preview {
    FamilyView()
}
