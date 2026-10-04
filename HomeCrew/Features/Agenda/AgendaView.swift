import SwiftUI

struct AgendaView: View {
    var body: some View {
        EmptyStateScreen(
            title: AppTab.agenda.title,
            systemImage: AppTab.agenda.systemImage,
            message: "Sem atividades"
        )
    }
}

#Preview {
    AgendaView()
}
