import XCTest

final class BalabolkaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGenerateHistoryAndRelaunchRestore() throws {
        let app = makeApp(resetState: true)
        app.launch()

        XCTAssertTrue(app.buttons["composer.generate"].waitForExistence(timeout: 5))
        app.buttons["preset.sarcasm"].tap()
        app.buttons["composer.generate"].tap()

        XCTAssertTrue(app.otherElements["preview.card"].waitForExistence(timeout: 15))
        app.tabBars.buttons["История"].tap()
        XCTAssertTrue(app.navigationBars["История"].waitForExistence(timeout: 5))
        let firstRow = app.buttons["history.row"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()
        XCTAssertTrue(app.buttons["detail.reopen"].waitForExistence(timeout: 5))

        app.terminate()

        let relaunched = makeApp(resetState: false)
        relaunched.launch()
        relaunched.tabBars.buttons["История"].tap()
        XCTAssertTrue(relaunched.navigationBars["История"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunched.buttons["history.row"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrimaryFlowPassesAccessibilityAudit() throws {
        let app = makeApp(resetState: true)
        app.launch()

        XCTAssertTrue(app.buttons["composer.generate"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()

        app.tabBars.buttons["История"].tap()
        XCTAssertTrue(app.navigationBars["История"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    private func makeApp(resetState: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BALABOLKA_UI_TEST_MODE"] = "1"
        app.launchEnvironment["BALABOLKA_DISABLE_INLINE_AUTOPLAY"] = "1"
        if resetState {
            app.launchEnvironment["BALABOLKA_RESET_STATE"] = "1"
        }
        return app
    }
}
