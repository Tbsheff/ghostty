import XCTest

final class GhosttyUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func mainWindow(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5), file: file, line: line)
        return window
    }

    private func toggleFileBrowser(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        let item = viewMenu.menus.menuItems["Toggle File Browser"]
        XCTAssertTrue(item.waitForExistence(timeout: 2), file: file, line: line)
        item.click()
    }

    private func toggleMarkdown(_ app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        let item = viewMenu.menus.menuItems["Toggle Markdown Preview"]
        XCTAssertTrue(item.waitForExistence(timeout: 2), file: file, line: line)
        item.click()
    }

    func testToggleFileBrowserPanel() {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        let window = mainWindow(app)
        window.click()

        let panel = app.otherElements["fileBrowser.panel"]

        toggleFileBrowser(app)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        toggleFileBrowser(app)
        XCTAssertFalse(panel.waitForExistence(timeout: 1))
    }

    func testToggleMarkdownPanelKeepsWidth() {
        let app = XCUIApplication()
        app.launch()
        app.activate()
        let window = mainWindow(app)
        window.click()

        let panel = app.otherElements["markdown.panel"]

        toggleMarkdown(app)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        let initialWidth = panel.frame.width

        toggleMarkdown(app)
        XCTAssertFalse(panel.waitForExistence(timeout: 1))

        toggleMarkdown(app)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.frame.width, initialWidth, accuracy: 2)
    }
}
