import XCTest

/// Pin only where the gateway keeps pins (#406). A Hermes from before it kept them lists chats
/// without "pinned" and refuses a pin as having nothing to update: the app offers no Pin there, in
/// the swipe or the row's menu. A pin refused all the same says why in an alert (the list's red
/// line was cleared by the next refresh), and Pin is not offered again.
///
/// Each test needs the mock in its mode, named in HERMES_E2E_ARGS: "no-pins" with the mock's
/// `--no-pins`, "refuse-pins" with its `--refuse-pins`; skipped otherwise. HERMES_E2E_URL /
/// HERMES_E2E_TOKEN as usual; HERMES_E2E_BUNDLE=com.vorantx.vory.demo drives the demo copy.
@MainActor
final class PinSupportUITests: XCTestCase {
    private var app: XCUIApplication!
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
    }

    private func launch(mode: String) throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        guard (e["HERMES_E2E_ARGS"] ?? "").contains(mode) else { throw XCTSkip("the mock is not in its \(mode) mode") }
        continueAfterFailure = false
        if let bundle = e["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats", "-colorSchemePreference", "light"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-launchTab", "chats", "-colorSchemePreference", "light"]
        }
        app.launch()
        XCTAssertTrue(row("Rewrite the nightly export job").waitForExistence(timeout: 40), "no chat rows")
        pause(3)
    }

    private func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).allElementsBoundByIndex.first { $0.isHittable }
            ?? app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
    }

    /// The row's leading swipe: its actions, as labels, then closed again.
    private func swipeActions(_ title: String) -> [String] {
        row(title).swipeRight()
        XCTAssertTrue(app.buttons["Archive"].firstMatch.waitForExistence(timeout: 5), "the swipe did not open")
        let found = ["Pin", "Unpin", "Archive"].filter { app.buttons[$0].firstMatch.exists }
        shot("pin-support-swipe")
        row(title).tap()
        pause(1)
        return found
    }

    /// The row's long-press menu: its items, as labels, then dismissed.
    private func menuItems(_ title: String) -> [String] {
        row(title).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Open"].firstMatch.waitForExistence(timeout: 5), "no menu")
        let found = ["Open", "Pin", "Unpin", "Archive", "Select"].filter { app.buttons[$0].firstMatch.exists }
        shot("pin-support-menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        pause(1)
        return found
    }

    func testNoPinWhereTheGatewayKeepsNone() throws {
        try launch(mode: "no-pins")
        let swipe = swipeActions("Weekly dependency audit")
        XCTAssertFalse(swipe.contains("Pin") || swipe.contains("Unpin"), "the swipe offers a pin the gateway cannot keep: \(swipe)")
        XCTAssertTrue(swipe.contains("Archive"), "the swipe lost Archive: \(swipe)")
        let menu = menuItems("Weekly dependency audit")
        XCTAssertFalse(menu.contains("Pin") || menu.contains("Unpin"), "the menu offers a pin the gateway cannot keep: \(menu)")
        XCTAssertTrue(menu.contains("Archive"), "the menu lost Archive: \(menu)")
        // The audit on Chats, as it is shown on such a gateway.
        var issues = 0
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
            issues += 1
            print("CHATS-AUDIT '\(issue.compactDescription)' label '\(issue.element?.label ?? "")' id '\(issue.element?.identifier ?? "")'")
            return true
        }
        print("CHATS-AUDIT done, \(issues) issues")
    }

    func testARefusedPinSaysWhyOnceAndIsNotOfferedAgain() throws {
        try launch(mode: "refuse-pins")
        // The rows say "pinned", so Pin is offered at first.
        row("Weekly dependency audit").swipeRight()
        let pin = app.buttons["Pin"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no Pin on a gateway whose rows carry it")
        pin.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "a refused pin said nothing")
        XCTAssertEqual(alert.label, "Pinning is not available")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'too old to pin chats'")).firstMatch.exists, "the alert does not say why")
        shot("pin-support-refused")
        alert.buttons["OK"].tap()
        pause(1.5)
        // Put back, and no Pin since: not in the swipe, not in the menu.
        let swipe = swipeActions("Weekly dependency audit")
        XCTAssertFalse(swipe.contains("Pin"), "Pin offered again after the gateway refused it: \(swipe)")
        let menu = menuItems("Weekly dependency audit")
        XCTAssertFalse(menu.contains("Pin"), "Pin in the menu after the gateway refused it: \(menu)")
        XCTAssertFalse(app.alerts.firstMatch.exists, "the alert came back")
    }
}
