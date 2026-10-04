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

    func testAddingADailyChoreAndTickingIt() {
        createFamily()
        app.tabBars.firstMatch.buttons["Agenda"].tap()
        app.buttons["Tarefas"].tap()

        let add = app.buttons["Nova tarefa"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let title = app.textFields["Tarefa"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Fazer a cama")
        app.buttons["Guardar"].tap()

        XCTAssertTrue(app.staticTexts["Fazer a cama"].waitForExistence(timeout: 5))
        app.buttons["Por fazer"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Feita"].waitForExistence(timeout: 5))
    }

    func testAddingAWeeklyActivityShowsItInTheWeek() {
        createFamily()
        app.tabBars.firstMatch.buttons["Agenda"].tap()

        let add = app.buttons["Nova atividade"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let title = app.textFields["Atividade"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Futebol")
        // Every day of the week, so it shows up whatever day the test runs.
        for weekday in 1...7 {
            app.buttons["weekday-\(weekday)"].tap()
        }
        app.buttons["Guardar"].tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Futebol")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testTickingAChoreFromToday() {
        createFamily()
        app.tabBars.firstMatch.buttons["Agenda"].tap()
        app.buttons["Tarefas"].tap()
        app.buttons["Nova tarefa"].tap()
        let title = app.textFields["Tarefa"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Lixo")
        app.buttons["Guardar"].tap()

        app.tabBars.firstMatch.buttons["Hoje"].tap()
        XCTAssertTrue(app.staticTexts["Lixo"].waitForExistence(timeout: 5))
        app.buttons["Por fazer"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Feita"].waitForExistence(timeout: 5))
    }

    func testAllergiesShowOnTheHealthCard() {
        createFamily()
        app.tabBars.firstMatch.buttons["Família"].tap()
        app.buttons["Adicionar membro"].tap()
        let name = app.textFields["Nome"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rita")
        app.buttons["Guardar"].tap()

        app.tabBars.firstMatch.buttons["Saúde"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rita")).firstMatch.tap()
        app.buttons["Editar"].tap()
        // A multi-line field shows up as a text view, so look it up by identifier.
        let allergies = app.descendants(matching: .any).matching(identifier: "allergies").firstMatch
        XCTAssertTrue(allergies.waitForExistence(timeout: 5))
        allergies.tap()
        allergies.typeText("Amendoim")
        app.buttons["Guardar"].tap()

        XCTAssertTrue(app.staticTexts["Amendoim"].waitForExistence(timeout: 5))
    }

    private func createFamily() {
        let create = app.buttons["Criar família"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "First launch should offer to create a family")
        create.tap()
    }
}
