import UIKit
import XCTest
@testable import HomeCrew

final class AppShellTests: XCTestCase {
    func testTabsAppearInTheAgreedOrder() {
        XCTAssertEqual(AppTab.allCases, [.today, .agenda, .family, .health])
    }

    func testEveryTabHasAnIcon() {
        for tab in AppTab.allCases {
            XCTAssertNotNil(UIImage(systemName: tab.systemImage), "Missing SF Symbol for \(tab)")
        }
    }

    func testRadiiMatchDirectionA() {
        XCTAssertEqual(Theme.Radius.card, 18)
        XCTAssertEqual(Theme.Radius.control, 12)
    }

    func testTapTargetIsAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(Theme.minimumTapTarget, 44)
    }

    func testPaletteAdaptsToDarkMode() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let adaptive: [UIColor] = [
            Theme.Palette.background, Theme.Palette.card, Theme.Palette.ink,
            Theme.Palette.accent, Theme.Palette.warning,
        ]
        for color in adaptive {
            XCTAssertNotEqual(color.resolvedColor(with: light), color.resolvedColor(with: dark))
        }
    }

    func testAccentIsTheDirectionABlueInLightMode() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(Theme.Palette.accent.resolvedColor(with: light), UIColor(hex: 0x2F55D4))
    }

    func testFourMemberColoursAreAvailable() {
        XCTAssertEqual(Theme.Palette.members.count, 4)
    }
}
