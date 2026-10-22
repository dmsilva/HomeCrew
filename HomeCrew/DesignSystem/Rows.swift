import SwiftUI

/// A section title on the cream background, with an optional detail on the right.
struct SectionHeader<Detail: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Color.hcInk)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            detail
                .font(Theme.Typography.caption)
                .foregroundStyle(Color.hcSecondaryInk)
        }
    }
}

extension SectionHeader where Detail == EmptyView {
    init(title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

/// A short label on a soft colour, such as a person's name.
struct Pill: View {
    let text: Text
    let foreground: Color
    let background: Color

    init(_ key: LocalizedStringKey, foreground: Color, background: Color) {
        self.text = Text(key)
        self.foreground = foreground
        self.background = background
    }

    init(verbatim: String, foreground: Color, background: Color) {
        self.text = Text(verbatim: verbatim)
        self.foreground = foreground
        self.background = background
    }

    var body: some View {
        text
            .font(Theme.Typography.text(11, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

/// The hairline between rows inside a card.
struct RowDivider: View {
    var inset: CGFloat = 14

    var body: some View {
        Color.hcSeparator
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The small arrow at the end of a row that opens something.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.hcSecondaryInk)
            .accessibilityHidden(true)
    }
}
