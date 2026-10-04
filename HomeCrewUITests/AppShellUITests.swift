import XCTest

final class AppShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAllFourTabsAreReachable() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt-PT)", "-AppleLocale", "pt_PT"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        for title in ["Hoje", "Agenda", "Família", "Saúde"] {
            let button = tabBar.buttons[title]
            XCTAssertTrue(button.exists, "Tab \(title) is missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Screen \(title) did not open")
        }
    }
}
