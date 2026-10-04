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
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        snap("01-hoje")

        for (index, tab) in ["agenda", "family", "health"].enumerated() {
            let button = app.buttons["tab-\(tab)"]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            snap(String(format: "%02d-%@", index + 2, tab))
            if tab == "agenda", app.buttons["Tarefas"].waitForExistence(timeout: 5) {
                app.buttons["Tarefas"].tap()
                snap("02b-tarefas")
                app.buttons["Atividades"].tap()
            }
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

    func testCaptureEditors() {
        XCTAssertTrue(app.buttons["tab-today"].waitForExistence(timeout: 15))
        for (kind, name) in [("Atividade", "07-nova-atividade"), ("Tarefa", "08-nova-tarefa")] {
            let plus = app.buttons["tab-create"]
            guard plus.waitForExistence(timeout: 5) else { return }
            plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let item = app.buttons[kind]
            guard item.waitForExistence(timeout: 5) else { continue }
            item.tap()
            snap(name)
            app.buttons["Cancelar"].tap()
        }
        app.buttons["tab-family"].tap()
        let daniel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Daniel")).firstMatch
        if daniel.waitForExistence(timeout: 5) {
            daniel.tap()
            snap("09-editar-membro")
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
