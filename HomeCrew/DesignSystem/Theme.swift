import SwiftUI
import UIKit

/// Design tokens for the MomFlow look: calm and legible. Cream ground, white cards with a hairline, one dark
/// green for actions and selection, a pastel per person, rose only for illness, serif titles.
/// Every screen reads colours, type, radii and spacing from here.
enum Theme {
    enum Palette {
        static let background = UIColor(light: 0xF7F5F0, dark: 0x121614)
        static let card = UIColor(light: 0xFFFFFF, dark: 0x1C2220)
        /// Pale chip behind icons and finished things.
        static let muted = UIColor(light: 0xF0EEE8, dark: 0x262D2A)
        static let ink = UIColor(light: 0x18231F, dark: 0xF2F1EC)
        static let secondaryInk = UIColor(light: 0x78817D, dark: 0xA3ABA7)
        static let separator = UIColor(light: 0xE7E5DF, dark: 0x2E3532)
        /// The one strong colour: primary buttons, selection, the tab you are on.
        static let accent = UIColor(light: 0x175C49, dark: 0x6CC2A3)
        static let accentSoft = UIColor(light: 0xDCEBE4, dark: 0x1F3A31)
        /// Highlight on green surfaces: "now", "done".
        static let lime = UIColor(light: 0xDCEBE4, dark: 0xDCEBE4)
        /// Illness only; never used for ordinary actions.
        static let warning = UIColor(light: 0xB8475C, dark: 0xE88A9B)
        static let warningSoft = UIColor(light: 0xF5DFE4, dark: 0x3D2228)
        /// Strong surfaces (the next thing, done marks) stay dark green in both appearances.
        static let night = UIColor(hex: 0x175C49)

        /// Colours a family member can pick, as (initial colour, circle fill) pairs: a pastel fill, a deep initial.
        static let members: [(foreground: UIColor, soft: UIColor)] = [
            (UIColor(hex: 0x175C49), UIColor(hex: 0xDCEBE4)),
            (UIColor(hex: 0xA0485A), UIColor(hex: 0xF5DFE4)),
            (UIColor(hex: 0x3B6A99), UIColor(hex: 0xDFEAF5)),
            (UIColor(hex: 0x8F6229), UIColor(hex: 0xF3E5D0)),
            (UIColor(hex: 0x6B55A0), UIColor(hex: 0xE8E2F3)),
            (UIColor(hex: 0x2C7A80), UIColor(hex: 0xD7EEEF)),
        ]
    }

    /// Georgia for titles, the system font for everything else; both scale with Dynamic Type.
    enum Typography {
        static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
            Font.custom("Georgia", size: size, relativeTo: style)
        }

        /// The look is calm, so the heaviest weights are softened to bold.
        static func text(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .body) -> Font {
            let calm: Font.Weight = (weight == .heavy || weight == .black) ? .bold : weight
            let metrics = UIFontMetrics(forTextStyle: style.uiTextStyle)
            return Font.system(size: metrics.scaledValue(for: size), weight: calm)
        }

        static let screenTitle = display(29)
        static let sectionTitle = text(17, weight: .bold, relativeTo: .headline)
        static let cardTitle = text(15, weight: .semibold, relativeTo: .headline)
        static let body = text(15, weight: .regular)
        static let caption = text(13, weight: .regular, relativeTo: .footnote)
        /// Small capitals above a title, such as the date.
        static let overline = text(12, weight: .bold, relativeTo: .caption)
        /// Big glyph used where a picture replaces a sentence.
        static let heroIcon = Font.system(size: 48, weight: .light)
    }

    enum Radius {
        static let hero: CGFloat = 22
        static let card: CGFloat = 18
        static let control: CGFloat = 12
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 18
    }

    /// Smallest tap target allowed anywhere in the app.
    static let minimumTapTarget: CGFloat = 44
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension View {
    /// A white card with a hairline and a soft shadow, the MomFlow building block.
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hcCard, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Color.hcSeparator, lineWidth: 1) }
            .shadow(color: Color(UIColor(hex: 0x18231F)).opacity(0.06), radius: 14, y: 6)
    }
}

extension Color {
    static let hcBackground = Color(Theme.Palette.background)
    static let hcCard = Color(Theme.Palette.card)
    static let hcMuted = Color(Theme.Palette.muted)
    static let hcInk = Color(Theme.Palette.ink)
    static let hcSecondaryInk = Color(Theme.Palette.secondaryInk)
    static let hcSeparator = Color(Theme.Palette.separator)
    static let hcAccent = Color(Theme.Palette.accent)
    static let hcAccentSoft = Color(Theme.Palette.accentSoft)
    static let hcLime = Color(Theme.Palette.lime)
    static let hcWarning = Color(Theme.Palette.warning)
    static let hcWarningSoft = Color(Theme.Palette.warningSoft)
    static let hcNight = Color(Theme.Palette.night)
}

extension UIColor {
    /// A colour that switches between two hex values with the system appearance.
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
