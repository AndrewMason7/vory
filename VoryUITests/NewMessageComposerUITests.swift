import XCTest

/// The New Message sheet's composer (#27): the chat's own card on a draft. A file picked there goes
/// with the first message to one bot; to several bots a group chat starts with the words only, and
/// says so. The demo copy stages a PDF in the message (`-vory-test-stage-compose`), since the system
/// file picker cannot be driven.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set. HERMES_E2E_BUNDLE=
/// com.vorantx.vory.demo drives the demo copy, pointed at the gateway by launch argument.
@MainActor
final class NewMessageComposerUITests: XCTestCase {
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
    }

    private func hittable(_ query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let e = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return e }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// The sheet open, with the PDF staged once a bot is chosen.
    private func openSheet(url: String, token: String) throws {
        let e = ProcessInfo.processInfo.environment
        if let bundle = e["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-launchTab", "chats",
                                   "-vory-test-stage-compose", "brief.pdf"]
        } else {
            app = XCUIApplication()
            app.launchArguments = ["-launchTab", "chats", "-vory-test-stage-compose", "brief.pdf"]
        }
        app.launch()
        let compose = try XCTUnwrap(hittable(app.buttons.matching(identifier: "chats.new"), timeout: 40), "no compose circle")
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: compose)], timeout: 60)
        // Held, the compose circle opens New Message.
        compose.press(forDuration: 1.0)
        XCTAssertTrue(app.textFields["Bot name"].firstMatch.waitForExistence(timeout: 15), "New Message did not open")
    }

    private func choose(_ bot: String) throws {
        let card = try XCTUnwrap(hittable(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", bot)), timeout: 10), "no \(bot) to add")
        card.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    func testAFileGoesWithTheFirstMessageToOneBot() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        try openSheet(url: url, token: token)
        try choose("default")
        let staged = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "brief.pdf")).firstMatch
        XCTAssertTrue(staged.waitForExistence(timeout: 10), "the PDF was not staged in the message")
        // The chat's own card: its + and its model chip, and no context ring before a chat exists.
        XCTAssertTrue(app.buttons["newchat.attach"].firstMatch.exists, "no + on the message")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "composer.modelChip").firstMatch.exists, "no model chip on the message")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "composer.context").firstMatch.exists, "a context ring before the chat exists")
        let field = app.textViews["newchat.text"].firstMatch
        field.tap()
        field.typeText("Here is the brief.")
        shot("newmessage-one-bot")
        app.buttons["newchat.send"].firstMatch.tap()
        // The chat opens with the message and its file.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chat.dock").firstMatch.waitForExistence(timeout: 30), "the chat did not open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Here is the brief.")).firstMatch.waitForExistence(timeout: 20), "the first message is not in the chat")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "brief.pdf")).firstMatch.waitForExistence(timeout: 20),
                      "the file did not go with the first message")
        shot("newmessage-one-bot-sent")
    }

    func testSeveralBotsStartAGroupWithTheWordsOnly() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        continueAfterFailure = false
        try openSheet(url: url, token: token)
        try choose("default")
        try choose("work")
        XCTAssertTrue(app.staticTexts["New Group Chat"].firstMatch.waitForExistence(timeout: 5), "two bots did not make a group")
        // Words and "@" only: no +, no model chip, and the staged file is said to stay behind.
        XCTAssertFalse(app.buttons["newchat.attach"].firstMatch.exists, "a + on a group's message")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "composer.modelChip").firstMatch.exists, "a model chip on a group's message")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Attachments go with a chat to one bot")).firstMatch.exists,
                      "no word that the file stays behind")
        let field = app.textViews["newchat.text"].firstMatch
        field.tap()
        field.typeText("@all what is the plan for the release?")
        shot("newmessage-group")
        app.buttons["newchat.send"].firstMatch.tap()
        let header = app.buttons["group.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 30), "the group chat did not open")
        XCTAssertTrue(header.label.contains("Default and Work"), "the header does not name the members: \(header.label)")
        shot("newmessage-group-sent")
    }
}
