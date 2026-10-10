import XCTest

/// Pictures of a bot's own name and title (#315) on the iPhone: the card's header after a name
/// and a title are saved, and the Model tab's Home section with Rename bot… on a bot that is
/// not the default. Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set (the mock gateway).
final class BotNamesShotsUITests: XCTestCase {
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

    private func launch(url: String, token: String) {
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-colorSchemePreference", "light"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-colorSchemePreference", "light"]
        }
        app.launch()
    }

    private func text(_ fragment: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment))
    }
    private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func becomesHittable(_ e: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if e.exists, e.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return e.exists && e.isHittable
    }

    /// A fresh chat with a reply that mentions @work, so the other bot's card is a tap away.
    private func openChatWithMentions() {
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("mention hi")
        if let send = app.buttons.matching(identifier: "composer.send").allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { send.tap() }
        XCTAssertTrue(text("for the go").firstMatch.waitForExistence(timeout: 30), "the reply with mentions did not arrive")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    func testNameAndTitleAndRenameRow() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = true
        launch(url: url, token: token)
        openChatWithMentions()

        // 1. The chat's bot: its card, the header as the way to the name and title editor.
        let pill = app.buttons["chat.titlePill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "no title pill")
        pill.tap()
        let header = any("profile.header")
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the card's header did not show")
        // The header is one accessibility element (its action opens the sheet); a touch has
        // to land on the name button, which is the card's top part.
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
        let name = any("botName.name")
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the name sheet did not open from the header")
        name.tap()
        name.typeText("Atlas")
        let title = any("botName.title")
        title.tap()
        title.typeText("Ops on the workshop host")
        let save = app.buttons["botName.save"].firstMatch
        XCTAssertTrue(becomesHittable(save), "no Save on the name sheet")
        save.tap()
        XCTAssertTrue(text("Ops on the workshop host").firstMatch.waitForExistence(timeout: 10), "the saved title is not under the name")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("315-1-name-and-title")
        app.buttons["profile.close"].firstMatch.tap()

        // 2. The other bot (not the default): its card from the reply's @work, Model › Home, Rename bot….
        let link = app.links.matching(NSPredicate(format: "label == '@work'")).firstMatch
        XCTAssertTrue(becomesHittable(link, timeout: 10), "no @work link in the reply")
        link.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the other bot's card did not open")
        let modelTab = any("profile.tab.model")
        XCTAssertTrue(becomesHittable(modelTab, timeout: 10), "no Model tab")
        modelTab.tap()
        let rename = app.buttons["profile.renameBot"].firstMatch
        for _ in 0..<8 where !(rename.exists && rename.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(rename.exists, "no Rename bot… row on the work bot's Model tab")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("315-2-rename-row")
    }
}
