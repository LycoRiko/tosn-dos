import XCTest

/// The spine of the app, not its surface: open, add one task, see it land.
/// Kept this short on purpose — a UI test with ten setup taps rots within a week.
final class SmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddingATaskFromQuickAdd() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let field = app.textFields["today.quickAdd"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "quick add never appeared")

        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "no keyboard")
        field.typeText("Smoke test")

        let add = app.buttons["Add task"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the add button never showed up")
        add.tap()

        // The new row can sit below the keyboard, outside the accessibility
        // snapshot. Filtering by its title brings it into view without scrolling.
        let filter = app.searchFields["Search tasks"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "the list search field is missing")
        filter.tap()
        filter.typeText("Smoke")

        XCTAssertTrue(
            app.staticTexts["Smoke test"].waitForExistence(timeout: 5),
            "the new task did not show up in the list"
        )
    }

    func testSearchIsReachableFromBrowse() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.buttons["Browse"].firstMatch.tap()

        let search = app.buttons["browse.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the Browse search entry is missing")

        search.tap()

        // The sheet's field is a search field on iOS and a text field on the Mac.
        let focused = app.searchFields.firstMatch.exists
            ? app.searchFields.firstMatch
            : app.textFields.firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 5), "the search sheet did not open")
    }
}
