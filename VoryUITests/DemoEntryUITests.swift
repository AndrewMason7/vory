import XCTest

/// Demo mode's way in and out (#392), on a device with no gateway: the first screen's "Try a demo" opens Vory on the
/// demo's bots and chats, Settings tags the gateway "Demo" and offers Leave demo, and leaving brings back the first
/// screen with nothing of the demo left. Runs on the demo copy (HERMES_E2E_BUNDLE), which keeps no gateway between
/// launches; skipped without it.
final class DemoEntryUITests: XCTestCase {
    private var app: XCUIApplication!

    private func text(_ fragment: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
    }

    func testTryADemoOpensTheDemoAndLeavingItGoesBack() throws {
        guard let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty else {
            throw XCTSkip("HERMES_E2E_BUNDLE not set")
        }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = ["-companionPromptShown", "YES"]
        app.launch()

        let tryDemo = app.buttons["onboarding.tryDemo"].firstMatch
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 30), "no Try a demo on the first screen")
        XCTAssertEqual(tryDemo.label, "Try a demo")
        tryDemo.tap()
        XCTAssertTrue(text("Packing list for the lake weekend").firstMatch.waitForExistence(timeout: 30), "the demo's chats did not load")

        let settings = app.buttons["tab.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(text("Vory demo").firstMatch.waitForExistence(timeout: 10), "Settings does not name the demo's gateway")
        XCTAssertTrue(app.staticTexts["Demo"].firstMatch.exists, "no Demo tag by the gateway's name")
        let leave = app.buttons["settings.leaveDemo"].firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: 10), "no Leave demo")
        XCTAssertTrue(app.buttons["settings.connectGateway"].firstMatch.exists, "no Connect your gateway")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "demo-settings"; shot.lifetime = .keepAlways; add(shot)
        leave.tap()

        XCTAssertTrue(app.buttons["onboarding.tryDemo"].firstMatch.waitForExistence(timeout: 30), "leaving the demo did not go back to the first screen")
        XCTAssertFalse(text("Packing list for the lake weekend").firstMatch.exists, "the demo's chats are still shown")
    }
}
