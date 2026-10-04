import XCTest

/// Walks the main screens with a demo family and keeps a screenshot of each, so CI shows what the app looks like.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-inMemoryStore", "-demoData", "-AppleLanguages", "(pt-PT)", "-AppleLocale", "pt_PT"]
        app.launch()
    }

    func testCaptureMainScreens() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        snap("01-hoje")

        for (index, title) in ["Agenda", "Família", "Saúde"].enumerated() {
            let tab = tabBar.buttons[title]
            guard tab.waitForExistence(timeout: 5) else { continue }
            tab.tap()
            snap(String(format: "%02d-%@", index + 2, title.lowercased()))
        }

        let leonor = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Leonor")).firstMatch
        if leonor.waitForExistence(timeout: 5) {
            leonor.tap()
            snap("05-saude-leonor")
            let episode = app.descendants(matching: .any).matching(identifier: "active-episode").firstMatch
            if episode.waitForExistence(timeout: 5) {
                episode.tap()
                snap("06-episodio")
            }
        }
    }

    private func snap(_ name: String) {
        // Let lists and charts settle before capturing.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
