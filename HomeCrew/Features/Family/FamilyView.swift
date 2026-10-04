import SwiftUI

struct FamilyView: View {
    var body: some View {
        EmptyStateScreen(
            tab: .family,
            message: "Ainda sem membros"
        )
    }
}

#Preview {
    FamilyView()
}
