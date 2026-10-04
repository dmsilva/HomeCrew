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
        XCTAssertTrue(tab("Hoje").waitForExistence(timeout: 5))
    }

    func testAllFourTabsAreReachable() {
        createFamily()
        XCTAssertTrue(tab("Hoje").waitForExistence(timeout: 10))

        for title in ["Agenda", "Família", "Saúde"] {
            let button = tab(title)
            XCTAssertTrue(button.exists, "Tab \(title) is missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Screen \(title) did not open")
        }
        tab("Hoje").tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-header"].waitForExistence(timeout: 5), "Today did not open")
    }

    func testAddingAMemberShowsTheirCard() {
        createFamily()
        tab("Família").tap()

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
        tab("Agenda").tap()
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
        tab("Agenda").tap()

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
        tab("Agenda").tap()
        app.buttons["Tarefas"].tap()
        app.buttons["Nova tarefa"].tap()
        let title = app.textFields["Tarefa"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Lixo")
        app.buttons["Guardar"].tap()

        tab("Hoje").tap()
        let chore = app.buttons["chore-Lixo"]
        XCTAssertTrue(chore.waitForExistence(timeout: 5))
        chore.tap()
        let done = expectation(for: NSPredicate(format: "value == %@", "Feita"), evaluatedWith: chore)
        wait(for: [done], timeout: 5)
    }

    func testAllergiesShowOnTheHealthCard() {
        createFamily()
        tab("Família").tap()
        app.buttons["Adicionar membro"].tap()
        let name = app.textFields["Nome"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rita")
        app.buttons["Guardar"].tap()

        tab("Saúde").tap()
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

    func testAnIllnessEpisodeShowsOnToday() {
        createFamily()
        tab("Família").tap()
        app.buttons["Adicionar membro"].tap()
        let name = app.textFields["Nome"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rita")
        app.buttons["Guardar"].tap()

        tab("Saúde").tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rita")).firstMatch.tap()
        let open = app.buttons["Abrir episódio"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let episode = app.descendants(matching: .any).matching(identifier: "active-episode").firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        episode.tap()
        let cough = app.buttons["symptom-0"]
        XCTAssertTrue(cough.waitForExistence(timeout: 5))
        cough.tap()

        tab("Hoje").tap()
        XCTAssertTrue(app.buttons["Rita doente"].waitForExistence(timeout: 5))
    }

    func testAddingAMedicationAndGivingADose() {
        createFamily()
        tab("Família").tap()
        app.buttons["Adicionar membro"].tap()
        let name = app.textFields["Nome"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rita")
        app.buttons["Guardar"].tap()

        tab("Saúde").tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rita")).firstMatch.tap()
        app.buttons["Abrir episódio"].tap()
        let episode = app.descendants(matching: .any).matching(identifier: "active-episode").firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 5))
        episode.tap()

        let add = app.buttons["Adicionar medicamento"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let medicine = app.textFields["medication-name"]
        XCTAssertTrue(medicine.waitForExistence(timeout: 5))
        medicine.tap()
        medicine.typeText("Bru")
        app.buttons["Brufen"].tap()
        app.buttons["Guardar"].tap()

        XCTAssertTrue(app.staticTexts["Brufen"].waitForExistence(timeout: 5))
        let give = app.buttons["Dei agora"].firstMatch
        XCTAssertTrue(give.exists)
        give.tap()
        XCTAssertTrue(app.images["hourglass"].waitForExistence(timeout: 5))
    }

    private func createFamily() {
        let create = app.buttons["Criar família"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "First launch should offer to create a family")
        create.tap()
        // The tab bar is there before the cover finishes sliding away; tapping a tab too early misses.
        XCTAssertTrue(tab("Hoje").waitForExistence(timeout: 10))
        let settled = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: create)
        wait(for: [settled], timeout: 10)
    }

    /// The app draws its own tab bar, so tabs are found by identifier rather than through `tabBars`.
    private func tab(_ title: String) -> XCUIElement {
        let ids = ["Hoje": "tab-today", "Agenda": "tab-agenda", "Família": "tab-family", "Saúde": "tab-health"]
        return app.buttons[ids[title] ?? title]
    }
}
