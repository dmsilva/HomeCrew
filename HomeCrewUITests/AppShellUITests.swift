import XCTest

final class AppShellUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-inMemoryStore", "-AppleLanguages", "(pt-PT)", "-AppleLocale", "pt_PT"]
        app.launch()
    }

    func testFirstLaunchAsksToCreateAFamily() {
        createFamily()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testAllFourTabsAreReachable() {
        createFamily()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        for title in ["Hoje", "Agenda", "Família", "Saúde"] {
            let button = tabBar.buttons[title]
            XCTAssertTrue(button.exists, "Tab \(title) is missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Screen \(title) did not open")
        }
    }

    func testAddingAMemberShowsTheirCard() {
        createFamily()
        app.tabBars.firstMatch.buttons["Família"].tap()

        let add = app.buttons["Adicionar membro"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let name = app.textFields["Nome"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rita")
        app.buttons["Guardar"].tap()

        // The card is a button, so its texts merge into the button's label.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rita")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    private func createFamily() {
        let create = app.buttons["Criar família"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "First launch should offer to create a family")
        create.tap()
    }
}
