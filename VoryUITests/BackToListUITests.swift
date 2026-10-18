import XCTest

/// On one column (a phone), Back from a chat lands on the list, never on an empty detail
/// column (the "No chat selected" placeholder with a back button, which the collapsed split
/// view left in front). Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set.
@MainActor
final class BackToListUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func launch(url: String, token: String) {
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-launchTab", "chats"]
        }
        app.launch()
    }

    private func settle(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    func testBackFromAChatShowsTheList() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        launch(url: url, token: token)
        let frame = app.windows.firstMatch.frame
        guard frame.width < 700 || frame.height > frame.width else { throw XCTSkip("a wide window keeps the list beside the chat") }
        let rows = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Disk cleanup'"))
        let deadline = Date().addingTimeInterval(40)
        var row: XCUIElement?
        while row == nil, Date() < deadline { row = rows.allElementsBoundByIndex.first { $0.exists && $0.isHittable }; if row == nil { settle(0.3) } }
        try XCTUnwrap(row, "the seeded chat is not listed").tap()
        let back = app.buttons["chat.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 15), "the chat did not open")
        settle(1)
        back.tap()
        settle(1.5)
        XCTAssertFalse(app.staticTexts["No chat selected"].firstMatch.exists, "Back landed on the empty detail column")
        let again = rows.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
        XCTAssertNotNil(again, "the list is not back after Back")
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.isHittable, "the tab bar is not back with the list")
    }
}
