import XCTest

/// The thread's follow lock (#329): a reader at the end follows a long reply to its end; a reader
/// up the thread who sends a message lands at the end and follows again; and the keyboard coming
/// up while the reader is up the thread does not move the rows being read.
///
/// Skipped unless HERMES_E2E_URL / HERMES_E2E_TOKEN are set (the mock: `long <s>`, `marathon <n>`,
/// `files`). HERMES_E2E_BUNDLE=com.vorantx.vory.demo drives the demo copy.
@MainActor
final class ChatFollowUITests: XCTestCase {
    private var app: XCUIApplication!

    private var env: (String, String)? {
        let e = ProcessInfo.processInfo.environment
        guard let u = e["HERMES_E2E_URL"], let t = e["HERMES_E2E_TOKEN"], !u.isEmpty, !t.isEmpty else { return nil }
        return (u, t)
    }

    private func launch(url: String, token: String) {
        if let bundle = ProcessInfo.processInfo.environment["HERMES_E2E_BUNDLE"], !bundle.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundle)
            app.launchArguments = ["-vory-demo-gateway", url, token, "Workshop", "-companionPromptShown", "YES"]
        } else {
            app = XCUIApplication()
        }
        app.launch()
    }

    private func pause(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    private func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func text(_ fragment: String) -> XCUIElementQuery { app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)) }
    private var arrow: XCUIElement { app.buttons.matching(NSPredicate(format: "label == 'Jump to latest'")).firstMatch }
    private var dock: XCUIElement { app.otherElements["chat.dock"].firstMatch }
    /// The turn's statistics line under a finished reply.
    private var finished: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Turn statistics'")).firstMatch }

    private func newChat(url: String, token: String) {
        launch(url: url, token: token)
        let newChat = app.buttons["chats.new"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 40))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: newChat)], timeout: 60)
        newChat.tap()
    }

    private func send(_ prompt: String) {
        let composer = app.textViews["composer.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText(prompt)
        let send = app.buttons.matching(identifier: "composer.send").firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "no send button")
        send.tap()
    }

    /// The bottom of the thread's lowest row.
    private func lowestRowBottom() -> CGFloat? {
        guard let snap = try? app.snapshot() else { return nil }
        var bottom: CGFloat?
        func walk(_ s: XCUIElementSnapshot) {
            if s.identifier.hasPrefix("thread."), s.frame.height > 0 { bottom = max(bottom ?? -.infinity, s.frame.maxY); return }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return bottom
    }

    /// A row of words on screen whose text is nowhere else in the tree, to find again.
    private func mark() -> (label: String, y: CGFloat)? {
        guard let snap = try? app.snapshot() else { return nil }
        let window = app.windows.firstMatch.frame
        var seen: [String: Int] = [:]
        func count(_ s: XCUIElementSnapshot) {
            if s.elementType == .staticText { seen[s.label.lowercased(), default: 0] += 1 }
            for c in s.children { count(c) }
        }
        count(snap)
        var found: (String, CGFloat)?
        func walk(_ s: XCUIElementSnapshot) {
            guard found == nil else { return }
            if s.elementType == .staticText, s.label.count >= 12, !s.label.contains("…"),
               s.frame.minY > window.minY + 140, s.frame.maxY < window.maxY - 220,
               seen.filter({ $0.key.contains(s.label.lowercased()) }).values.reduce(0, +) == 1 {
                found = (s.label, s.frame.minY); return
            }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return found
    }

    /// The keyboard on screen (XCTest goes on listing it below the screen once it has gone).
    private var keyboardUp: Bool {
        let k = app.keyboards.firstMatch
        return k.exists && k.frame.minY < app.frame.height - 20
    }

    /// The keyboard down: a drag from just above the dock to the bottom of the screen pulls it
    /// away interactively (a swipe in the thread's middle only scrolled).
    private func keyboardDown() {
        guard keyboardUp else { return }
        let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: dock.frame.minY - 12))
        let to = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height - 4))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
        pause(1)
    }

    /// A reader at the end keeps the end of a long streamed reply in view, to its last word, with
    /// no jump arrow.
    func testAReaderAtTheEndFollowsALongReply() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        newChat(url: url, token: token)
        send("long 12")
        XCTAssertTrue(text("Step 1.").firstMatch.waitForExistence(timeout: 20), "the reply did not start")
        pause(5)
        // Mid-stream: the newest words sit just above the dock.
        let midBottom = try XCTUnwrap(lowestRowBottom(), "no rows")
        print("CHAT-FOLLOW mid-stream lowest row \(Int(midBottom)) dock \(Int(dock.frame.minY))")
        XCTAssertFalse(arrow.exists, "the jump arrow showed while following")
        XCTAssertTrue(finished.waitForExistence(timeout: 40), "the reply did not finish")
        pause(1.5)
        shot("follow-end")
        let bottom = try XCTUnwrap(lowestRowBottom(), "no rows")
        let gap = dock.frame.minY - bottom
        print("CHAT-FOLLOW at the end: lowest row \(Int(bottom)) dock \(Int(dock.frame.minY)) gap \(Int(gap))")
        XCTAssertGreaterThanOrEqual(gap, 4, "the reply's end is under the dock")
        XCTAssertLessThan(gap, 160, "the thread stopped short of the reply's end")
        XCTAssertFalse(arrow.exists, "the jump arrow shows at the end of a followed reply")
    }

    /// Up the thread, a sent message brings it back to the end and it follows the reply.
    func testSendingWhileScrolledUpLandsAtTheEnd() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        newChat(url: url, token: token)
        send("marathon 30")
        XCTAssertTrue(text("Everything else looked healthy").firstMatch.waitForExistence(timeout: 90), "the long turn did not finish")
        pause(1.5)
        keyboardDown()
        for _ in 0..<3 { app.swipeDown(velocity: .slow) }
        pause(1)
        XCTAssertTrue(arrow.waitForExistence(timeout: 3), "no jump arrow while up the thread")
        shot("send-up-the-thread")
        send("files")
        XCTAssertTrue(text("The report is ready").firstMatch.waitForExistence(timeout: 15), "no reply")
        pause(2)
        shot("send-after-reply")
        let reply = text("The report is ready").firstMatch
        print("CHAT-FOLLOW reply at \(reply.frame) dock \(dock.frame.minY) arrow \(arrow.exists)")
        XCTAssertTrue(reply.frame.maxY < dock.frame.minY && reply.frame.minY > 0, "the new reply is not on screen above the dock")
        XCTAssertFalse(arrow.exists, "still away from the end after sending")
    }

    /// Up the thread, the keyboard coming up leaves the rows being read where they are.
    func testTheKeyboardUpTheThreadKeepsTheRows() throws {
        guard let (url, token) = env else { throw XCTSkip("HERMES_E2E_URL / HERMES_E2E_TOKEN not set") }
        newChat(url: url, token: token)
        send("marathon 30")
        XCTAssertTrue(text("Everything else looked healthy").firstMatch.waitForExistence(timeout: 90), "the long turn did not finish")
        pause(1.5)
        keyboardDown()
        XCTAssertFalse(keyboardUp, "the keyboard did not go down")
        app.swipeDown(velocity: .slow); app.swipeDown(velocity: .slow)
        pause(1.5)
        let held = try XCTUnwrap(mark(), "no row to hold")
        print("CHAT-FOLLOW held \(held.label.prefix(40)) at \(Int(held.y))")
        app.textViews["composer.text"].firstMatch.tap()
        pause(1.5)
        XCTAssertTrue(keyboardUp, "the keyboard did not come up")
        shot("keyboard-up-the-thread")
        let after = text(held.label).firstMatch
        print("CHAT-FOLLOW after the keyboard: \(after.exists ? Int(after.frame.minY) : -1)")
        XCTAssertTrue(after.exists, "the row held is gone")
        XCTAssertEqual(after.frame.minY, held.y, accuracy: 24, "the keyboard moved the rows being read by \(Int(after.frame.minY - held.y)) pt")
    }
}
