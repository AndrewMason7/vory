import XCTest

/// #378: a chat opened from Home's "Pick up where you left off" opens with the chat's bar (its
/// Back, its bot, its actions) as from the Chats list, not with a bare Back that came only at the
/// end of the push, and its Back comes back to Home. Another bot's Bot Chat too (it selects its
/// bot). Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set; HERMES_E2E_BUNDLE picks the
/// copy to drive (the demo copy by default).
@MainActor
final class HomePickUpUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func mark(_ what: String) { print(String(format: "C378 %.1f %@", Date().timeIntervalSince1970, what)) }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let folder = ProcessInfo.processInfo.environment["HERMES_E2E_SHOTS"].flatMap { $0.isEmpty ? nil : $0 }
        let d = folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hermes-chat-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: d.appendingPathComponent("\(name).png"))
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func launch() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.vorantx.vory.demo"
        app = XCUIApplication(bundleIdentifier: bundle)
        // Every bot's chats on Home, so another bot's Bot Chat is in Pick up.
        app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES", "-home.allBots", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["chats.new"].firstMatch.waitForExistence(timeout: 40), "no chat list")
    }

    /// What the top of the screen holds a moment after a chat opens from Home: by a second the
    /// chat's bar, never the "New chat" stand-in for its title.
    private func watchOpening(_ name: String) {
        let opened = Date()
        for at in [0.2, 0.5, 1.0, 2.0] {
            let wait = at - Date().timeIntervalSince(opened)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let seen = ["chat.header", "morph.bar", "page.back", "chat.back", "chat.dock"].filter { any($0).exists }
            // The pill reads "Chat info: <title>, <subtitle>".
            let pill = any("chat.header").buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chat info: '")).firstMatch
            let label = pill.exists ? pill.label : ""
            let stand = label.hasPrefix("Chat info: New chat")
            mark("\(name) +\(at) s: \(seen.joined(separator: " ")) [\(label)]")
            shot("c378-\(name)-\(at)")
            XCTAssertFalse(stand, "\(name): the header read New chat at +\(at) s")
            if at >= 1.0 { XCTAssertTrue(any("chat.header").exists, "\(name): no chat bar at +\(at) s") }
        }
    }

    private func openFromHome(_ fragment: String, _ name: String) {
        let home = any("tab.dashboard")
        XCTAssertTrue(home.waitForExistence(timeout: 10), "no Home tab")
        home.tap()
        XCTAssertTrue(app.staticTexts["Pick up where you left off"].firstMatch.waitForExistence(timeout: 20), "no Pick up card")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no \(fragment) in Pick up")
        sleep(1)
        mark("tap \(name)")
        row.tap()
        watchOpening(name)
    }

    private func back() {
        for id in ["page.back", "chat.back"] where any(id).exists && any(id).isHittable {
            any(id).tap(); sleep(2); return
        }
    }

    /// Back from a chat opened from Home lands on Home.
    private func backToHome(_ name: String) {
        back()
        let onHome = app.staticTexts["Pick up where you left off"].firstMatch.waitForExistence(timeout: 5) && app.staticTexts["Pick up where you left off"].firstMatch.isHittable
        mark("\(name) back: \(onHome ? "on Home" : "not on Home")")
        shot("c378-\(name)-back")
        XCTAssertTrue(onHome, "\(name): Back did not come back to Home")
    }

    func testAChatOpenedFromPickUpHasItsBar() throws {
        try launch()
        // The current bot's chat first, then another bot's Bot Chat (which switches the bot).
        openFromHome("Disk cleanup", "chat")
        backToHome("chat")
        openFromHome("Bot Chat", "botchat")
        backToHome("botchat")
        mark("back on Home")
    }

    /// The Bot Chat as the first chat opened from Home after the launch.
    func testABotChatOpenedFirstFromPickUpHasItsBar() throws {
        try launch()
        openFromHome("Bot Chat", "botfirst")
        backToHome("botfirst")
        mark("back on Home")
    }

    /// The accessibility audit on Home, failing only on the Pick up rows (the change): each is one
    /// described button a finger and VoiceOver can reach.
    func testHomePickUpAuditClean() throws {
        try launch()
        let home = any("tab.dashboard")
        XCTAssertTrue(home.waitForExistence(timeout: 10), "no Home tab")
        home.tap()
        let card = app.staticTexts["Pick up where you left off"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no Pick up card")
        let rows = ["Disk cleanup", "Bot Chat", "nightly export"].map { app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", $0)).firstMatch }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 15), "no Pick up rows")
        // The card on screen: the audit looks at what is shown.
        var swipes = 0
        while !(rows.last { $0.exists }?.isHittable ?? true), swipes < 4 { app.swipeUp(velocity: .slow); swipes += 1 }
        sleep(1)
        let region = rows.filter { $0.exists }.map { $0.frame }.reduce(card.frame) { $0.union($1) }
        for r in rows where r.exists { print("C378-ROW '\(r.label)' frame \(r.frame) hittable \(r.isHittable)") }
        var flagged: [String] = []
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .elementDetection]) { issue in
            guard let el = issue.element else { print("C378-AUDIT '\(issue.compactDescription)' no element"); return true }
            let line = "'\(issue.compactDescription)' type \(el.elementType.rawValue) id '\(el.identifier)' label '\(el.label)' frame \(el.frame)"
            print("C378-AUDIT \(line)")
            if region.intersects(el.frame), el.frame.width < region.width + 1 { flagged.append(line) }
            return true
        }
        XCTAssertTrue(flagged.isEmpty, "the audit flags Pick up: \(flagged)")
    }

    /// A chat left open on Chats, Home from the Overview widget's link, another chat from Pick up:
    /// before #378 it was pushed on Home with a stuck bar (Home's title, no Back, no bot). It opens
    /// on Chats over the first, Back goes to the first with its bar, and Back again to Home.
    func testAChatFromHomeOverAnOpenChatGoesBackThroughIt() throws {
        try launch()
        let chats = any("tab.chats")
        XCTAssertTrue(chats.waitForExistence(timeout: 10), "no Chats tab")
        chats.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "nightly export")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no nightly export chat in the list")
        row.tap()
        XCTAssertTrue(any("chat.header").waitForExistence(timeout: 10), "the first chat has no chat bar")
        sleep(2)
        shot("c386-1-first-chat")
        // What the Overview widget opens: Home, with the chat left open on Chats.
        app.open(URL(string: "vory://home")!)
        XCTAssertTrue(app.staticTexts["Pick up where you left off"].firstMatch.waitForExistence(timeout: 20), "no Home")
        sleep(1)
        openFromHome("Disk cleanup", "over")
        back()
        let first = any("chat.header").buttons.matching(NSPredicate(format: "label CONTAINS[c] 'nightly export'")).firstMatch
        let onFirst = first.waitForExistence(timeout: 5)
        mark("over back: \(onFirst ? "on the first chat" : "not on the first chat")")
        shot("c386-2-first-again")
        XCTAssertTrue(onFirst, "Back did not come to the chat left open, with its bar")
        backToHome("over-first")
    }
}
