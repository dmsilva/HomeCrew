import SwiftUI
import UIKit

/// Design tokens for Direção E: see, don't read. Violet and lime on a pale lilac ground, coral only for illness,
/// people as colour circles with an initial. Every screen reads colours, type, radii and spacing from here.
enum Theme {
    enum Palette {
        static let background = UIColor(light: 0xF7F5FF, dark: 0x0E0C1F)
        static let card = UIColor(light: 0xFFFFFF, dark: 0x1C1838)
        /// Pale chip behind icons and finished things.
        static let muted = UIColor(light: 0xECE9F8, dark: 0x2A2550)
        static let ink = UIColor(light: 0x14112B, dark: 0xF7F5FF)
        static let secondaryInk = UIColor(light: 0x4A4566, dark: 0xB8B2D9)
        static let separator = UIColor(light: 0xDCD8EE, dark: 0x2E2A4D)
        /// The one strong colour: the day card, primary buttons, selection.
        static let accent = UIColor(light: 0x4B2BFF, dark: 0x7B63FF)
        static let accentSoft = UIColor(light: 0xE6E0FF, dark: 0x251C5C)
        /// Highlight on dark and violet surfaces: "now", "done", the selected tab.
        static let lime = UIColor(hex: 0xD7FF3A)
        /// Illness only; never used for ordinary actions.
        static let warning = UIColor(light: 0xFF5A3C, dark: 0xFF7A60)
        static let warningSoft = UIColor(light: 0xFFE1DA, dark: 0x4A1E16)
        /// Dark surfaces (tab bar, next activity) stay dark in both appearances.
        static let night = UIColor(hex: 0x14112B)

        /// Colours a family member can pick, as (initial colour, circle fill) pairs. Fills are vivid, initials ink.
        static let members: [(foreground: UIColor, soft: UIColor)] = [
            (UIColor(hex: 0x14112B), UIColor(hex: 0xD7FF3A)),
            (UIColor(hex: 0x14112B), UIColor(hex: 0xFF8AD8)),
            (UIColor(hex: 0x14112B), UIColor(hex: 0x7FD4FF)),
            (UIColor(hex: 0x14112B), UIColor(hex: 0xFFC53D)),
            (UIColor(hex: 0x14112B), UIColor(hex: 0x6EE7B7)),
            (UIColor(hex: 0x14112B), UIColor(hex: 0xB9A6FF)),
        ]
    }

    /// Syne for the few big numbers and titles, Figtree for everything else; both scale with Dynamic Type.
    /// If the bundled fonts are missing, SwiftUI falls back to the system font.
    enum Typography {
        static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
            Font.custom("Syne", size: size, relativeTo: style).weight(.heavy)
        }

        static func text(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
            Font.custom("Figtree", size: size, relativeTo: style).weight(weight)
        }

        static let screenTitle = display(34)
        static let cardTitle = text(17, weight: .heavy, relativeTo: .headline)
        static let body = text(16, weight: .medium)
        static let caption = text(13, weight: .bold, relativeTo: .footnote)
        /// Big glyph used where a picture replaces a sentence.
        static let heroIcon = Font.system(size: 56, weight: .regular)
    }

    enum Radius {
        static let hero: CGFloat = 32
        static let card: CGFloat = 22
        static let control: CGFloat = 14
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
