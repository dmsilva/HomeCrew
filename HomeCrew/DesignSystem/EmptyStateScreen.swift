import SwiftUI

/// A tab's placeholder until its feature lands: one icon and one short line,
/// following the "ver, não ler" rule of keeping text to a minimum.
struct EmptyStateScreen: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hcBackground.ignoresSafeArea()
                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                        .foregroundStyle(Color.hcInk)
                } description: {
                    Text(message)
                        .foregroundStyle(Color.hcSecondaryInk)
                }
            }
            .navigationTitle(title)
        }
    }
}
