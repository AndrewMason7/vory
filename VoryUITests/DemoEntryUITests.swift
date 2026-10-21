import XCTest

/// Demo mode's way in and out (#392), on a device with no gateway: the tour's "Try a demo" (its last beat, #388) opens
/// Vory on the demo's bots and chats, Settings tags the gateway "Demo" and offers Leave demo, and leaving brings back the
/// tour with nothing of the demo left. Runs on the demo copy (HERMES_E2E_BUNDLE), which keeps no gateway between
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

        // Try a demo is on the tour's last beat (#388): Skip goes there.
        let skip = app.buttons["onboarding.skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "no tour on a device with no gateway")
        skip.tap()
        let tryDemo = app.buttons["onboarding.tryDemo"].firstMatch
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 10), "no Try a demo on the tour's last beat")
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

        XCTAssertTrue(app.buttons["onboarding.getStarted"].firstMatch.waitForExistence(timeout: 30), "leaving the demo did not go back to the tour")
        XCTAssertFalse(text("Packing list for the lake weekend").firstMatch.exists, "the demo's chats are still shown")
    }

    /// The demo offers no Companion (#494): neither the prompt nor Settings' card. Both used themselves up in the demo,
    /// and the person's own gateway, added after it, was never offered them. Started as if never offered.
    func testTheDemoOffersNoCompanion() throws {
        guard let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty else {
            throw XCTSkip("HERMES_E2E_BUNDLE not set")
        }
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: bundle)
        app.launchArguments = ["-companionPromptShown", "NO", "-notificationsSetupCardDone", "NO"]
        app.launch()
        let skip = app.buttons["onboarding.skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 30), "no tour on a device with no gateway")
        skip.tap()
        let tryDemo = app.buttons["onboarding.tryDemo"].firstMatch
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 10))
        tryDemo.tap()
        XCTAssertTrue(text("Packing list for the lake weekend").firstMatch.waitForExistence(timeout: 30), "the demo's chats did not load")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(text("Unlock Vory's full potential").firstMatch.exists, "the Companion prompt showed for the demo")
        XCTAssertFalse(text("The Companion is already here").firstMatch.exists, "the Companion prompt showed for the demo")

        let settings = app.buttons["tab.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(text("Vory demo").firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(text("Unlock Vory's full potential").firstMatch.exists, "Settings offered the Companion for the demo")
        app.buttons["settings.leaveDemo"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboarding.getStarted"].firstMatch.waitForExistence(timeout: 30))
    }
}
