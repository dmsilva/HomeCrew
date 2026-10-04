import SwiftUI

struct AgendaView: View {
    var body: some View {
        EmptyStateScreen(
            tab: .agenda,
            message: "Sem atividades"
        )
    }
}

#Preview {
    AgendaView()
}
