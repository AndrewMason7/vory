import XCTest

/// Pictures of the bot while an approval waits (the exclamation) and while a reply writes (the
/// bubbles on the header), at full resolution, for the planner and Matt (#304). Skipped unless
/// HERMES_E2E_URL / HERMES_E2E_TOKEN are set (the mock gateway).
final class BotApprovalShotUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
        print("CHAT-SHOT \(d.appendingPathComponent("\(name).png").path)")
    }

    private func launch(url: String, token: String, scheme: String) {
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-colorSchemePreference", scheme, "-chat.showBots", "YES"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-colorSchemePreference", scheme, "-chat.showBots", "YES"]
        }
        app.launch()
    }

    private func text(_ fragment: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
    }

    private func send(_ prompt: String) {
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText(prompt)
        if let send = app.buttons.matching(identifier: "composer.send").allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { send.tap() }
    }

    private func settle(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func hideKeyboard() {
        if app.keyboards.buttons["Hide keyboard"].firstMatch.exists { app.keyboards.buttons["Hide keyboard"].firstMatch.tap() }
    }

    func testApprovalAndWritingPictures() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        for scheme in ["light", "dark"] {
            launch(url: url, token: token, scheme: scheme)
            let newChat = app.buttons["chats.new"].firstMatch
            XCTAssertTrue(newChat.waitForExistence(timeout: 40))
            wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
            newChat.tap()
            XCTAssertTrue(app.buttons["chat.titlePill"].firstMatch.waitForExistence(timeout: 30), "no title pill")
            // Writing: a long reply streams for a few seconds.
            send("marathon 1")
            settle(2.0)
            shot("motion-\(scheme)-1-early-turn")
            settle(3.0)
            shot("motion-\(scheme)-2-mid-turn")
            _ = text("tok/s").firstMatch.waitForExistence(timeout: 60)
            settle(2.5)
            hideKeyboard()
            settle(1)
            shot("motion-\(scheme)-3-rest-after-turn")
            // An approval: the exclamation, the eyes gone.
            send("card")
            XCTAssertTrue(text("Approval needed").firstMatch.waitForExistence(timeout: 30), "no approval card")
            settle(1.5)
            hideKeyboard()
            settle(1)
            shot("motion-\(scheme)-4-approval")
            app.terminate()
        }
    }
}
