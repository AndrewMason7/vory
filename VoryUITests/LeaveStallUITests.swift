import XCTest

/// #422: the main thread stalled 0.5 to 0.6 s at every press of the home button, at rest too. Each test leaves and comes
/// back five times from one screen, with the app's stall log at 50 ms (`-vory-perf-stall-ms`); every leave and return
/// prints a C422 line so the host can put each stall on the leave or the return. Skipped unless HERMES_E2E_URL /
/// HERMES_E2E_TOKEN are set; HERMES_E2E_BUNDLE picks the copy (the demo).
@MainActor
final class LeaveStallUITests: XCTestCase {
    private var app: XCUIApplication!

    private func mark(_ s: String) { print(String(format: "C422 %.2f %@", Date().timeIntervalSince1970, s)) }
    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

    private func launch(tab: String) throws {
        let e = ProcessInfo.processInfo.environment
        guard let url = e["HERMES_E2E_URL"], let token = e["HERMES_E2E_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set")
        }
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: e["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo")
        // HERMES_E2E_422_ARGS: more launch arguments, space-separated (-vory-no-defaults-probe, say).
        let more = (e["HERMES_E2E_422_ARGS"] ?? "").split(separator: " ").map(String.init)
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", tab,
                               "-vory-perf-stall-ms", "50"] + more
        app.launch()
        // A release build has no demo copy: HERMES_E2E_422_ONBOARD=1 adds the mock as a gateway through onboarding.
        if e["HERMES_E2E_422_ONBOARD"] == "1" { onboard(url: url, token: token) }
    }

    /// Onboarding to the gateway at `url` with a session token, as a person would (HermesRemoteUITests' path), unless a
    /// gateway is already saved.
    private func onboard(url: String, token: String) {
        let start = app.buttons["onboarding.getStarted"].firstMatch
        let skip = app.buttons["onboarding.skip"].firstMatch
        let add = app.buttons["onboarding.addGateway"].firstMatch
        let chats = app.buttons["chats.new"].firstMatch
        let deadline = Date().addingTimeInterval(45)
        while !start.exists && !skip.exists && !add.exists && !chats.exists && Date() < deadline { pause(0.5) }
        if chats.exists { mark("ONBOARD already saved"); return }
        if start.exists { start.tap() }
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        XCTAssertTrue(add.waitForExistence(timeout: 15), "no Add Gateway")
        add.tap()
        let name = app.textFields["gateway.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "no gateway form")
        name.tap(); name.typeText("Workshop")
        let field = app.textFields["gateway.url"].firstMatch
        field.tap(); field.typeText(url)
        let tokenField = app.secureTextFields["gateway.sessionToken"].firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5), "no token field")
        tokenField.tap(); tokenField.typeText(token)
        app.buttons["gateway.test"].firstMatch.tap()
        let save = app.buttons["gateway.save"].firstMatch
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save)], timeout: 60)
        save.tap()
        XCTAssertTrue(chats.waitForExistence(timeout: 40), "not on the chat list after onboarding")
        mark("ONBOARD done")
    }

    /// Five leaves and returns, three seconds apart, with nothing touched in between.
    private func cycles(_ name: String) {
        pause(4)
        for i in 1...5 {
            mark("LEAVE \(name) \(i)")
            XCUIDevice.shared.press(.home)
            pause(3)
            mark("BACK \(name) \(i)")
            app.activate()
            pause(3)
        }
        mark("DONE \(name)")
    }

    func testLeavingFromTheChatList() throws {
        try launch(tab: "chats")
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 40), "no chat list")
        cycles("chats")
    }

    func testLeavingFromALongChat() throws {
        try launch(tab: "chats")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Disk cleanup")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 40), "no chat list")
        row.tap()
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 30) || app.buttons["Deny"].exists, "the chat did not open")
        cycles("chat")
    }

    func testLeavingFromHome() throws {
        try launch(tab: "dashboard")
        pause(3)
        cycles("home")
    }
}
