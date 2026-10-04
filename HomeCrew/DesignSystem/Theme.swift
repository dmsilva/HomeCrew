import SwiftUI
import UIKit

/// Design tokens for Direção A · Clara: the native iOS look picked for the MVP.
/// Every screen reads colours, type, radii and spacing from here, never from literals.
enum Theme {
    enum Palette {
        static let background = UIColor(light: 0xF2F2F7, dark: 0x000000)
        static let card = UIColor(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let ink = UIColor(light: 0x111114, dark: 0xF2F2F7)
        static let secondaryInk = UIColor(light: 0x5E5E6A, dark: 0xA1A1AA)
        static let separator = UIColor(light: 0xE4E4EB, dark: 0x2C2C30)
        static let accent = UIColor(light: 0x2F55D4, dark: 0x7A95FF)
        static let accentSoft = UIColor(light: 0xE7ECFB, dark: 0x1B2547)
        /// Health only; never used for ordinary actions.
        static let warning = UIColor(light: 0xB4380B, dark: 0xFF8A5C)
        static let warningSoft = UIColor(light: 0xFCEBE3, dark: 0x3A2119)

        /// Colours a family member can pick, as (foreground, soft background) pairs.
        static let members: [(foreground: UIColor, soft: UIColor)] = [
            (accent, accentSoft),
            (UIColor(light: 0xA3367F, dark: 0xF2A7D8), UIColor(light: 0xF7E6F1, dark: 0x3A1F33)),
            (UIColor(light: 0x0F7B6C, dark: 0x6FD9C6), UIColor(light: 0xDDF2EE, dark: 0x163330)),
            (UIColor(light: 0x8A5A00, dark: 0xFFC870), UIColor(light: 0xFBF0D9, dark: 0x3A2D16)),
        ]
    }

    /// Text styles, all built on Dynamic Type so they scale with the user's setting.
    enum Typography {
        static let screenTitle = Font.largeTitle.weight(.bold)
        static let cardTitle = Font.headline
        static let body = Font.body
        static let caption = Font.footnote
        /// Big glyph used where a picture replaces a sentence.
        static let heroIcon = Font.system(size: 56, weight: .regular)
    }

    enum Radius {
        static let card: CGFloat = 18
        static let control: CGFloat = 12
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }

    /// Smallest tap target allowed anywhere in the app.
    static let minimumTapTarget: CGFloat = 44
}

extension Color {
    static let hcBackground = Color(Theme.Palette.background)
    static let hcCard = Color(Theme.Palette.card)
    static let hcInk = Color(Theme.Palette.ink)
    static let hcSecondaryInk = Color(Theme.Palette.secondaryInk)
    static let hcSeparator = Color(Theme.Palette.separator)
    static let hcAccent = Color(Theme.Palette.accent)
    static let hcAccentSoft = Color(Theme.Palette.accentSoft)
    static let hcWarning = Color(Theme.Palette.warning)
    static let hcWarningSoft = Color(Theme.Palette.warningSoft)
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
