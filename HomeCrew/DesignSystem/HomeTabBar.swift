import SwiftUI

/// The floating dark pill at the bottom of the app: one icon per section and the "+" to create something.
/// Replaces the system tab bar so it looks like the design; each icon still carries its section's name for VoiceOver.
struct HomeTabBar: View {
    let tabs: [AppTab]
    @Binding var selection: AppTab
    /// Nil hides the "+" (for people who can only look).
    let onCreate: ((CreateAction) -> Void)?

    enum CreateAction {
        case activity, chore
    }

    static let height: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                if index == tabs.count / 2, let onCreate {
                    createMenu(onCreate)
                }
                tabButton(tab)
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // On Família's night background the bar lifts to a lighter night so it stays visible.
        .background(selection == .family ? Color(UIColor(hex: 0x2A2650)) : Color.hcNight, in: Capsule())
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Image(systemName: tab.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.hcNight : Color.white)
                .frame(width: 48, height: 48)
                .background(isSelected ? Color.hcLime : Color.clear, in: Circle())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityIdentifier("tab-\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func createMenu(_ onCreate: @escaping (CreateAction) -> Void) -> some View {
        Menu {
            Button { onCreate(.activity) } label: { Label("Atividade", systemImage: "figure.run") }
            Button { onCreate(.chore) } label: { Label("Tarefa", systemImage: "checklist") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.hcAccent, in: Circle())
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(Text("Criar"))
        .accessibilityIdentifier("tab-create")
    }
}
