import SwiftUI

/// The white bar at the bottom of the app: an icon and a short name per section, green for the one you are on,
/// and a green "+" in the middle to create something.
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
        .background {
            Color.hcCard
                .overlay(alignment: .top) { Color.hcSeparator.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                Text(tab.title)
                    .font(Theme.Typography.text(11, weight: isSelected ? .semibold : .regular, relativeTo: .caption2))
            }
            .foregroundStyle(isSelected ? Color.hcAccent : Color.hcSecondaryInk)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
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
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.hcAccent, in: Circle())
                .shadow(color: Color.hcAccent.opacity(0.3), radius: 8, y: 4)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(Text("Criar"))
        .accessibilityIdentifier("tab-create")
    }
}
