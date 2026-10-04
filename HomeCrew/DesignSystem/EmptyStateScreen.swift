import SwiftUI

/// A tab's placeholder until its feature lands: one icon and one short line,
/// following the "ver, não ler" rule of keeping text to a minimum.
struct EmptyStateScreen: View {
    let tab: AppTab
    let message: LocalizedStringKey

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hcBackground.ignoresSafeArea()
                ContentUnavailableView {
                    Image(systemName: tab.systemImage)
                        .font(Theme.Typography.heroIcon)
                        .foregroundStyle(Color.hcAccent)
                        .accessibilityHidden(true)
                } description: {
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Color.hcSecondaryInk)
                }
            }
            .navigationTitle(tab.title)
        }
    }
}
